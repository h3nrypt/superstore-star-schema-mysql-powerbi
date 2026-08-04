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

## 5. `dim_geography` was built at the wrong grain — rebuilt as `dim_geography_city`

**What happened:** a duplicate check on `dim_geography` (normalizing
city/state casing) returned multiple `geography_key` values for the
same city — e.g. 3 rows for Chicago, 6 for Los Angeles, 4 for Houston.

**Root cause:** the original table was built with:

```sql
INSERT INTO dim_geography (country, region, state, city, postal_code)
SELECT DISTINCT country, region, state, city, postal_code
FROM stg_superstore;
```

`postal_code` was included in the `DISTINCT` before the table's
intended grain was explicitly decided. Chicago genuinely has multiple
ZIP codes in the source data, so each one produced its own row and its
own surrogate key — this wasn't corrupted data, every "duplicate"
traced back to a real, different postal code:

```
city, state, postal_code, geography_key
'Chicago', 'Illinois', '60610', '27'
'Chicago', 'Illinois', '60623', '37'
'Chicago', 'Illinois', '60653', '156'
```

**Confirmed:** ZIP-level detail wasn't needed by any planned report or
dashboard — city-level was sufficient. The table was rebuilt as
`dim_geography_city` at city/state/country grain (Step 6 in
`sql/superstore_star_schema.sql`), and `fact_sales.geography_key` was
remapped by joining through `stg_superstore` — the only table that
still had row-level city/state/country, since `fact_sales` itself only
stores the surrogate key.

**Two errors hit during the rebuild, worth recording separately:**

- `Error Code: 2013. Lost connection to MySQL server during query` —
  hit mid-remap. Ruled out server timeouts (all timeout variables were
  generous) and missing indexes (both tables involved were indexed,
  and at this dataset's scale — `fact_sales`: 10,426 rows;
  `stg_superstore`: 5,009; `dim_geography_city`: 604 — a 3-table join
  runs in milliseconds regardless of indexing). Concluded it was a
  transient client/connection drop; re-running the identical query
  completed successfully.
- `Error Code: 3730. Cannot drop table 'dim_geography' referenced by a
  foreign key constraint 'fact_sales_ibfk_5' on table 'fact_sales'` —
  hit when retiring the old table. The fact table's data had already
  been remapped to the new dimension, but the foreign key constraint
  was still physically pointed at the old table. Fixed by dropping the
  old constraint and adding a new one against `dim_geography_city`
  before dropping the old table:

```sql
ALTER TABLE fact_sales DROP FOREIGN KEY fact_sales_ibfk_5;

ALTER TABLE fact_sales
ADD CONSTRAINT fk_fact_geography_city
FOREIGN KEY (geography_key) REFERENCES dim_geography_city(geography_key);

DROP TABLE dim_geography;
```

**Lesson:** decide a dimension's grain on paper before writing the
`SELECT DISTINCT` that builds it — a diagnostic query run without a
declared expected grain will keep flagging correct design decisions as
bugs. Separately: updating the data a foreign key references doesn't
move the constraint itself; it has to be dropped and recreated against
the new parent table explicitly, and a "lost connection" error at
small table sizes is almost always environmental, not a performance
problem worth optimizing around.

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

## Date column missing from Report View

**Symptom:** `dim_date[date]` column exists in Data view with correct Date data 
type, but does not appear in the Fields pane in Report view.

**Root cause:** The column had "Hide in Report View" enabled — a flag independent 
of the column's existence in the model. Hidden columns remain fully usable in DAX 
(time intelligence functions like DATEADD continued working) but are suppressed 
from the Report view Fields pane and drag-and-drop.

**Fix:** Model view → select `dim_date` table → right-click the `date` column → 
toggle off "Hide in Report View." Alternatively via Data view, same right-click 
path.

**Note:** This is often intentional design — hiding raw date columns and exposing 
only Year/Month/Quarter hierarchy for slicers is common practice. Confirm before 
assuming it's a bug.




