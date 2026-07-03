"""
Load pharma data (downloaded manually via the Kaggle CLI) as JSON to Azure SQL raw schema.
- Assumes data/ has already been populated by running the Kaggle CLI yourself:
    kaggle datasets download -d darvinsures/pharma-batch-quality-and-process-data -p data --unzip
- Stores as JSON (schema-flexible landing zone)
- No transformations in raw layer
"""

import os
import glob
import json
import pandas as pd
import pyodbc
from datetime import datetime
from dotenv import load_dotenv
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

load_dotenv()

# Config
DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data')
KAGGLE_DATASET = os.getenv('KAGGLE_DATASET', 'darvinsures/pharma-batch-quality-and-process-data')
SAMPLE_SIZE = int(os.getenv('SAMPLE_SIZE', 250))
DRY_RUN = os.getenv('DRY_RUN', 'false').lower() in ('1', 'true', 'yes')

# The Kaggle zip extracts with a nested duplicate folder: data/Process/Process/*.csv
PROCESS_GLOB = os.path.join(DATA_DIR, 'Process', 'Process', '*.csv')

# Azure SQL
SERVER = os.getenv('AZURE_SQL_SERVER')
DB = os.getenv('AZURE_SQL_DB')
USER = os.getenv('AZURE_SQL_USER')
PWD = os.getenv('AZURE_SQL_PASSWORD')

CONN_STR = f'Driver={{ODBC Driver 18 for SQL Server}};Server=tcp:{SERVER},1433;Database={DB};Uid={USER};Pwd={PWD};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'


def check_data_exists():
    """Verify Laboratory.csv and the process CSVs are already present in data/.
    Does NOT call the Kaggle API — download must be done manually via the CLI:
        kaggle datasets download -d {KAGGLE_DATASET} -p data --unzip
    """
    lab_file = os.path.join(DATA_DIR, 'Laboratory.csv')
    process_files = glob.glob(PROCESS_GLOB)

    if os.path.exists(lab_file) and process_files:
        logger.info(f"✓ Data files found locally ({len(process_files)} process files)")
        return

    missing = []
    if not os.path.exists(lab_file):
        missing.append('Laboratory.csv')
    if not process_files:
        missing.append(f'process CSVs matching {PROCESS_GLOB}')

    raise FileNotFoundError(
        "\n❌ Missing data: " + ", ".join(missing) + "\n"
        "Download it manually first by running:\n"
        f"  kaggle datasets download -d {KAGGLE_DATASET} -p data --unzip\n"
        "(run from the project root, with your Kaggle CLI already authenticated)"
    )


def create_raw_schema():
    """Create raw schema."""
    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM sys.schemas WHERE name = 'raw'")
    if not cursor.fetchone():
        cursor.execute("CREATE SCHEMA [raw]")
        logger.info("Raw schema created")

    conn.commit()
    conn.close()


def read_csv_flexible(path):
    """Read a CSV trying ';' first (this dataset's known delimiter),
    falling back to ',' if that only yields a single column."""
    df = pd.read_csv(path, sep=';', low_memory=False, encoding='utf-8')
    if df.shape[1] <= 1:
        df = pd.read_csv(path, sep=',', low_memory=False, encoding='utf-8')
    return df


def consolidate_process_files():
    """Read every data/Process/Process/*.csv (25 files, one per press/equipment
    line — each file's 'code' column matches its filename number) and
    concatenate into one dataframe, tagging each row with its source filename."""
    files = sorted(
        glob.glob(PROCESS_GLOB),
        key=lambda p: int(os.path.splitext(os.path.basename(p))[0])
        if os.path.splitext(os.path.basename(p))[0].isdigit() else p
    )

    if not files:
        raise FileNotFoundError(f"No process CSV files found matching {PROCESS_GLOB}")

    logger.info(f"Consolidating {len(files)} process files: "
                f"{[os.path.basename(f) for f in files]}")

    frames = []
    for f in files:
        df = read_csv_flexible(f)
        df['source_file'] = os.path.basename(f)
        frames.append(df)

    consolidated = pd.concat(frames, ignore_index=True)
    logger.info(f"✓ Consolidated {len(consolidated)} total process rows "
                f"across {len(files)} files")
    return consolidated


def load_dataframe_to_raw(df, table_name, source_label, sample_size=None, batch_size=5000):
    """Convert a dataframe to JSON documents and bulk-load into raw.<table_name>.
    Uses fast_executemany + batched executemany so large volumes (millions of rows)
    load in minutes instead of hours. In DRY_RUN mode, skips Azure SQL entirely."""
    if sample_size:
        df = df.head(sample_size)

    df = df.astype(object).where(df.notnull(), None)
    total = len(df)
    logger.info(f"Preparing {total} rows from {source_label} for raw.{table_name}...")

    if DRY_RUN:
        if total:
            sample_row = df.iloc[0].to_dict()
            sample_row['loaded_at'] = datetime.now().isoformat()
            sample_row['source_file'] = sample_row.get('source_file', source_label)
            logger.info(f"[DRY_RUN] Sample row: {json.dumps(sample_row, default=str)[:300]}...")
        logger.info(f"[DRY_RUN] Skipping Azure SQL write for raw.{table_name}")
        return

    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()
    cursor.fast_executemany = True

    cursor.execute(f"IF OBJECT_ID('raw.{table_name}', 'U') IS NOT NULL DROP TABLE raw.{table_name}")
    cursor.execute(f"""
        CREATE TABLE raw.{table_name} (
            id INT IDENTITY(1,1) PRIMARY KEY,
            raw_data NVARCHAR(MAX),
            loaded_at DATETIME2 DEFAULT GETDATE()
        )
    """)
    conn.commit()

    insert_sql = f"INSERT INTO raw.{table_name} (raw_data) VALUES (?)"
    loaded_at_iso = datetime.now().isoformat()
    batch = []
    inserted = 0

    for _, row in df.iterrows():
        row_dict = row.to_dict()
        row_dict['loaded_at'] = loaded_at_iso
        row_dict['source_file'] = row_dict.get('source_file', source_label)
        batch.append((json.dumps(row_dict, default=str),))

        if len(batch) >= batch_size:
            cursor.executemany(insert_sql, batch)
            conn.commit()
            inserted += len(batch)
            logger.info(f"  Inserted {inserted}/{total} rows...")
            batch = []

    if batch:
        cursor.executemany(insert_sql, batch)
        conn.commit()
        inserted += len(batch)

    logger.info(f"✓ Loaded {inserted} JSON documents to raw.{table_name}")
    conn.close()


def load_laboratory_to_raw():
    lab_file = os.path.join(DATA_DIR, 'Laboratory.csv')
    if not os.path.exists(lab_file):
        logger.warning(f"⚠ File not found: {lab_file}, skipping")
        return
    df = read_csv_flexible(lab_file)
    load_dataframe_to_raw(df, 'laboratory', 'Laboratory.csv')


def load_process_to_raw():
    df = consolidate_process_files()
    load_dataframe_to_raw(df, 'process_timeseries', 'process_consolidated')


def main():
    """Load both datasets as JSON to raw schema. Assumes data has already
    been downloaded manually via the Kaggle CLI."""
    logger.info("Starting data load pipeline...")
    if DRY_RUN:
        logger.info("*** DRY_RUN=true: will parse only, no Azure SQL writes ***")

    check_data_exists()

    if not DRY_RUN:
        create_raw_schema()

    load_laboratory_to_raw()
    load_process_to_raw()

    logger.info("✓ Data load complete")


if __name__ == '__main__':
    main()
