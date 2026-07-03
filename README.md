# Pharma MES Batch, OEE & Quality Reporting

A **production-ready analytics pipeline** for pharmaceutical batch quality, OEE (Overall Equipment Effectiveness), and equipment downtime analysis.

**Status:** Data loading + staging layer (in progress)
**Tech Stack:** Python (ingestion) → dbt (transformation) → Azure SQL → Metabase (dashboards)

---

## Quick Start (Local Development)

### 1. Prerequisites
- Python 3.11+
- ODBC Driver 18 for SQL Server (Windows)
- Azure SQL database (free tier)
- Kaggle account (for dataset access)

### 2. Setup
```bash
# Clone repo
git clone <repo>
cd pharma-mes-batch-oee-reporting-vvp1

# Install dependencies
pip install pandas pyodbc python-dotenv kaggle dbt-sqlserver

# Set up Kaggle credentials
# Go to https://www.kaggle.com/settings/account
# Create Legacy API Key, save to ~/.kaggle/kaggle.json
# Or add to .env: KAGGLE_USERNAME=... KAGGLE_KEY=...

# Copy env template and fill in Azure SQL details
cp .env.example .env
# Edit .env with your Azure SQL credentials
```

### 3. Run the pipeline locally
```bash
# Load data from Kaggle → Azure SQL (raw layer as JSON)
python ingestion/load_to_azure_sql.py

# Transform data (dbt)
cd dbt
dbt deps
dbt build
```

---

## Project Structure

```
pharma-mes-batch-oee-reporting-vvp1/
├── README.md                  # This file
├── ROADMAP.md                 # Implementation roadmap & next steps
├── .env.example               # Template for local credentials
├── ingestion/
│   └── load_to_azure_sql.py   # Download from Kaggle → Azure SQL raw layer
├── dbt/
│   ├── models/
│   │   ├── staging/           # Clean, parse raw data
│   │   └── marts/             # OEE, quality, downtime facts
│   ├── tests/                 # Data quality tests
│   └── dbt_project.yml
├── .github/workflows/
│   └── pipeline.yml           # GitHub Actions: daily load + dbt build
└── data/                      # (git-ignored) Raw CSVs from Kaggle
```

---

## Data Architecture

```
Kaggle Datasets
   │
   ├─ Laboratory.csv (batch quality)
   └─ Process/ (15 Excel files → consolidated)
          │
          ↓
   Python Loader (ingestion/load_to_azure_sql.py)
          │
          ↓
   Azure SQL: raw schema (JSON documents)
   ├─ raw.laboratory
   └─ raw.process_timeseries
          │
          ↓
   dbt Staging Layer (stg_*)
   ├─ stg_laboratory
   └─ stg_process_timeseries
          │
          ↓
   dbt Marts Layer (fct_*, dim_*)
   ├─ fct_batch_quality
   ├─ fct_oee_daily
   ├─ fct_downtime_analysis
   └─ dim_* (batch, equipment, date)
          │
          ↓
   Metabase Dashboards
   ├─ Equipment OEE & Availability
   ├─ Batch Quality Overview
   └─ Downtime Impact Analysis
```

---

## Key Metrics

### OEE (Overall Equipment Effectiveness)
```
OEE = Availability × Performance × Quality
    = (uptime / total_time) × (actual_output / planned_output) × (good_units / total_units)
```

### Quality Score
Composite metric from CQAs (Critical Quality Attributes):
- Dissolution (%)
- Impurities (%)
- Yield (%)
- Hardness, tensile strength

### Availability
```
Availability = uptime_minutes / (uptime_minutes + downtime_minutes)
```

---

## Data Sources

**Laboratory.csv** — Batch quality data
- 1,005 batches of cholesterol-lowering tablets (Nov 2018 - Apr 2021)
- 55 columns: batch ID, product, incoming material quality, intermediate/final QC results
- Source: Kaggle (darvinsures/pharma-batch-quality-and-process-data)
- License: CC BY-SA 4.0

**Process Files (1-15)** — Equipment time-series
- Per-equipment state logs (running, idle, downtime)
- Downtime reasons (maintenance, mechanical, electrical)
- Consolidated into single CSV by loader
- Source: Same Kaggle dataset
- License: CC BY-SA 4.0

---

## GitHub Actions CI/CD

Pipeline runs **daily at 2 AM UTC**:
1. Download latest data from Kaggle
2. Load to Azure SQL raw layer
3. Run dbt transformations
4. Publish results

**Secrets required** (set in repo Settings):
- `KAGGLE_USERNAME`, `KAGGLE_KEY`
- `AZURE_SQL_SERVER`, `AZURE_SQL_DB`, `AZURE_SQL_USER`, `AZURE_SQL_PASSWORD`

---

## Development Workflow

```bash
# Make changes to dbt models
vim dbt/models/staging/stg_laboratory.sql

# Test locally
cd dbt
dbt run --select stg_laboratory
dbt test --select stg_laboratory

# Push to GitHub (CI/CD runs automatically)
git add .
git commit -m "feat: update laboratory staging model"
git push origin main
```

---

## Next Steps

See **[ROADMAP.md](./ROADMAP.md)** for full implementation plan.

**Current focus:** Get data loader working, then build dbt staging layer.

---

## Support & Questions

- **Data loads but tests fail?** Check `dbt test` output, fix in staging layer
- **Kaggle download fails?** Verify credentials in `.env` or GitHub Secrets
- **Azure SQL timeout?** Check database is resumed (free tier auto-pauses)
- **Metabase dashboards slow?** Check dbt marts are materialized (or add indexes)

---

## License

Data: CC BY-SA 4.0 (Kaggle)
Code: MIT (your organization)

**Attribution:** Dataset by darvinsures on Kaggle. Original research: figshare collection 10.6084/m9.figshare.c.5645578
