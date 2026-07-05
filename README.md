# Pharma MES Batch, OEE & Quality Reporting

A unified reporting and analytics layer for pharmaceutical batch quality, OEE (Overall Equipment Effectiveness), and equipment downtime — built as a Value Validation Project demonstrating the BI & Data Engineer skill set: dimensional modeling, a modern transform stack (dbt), query tuning at scale, and production dashboards in Metabase.

**Tech stack:** Python (ingestion) → Azure SQL (raw/staging/marts) → dbt Core (transformation) → Metabase (dashboards)

---

## What this demonstrates

- **Dimensional modeling**: star schema (`dim_equipment`, `dim_product`, `dim_date` against `fct_batch`, `fct_oee_by_batch`, `fct_downtime_analysis`, `fct_batch_downtime_proximity`)
- **Query tuning at scale**: three measured before/after performance stories on a 4.7M-row source table (see [Query Tuning](#query-tuning) below)
- **Data quality engineering**: real bugs found and fixed against real data — a NaN-to-invalid-JSON failure, a cumulative-counter metric misread, mixed timestamp formats across source files — not a clean synthetic dataset

## Architecture

```
Kaggle: darvinsures/pharma-batch-quality-and-process-data
   │
   ├─ Laboratory.csv           (1,005 batches, quality/CQA data)
   └─ Process/Process/*.csv    (25 files, one per press/equipment line —
                                 each row's 'code' column matches its filename)
          │
          ↓  ingestion/load_to_azure_sql.py
          │  (NaN → null sanitization, fast_executemany bulk insert)
          ↓
Azure SQL — raw schema (JSON documents, zero transformation)
   ├─ raw.laboratory
   └─ raw.process_timeseries
          │
          ↓  dbt staging (OPENJSON parsing, mixed timestamp handling)
          │
   staging.stg_laboratory
   staging.stg_process_timeseries
   staging.int_batch_production   (cumulative counters → per-batch totals)
          │
          ↓  dbt marts
          │
   marts.dim_equipment, dim_product, dim_date
   marts.fct_batch              (quality_score, 0–100, relative composite)
   marts.fct_oee_by_batch       (batch-grain OEE, per OEE Academy guidance)
   marts.fct_downtime_analysis  (10 min – 24 hr capped downtime events)
   marts.fct_batch_downtime_proximity
          │
          ↓
Metabase Dashboards
   ├─ Equipment OEE & Availability
   └─ Downtime Impact on Quality
---

## Key metrics — and their honest limitations

**OEE** = Availability × Performance × Quality, computed **per batch** (not per calendar day — long-running batches don't fit cleanly into daily buckets; see [OEE Academy guidance](https://oee.academy/oee-academy/oee-calculation-faq/oee-long-batches/) on why per-batch is the correct measurement window). Availability and Performance are proxies (reading-based running proportion; speed relative to that batch's own observed max) since the source data has no rated/nameplate capacity or planned-downtime reference — treat these as internally consistent for comparing equipment against each other, not as calibrated industry-standard figures.

**quality_score** (0–100) is a **relative** composite of `dissolution_average`, `total_impurities`, `residual_solvent`, and `batch_yield`, min-max normalized against the 1,005 batches actually observed. There are no real regulatory spec limits (USP, ICH) in this public dataset, so this ranks batches against each other — it is not a compliance/spec-conformance score.

**Downtime** is capped to 10 minutes–24 hours per event. Gaps longer than 24 hours are between-campaign idle time, not equipment failure, and are excluded. **There is no downtime-reason classification anywhere in the source data** — every process file was checked, none has a reason/category column. Dashboard 2's downtime breakdown is by equipment and duration, not by cause.

```
---

## Query tuning

| Change | Before | After | Technique |
|---|---|---|---|
| `stg_process_timeseries` JSON parsing | 468.56s | _[fill in after rerun]_ | 17× `JSON_VALUE()` per row → single `OPENJSON ... WITH` parse |
| Ad-hoc aggregation vs. pre-built mart | _[time against raw 4.7M rows]_ | _[time against fct_oee_by_batch, ~1,900 rows]_ | Pre-aggregated mart layer — Metabase never queries raw readings directly |


---

## Prerequisites

- Python 3.11+
- [Microsoft ODBC Driver 18 for SQL Server](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server)
- Docker (for local Metabase)
- An Azure SQL database (free tier is sufficient)
- A Kaggle account with API credentials
- `dbt-core` and `dbt-sqlserver` (installed separately from the ingestion requirements — see below)

---

## Setup and reproducibility

```bash
git clone https://github.com/dsures/pharma-mes-batch-oee-reporting-vvp1.git
cd pharma-mes-batch-oee-reporting-vvp1

# Python dependencies for the ingestion loader
pip install -r ingestion/requirements.txt

# dbt (separate install — not in ingestion/requirements.txt)
pip install dbt-core dbt-sqlserver

# Configure credentials — one .env at the project root (not inside pharma_analytics/)
cp .env.example .env
# Fill in: AZURE_SQL_SERVER, AZURE_SQL_DB, AZURE_SQL_USER, AZURE_SQL_PASSWORD,
#          KAGGLE_DATASET

# Authenticate the Kaggle CLI separately (not handled by the Python script —
# download is a manual/CI step, kept out of application code by design)
# Get your API token from kaggle.com -> Settings -> API -> Create New Token
# Save the downloaded kaggle.json to ~/.kaggle/kaggle.json

# Download the dataset
kaggle datasets download -d darvinsures/pharma-batch-quality-and-process-data -p data --unzip

# Load raw data into Azure SQL (loads a JSON landing zone, full volume, no sampling)
python ingestion/load_to_azure_sql.py

# Build the dbt project
cd pharma_analytics
dbt deps
dbt build
```

`dbt` reads Azure SQL credentials via `env_var()` in `profiles.yml`, which only sees actual OS environment variables — it does **not** read `.env` files automatically. Before running any `dbt` command, load the root `.env` into your shell session, e.g. in PowerShell:
```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
    }
}
```

### Running tests
```bash
cd pharma_analytics
dbt test
```

### Local Metabase
```bash
docker-compose up -d
```
Open `http://localhost:3000`, complete first-run setup, then add Azure SQL as a database connection (Admin → Databases → Add a database → SQL Server). Your Azure SQL firewall must allow your local IP — add a firewall rule in the Azure Portal under the SQL server's Networking settings if you get a connection-refused error.

---

## CI/CD

`.github/workflows/pipeline.yml` runs the full pipeline (Kaggle download → raw load → dbt staging → dbt marts → dbt tests) as separately visible stages, triggered manually (`workflow_dispatch`) rather than on a schedule — this is a static historical dataset, so a daily rebuild would burn Azure free-tier compute for no new data. Requires these GitHub Secrets: `KAGGLE_USERNAME`, `KAGGLE_KEY`, `AZURE_SQL_SERVER`, `AZURE_SQL_DB`, `AZURE_SQL_USER`, `AZURE_SQL_PASSWORD`.

---

## Dashboards

### Equipment OEE & Availability
<img width="1260" height="766" alt="image" src="https://github.com/user-attachments/assets/41284614-9569-4938-87f8-0d63cbf75973" />


### Downtime Impact on Quality
<img width="1358" height="532" alt="image" src="https://github.com/user-attachments/assets/2eae153a-6aca-4612-a195-c2936ee15c69" />

---

## Data sources and attribution

- **Laboratory.csv** — 1,005 batches, cholesterol-lowering tablets, Nov 2018–Apr 2021, 55 columns of batch/quality data.
- **Process/Process/*.csv** — 25 files, one per tablet press, continuous per-second/per-minute telemetry across many batches and campaigns.
- **Source:** [Kaggle: darvinsures/pharma-batch-quality-and-process-data](https://www.kaggle.com/datasets/darvinsures/pharma-batch-quality-and-process-data), originally from the [figshare collection](https://figshare.com/collections/Big_data_collection_in_pharmaceutical_manufacturing/5645578) (DOI: 10.6084/m9.figshare.c.5645578), CC BY-SA 4.0.

## License

Code: MIT. Data: CC BY-SA 4.0 — attribution required, see above.
