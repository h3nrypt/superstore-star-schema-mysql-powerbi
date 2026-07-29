# Architecture & Design Decisions

## Method: staging → dimensions → fact

Never build dimension tables directly from a raw CSV import. The
staging table (`stg_superstore`) is a 1:1 mirror of the source file,
untouched. Every dimension and the fact table are built *from* staging
via `SELECT DISTINCT` / `JOIN`, not from the file directly. This means
if something downstream is wrong, you have an untouched copy of the
source to diagnose against — you're never debugging a transformation
and a load error at the same time.

## Why surrogate keys on three of the four dimensions

`dim_product`, `dim_customer`, and `dim_geography` all use an
auto-incrementing surrogate key (`product_key`, `customer_key`,
`geography_key`) instead of the natural ID from the source file
(`Product ID`, `Customer ID`, etc.).

The concrete reason, not a "best practice" cliché: **`Product ID` is
not actually unique to one product name in this dataset.** The same
Product ID occasionally appears against two different Product Names —
a real data quality issue in the source file, not a hypothetical. Using
`product_id` as a primary key would throw duplicate-key errors or
silently drop rows on insert. A surrogate key sidesteps the problem
entirely and is standard dimensional-modeling practice regardless —
natural keys can change or be reused by a source system; surrogate keys
never do.

Proof query (included in `sql/superstore_star_schema.sql`, Step 4):

```sql
SELECT product_id, COUNT(DISTINCT product_name) AS name_variants
FROM stg_superstore
GROUP BY product_id
HAVING COUNT(DISTINCT product_name) > 1;
```

## Why `dim_date` is a continuous calendar, not just distinct order dates

`dim_date` is generated as every single calendar day between the
earliest `order_date` and the latest `ship_date` in the dataset — not
just the dates that happen to appear in an order. This is a
requirement, not a preference: Power BI's time-intelligence DAX
functions (`SAMEPERIODLASTYEAR`, `DATEADD`, gap/trend analysis) assume
a continuous date table. A date table with gaps produces silently wrong
results for those functions, not an error.

## The role-playing dimension: `order_date` and `ship_date`

`fact_sales` has two foreign keys pointing at the same `dim_date`
table — one for `order_date`, one for `ship_date`. This is called a
**role-playing dimension**: one physical table serving two logical
roles.

This has a direct consequence in Power BI: only one of the two
relationships between `fact_sales` and `dim_date` can be *active* at a
time. The other is inactive by default. Two ways to handle it:

- Use `USERELATIONSHIP()` inside any DAX measure that needs to filter
  or group by ship date instead of order date.
- Build a second, physically separate date table (`dim_ship_date`, a
  duplicate of `dim_date`) so both relationships can be active
  simultaneously without DAX gymnastics.

Neither is objectively "correct" — it's a modeling trade-off you should
be able to explain, not something to leave to Power BI's autodetect.

## Grain of `fact_sales`

Grain = one row per `Row ID` from the source file, i.e. one row per
order line item. This is stated explicitly because grain is the single
most important design decision in a fact table, and being unable to
state it plainly is a common interview red flag.
