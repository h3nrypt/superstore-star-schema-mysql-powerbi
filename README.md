# Superstore Star Schema — MySQL to Power BI

A dimensional data model (star schema) built from the Sample Superstore
sales dataset, using MySQL as the staging/transformation layer and
Power BI as the reporting layer.

This repo isn't just the finished script. It documents the actual build
process, including the mistakes made and root-caused along the way —
because knowing *why* a step exists is what makes this defensible in an
interview, not just runnable.

## What this project demonstrates

- Star schema design: fact table + conformed dimensions, surrogate keys,
  a role-playing dimension (`dim_date` used twice), and a continuous
  calendar table built for Power BI time-intelligence.
- Data loading via MySQL's native `LOAD DATA LOCAL INFILE`, chosen
  deliberately over a GUI import wizard, and why that choice matters.
- A verification discipline: every load and every join is checked
  against row counts, null counts, and aggregate totals — not assumed
  correct because it "ran."

## Repo structure

See [`docs/01-architecture.md`](docs/01-architecture.md) for the design decisions 
behind the schema — grain, keys, and why three of four dimensions use surrogate keys.

See [`docs/02-troubleshooting.md`](docs/02-troubleshooting.md) for the real build 
errors hit and root-caused during this project.

See [`docs/03-dax-measures.md`](docs/03-dax-measures.md) for the DAX measures 
powering the Sales Growth KPI card and conditional formatting logic.
```
├── README.md
├── superstore_dashboard.pbix
├── sql/
│   └── superstore_star_schema.sql
├── docs/
│   ├── 01-architecture.md
│   ├── 02-troubleshooting.md
│   └── 03-dax-measures.md
└── screenshots/
    └── dashboard-overview.png
```

## Schema overview

| Table            | Grain                              | Key                     |
|-------------------|-------------------------------------|-------------------------|
| `stg_superstore`  | 1 row per CSV line (raw, untouched) | none                     |
| `dim_date`        | 1 row per calendar day              | `date` (natural key)    |
| `dim_product`     | 1 row per distinct product record   | `product_key` (surrogate) |
| `dim_customer`    | 1 row per distinct customer record  | `customer_key` (surrogate) |
| `dim_geography_city` | 1 row per distinct city/state/country | `geography_key` (surrogate) |
| `fact_sales`      | 1 row per order line item           | `row_id`                |

**Note:** `dim_geography_city` replaced an earlier `dim_geography`
built at postal-code grain, which produced multiple rows per city (a
grain the reporting requirement never actually needed). The full
diagnostic trail — how the wrong grain was found, the rebuild, and a
foreign-key constraint hit while retiring the old table — is in
`docs/02-troubleshooting.md`, entry 5.

See `docs/01-architecture.md` for the reasoning behind each of those
grain and key decisions — particularly why three of the four dimensions
use a surrogate key instead of the natural ID from the source file.

## Quick start

1. Clone this repo.
2. Download the Sample Superstore CSV (search "Sample Superstore
   dataset", widely available on Kaggle/Tableau sample data).
3. Open `sql/superstore_star_schema.sql` in MySQL Workbench.
4. Read the comments — the script is written to be read, not just run.
   Each step explains what it does and why.
5. Enable `local_infile` (server + client) before running the
   `LOAD DATA LOCAL INFILE` step — see `docs/02-troubleshooting.md`
   if you hit permission or path errors.
6. Run the script top to bottom, section by section, verifying counts
   at each checkpoint before moving to the next.
7. Connect Power BI (Get Data → MySQL Database), import the five
   model tables (`dim_date`, `dim_product`, `dim_customer`,
   `dim_geography_city`, `fact_sales`), and build relationships
   **manually** — do not trust autodetect, especially for the
   `dim_date` role-playing relationship.

## Known data quirks in this dataset (worth knowing before you build)

- File encoding is Windows-1252, not UTF-8 — it contains non-breaking
  spaces in some product names.
- `Product ID` is not a reliable unique key — the same ID occasionally
  maps to more than one product name in the source file.
- Sales values carry more than 2 decimal places in places — undersizing
  that column silently truncates data instead of erroring.

Full detail and how each was found: `docs/02-troubleshooting.md`.

## License

Personal learning / portfolio project. Use freely.
