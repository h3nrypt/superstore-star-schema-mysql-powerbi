# Troubleshooting Log — Real Errors Hit During This Build

This is documented deliberately, mistakes included. The point of a
third rebuild wasn't to hide that errors happened — it was to
understand each one well enough to explain it, not just fix it and
move on. Every entry below follows the same shape: **what happened →
why it happened → how it was confirmed → the fix.**

The common thread across all four, stated once so it doesn't need
repeating four times: every failure below came from trusting a default
or a GUI tool's behavior instead of verifying the actual data or
actual documentation. That's the transferable lesson — the specific
fixes are dataset- and tool-specific; the instinct to verify isn't.

---

## 1. Row count came back short (9694 instead of 9994) — twice

**What happened:** Using MySQL Workbench's Table Data Import Wizard,
300 rows silently failed to import. Same exact shortfall on a second
attempt after changing the file encoding setting.

**Why that second data point mattered:** the deficit was identical
both times. A random or encoding-related failure would produce a
*different* count each time, or fail completely. An identical,
repeatable shortfall pointed away from encoding and toward something
structural in how the file was being parsed.

**Root cause:** the CSV contains fields with embedded commas and
escaped quotes inside quoted values (e.g. product names like
`"Stur-D-Stor Shelving, Vertical 5-Shelf: 72""H x 36""W"`), which are
valid per the CSV spec (RFC 4180) but are a known weak point in some
versions of Workbench's Import Wizard parser.

**Fix:** switched to `LOAD DATA LOCAL INFILE`, MySQL's native,
RFC-4180-compliant CSV parser, which handles quoted commas and escaped
quotes correctly by construction. Confirmed 9994/9994 rows loaded, 0
skipped, on the first attempt with this method.

**Lesson:** a GUI import tool "succeeding" (no error dialog) isn't the
same as succeeding completely. Always verify count against a known
total, not against "did it show an error."

---

## 2. Character encoding — `cp1252` rejected as "unknown character set"

**What happened:** the CSV was confirmed (by inspecting raw bytes) to
be Windows-1252 encoded, not UTF-8 — it contains non-breaking-space
characters (`0xA0`) inside some product names. Specifying
`CHARACTER SET cp1252` in the `LOAD DATA` statement was rejected by
MySQL as an unrecognized character set name.

**Root cause:** MySQL does not have a character set literally named
`cp1252`. Its charset named `latin1` is, by long-standing MySQL
convention, actually implemented internally as Windows-1252 — not true
ISO-8859-1. So `latin1` was the technically correct name for this
exact encoding, not an approximation or fallback.

**Fix:** `CHARACTER SET latin1` in the `LOAD DATA LOCAL INFILE`
statement.

**Lesson:** don't assume a tool's terminology maps 1:1 onto the
encoding standard's terminology. Verify what a name actually means
inside the specific tool you're using.

---

## 3. `LOAD DATA LOCAL INFILE` — "no such file" with a copy-pasted path

**What happened:** a file path copied directly from Windows File
Explorer (`C:\Users\User\Downloads\Sample - Superstore.csv`) caused a
"file not found" error, even though the file existed exactly at that
location.

**Root cause:** backslash (`\`) is MySQL's escape character inside
string literals. `\U`, `\D`, `\S` etc. inside that path were being
interpreted as escape sequences, not literal path separators — the
resulting string MySQL actually tried to open did not match the real
path at all.

**Fix:** replace backslashes with forward slashes in the path
(`C:/Users/User/Downloads/Sample - Superstore.csv`) — MySQL accepts
forward slashes in Windows paths. (Alternative: escape every backslash
as `\\`, but forward slashes are simpler and less error-prone.)

**Lesson:** a copy-pasted value isn't automatically "safe" just because
it's copied verbatim from the source. The receiving context (a SQL
string literal, in this case) has its own parsing rules that can
silently reinterpret it.

---

## 4. Sales values silently truncated (`1265: Data truncated for column 'sales'`)

**What happened:** after fixing the row-count and path issues, the
load succeeded with 9994/9994 rows and 0 skipped — but returned ~4,000
warnings, all `1265: Data truncated for column 'sales'`.

**Root cause:** the `sales` column was defined as `DECIMAL(10,2)` (2
decimal places), but a meaningful number of source rows carry sales
values computed to 3+ decimal places (e.g. `911.424`, from unit price ×
quantity × discount math upstream in the source data). Values were
being silently rounded on insert, not rejected — a load can report
"0 skipped" and still be quietly wrong.

**Fix:** widened the column to `DECIMAL(10,4)` in both `stg_superstore`
and `fact_sales`, matching the precision already used for `profit`.
Truncated the staging table and reloaded — confirmed 0 warnings on
re-run.

**Lesson:** "0 rows skipped" and "0 warnings" are two different
success conditions. Always check both. A warning is MySQL telling you
it silently altered your data to make it fit — that is a correctness
issue, not a cosmetic one, even though it doesn't stop the load.

---

## Verification checklist used after every load and every join

Run after `stg_superstore` load, and again after `fact_sales` is
populated:

```sql
-- Row counts must match between stages
SELECT COUNT(*) FROM stg_superstore;   -- expect 9994
SELECT COUNT(*) FROM fact_sales;       -- expect 9994

-- Zero orphans expected — a non-zero count means a JOIN condition
-- upstream is wrong for this data
SELECT COUNT(*) FROM stg_superstore s
LEFT JOIN dim_customer c ON c.customer_id = s.customer_id AND c.segment = s.segment
WHERE c.customer_key IS NULL;

-- Totals must match exactly — proves no rows were dropped or
-- duplicated by the JOINs building fact_sales
SELECT
    (SELECT ROUND(SUM(sales),2) FROM stg_superstore) AS staging_total_sales,
    (SELECT ROUND(SUM(sales),2) FROM fact_sales)     AS fact_total_sales;
```

Row count matching is necessary but not sufficient — it confirms rows
arrived, not that they arrived correctly. The total-sales comparison is
what actually confirms correctness.
