"""
Load pharma manufacturing data from figshare to Azure SQL.
Pulls Laboratory.csv, cleans it, and loads into raw schema.
"""

import os
import pandas as pd
import pyodbc
from dotenv import load_dotenv
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables from .env file
load_dotenv()

# Azure SQL connection details from .env
AZURE_SQL_SERVER = os.getenv('AZURE_SQL_SERVER')
AZURE_SQL_DB = os.getenv('AZURE_SQL_DB')
AZURE_SQL_USER = os.getenv('AZURE_SQL_USER')
AZURE_SQL_PASSWORD = os.getenv('AZURE_SQL_PASSWORD')

# Figshare URLs (public, no auth required)
FIGSHARE_LABORATORY_URL = os.getenv('FIGSHARE_LABORATORY_URL')

# Connection string
CONNECTION_STRING = (
    f'Driver={{ODBC Driver 18 for SQL Server}};'
    f'Server=tcp:{AZURE_SQL_SERVER},1433;'
    f'Database={AZURE_SQL_DB};'
    f'Uid={AZURE_SQL_USER};'
    f'Pwd={AZURE_SQL_PASSWORD};'
    f'Encrypt=yes;'
    f'TrustServerCertificate=no;'
    f'Connection Timeout=30;'
)

def create_raw_schema():
    """Create raw schema if it doesn't exist."""
    try:
        conn = pyodbc.connect(CONNECTION_STRING)
        cursor = conn.cursor()

        # Check if schema exists
        cursor.execute("SELECT * FROM sys.schemas WHERE name = 'raw'")
        if cursor.fetchone() is None:
            # Schema doesn't exist, create it
            cursor.execute("CREATE SCHEMA [raw]")
            conn.commit()
            logger.info("Raw schema created")
        else:
            logger.info("Raw schema already exists")

        conn.close()
    except pyodbc.Error as e:
        logger.error(f"Error creating schema: {e}")
        raise

def load_laboratory_csv():
    """
    Load Laboratory.csv from figshare into Azure SQL raw.laboratory table.
    Handles:
    - Semicolon delimiter
    - Missing values
    - Data type inference
    """
    try:
        logger.info("Fetching Laboratory.csv from figshare...")

        # Read CSV with semicolon delimiter
        csv_file = r'C:\Users\Darvin\Documents\Freelancing business\VVP\Vimachem\pharma-mes-batch-oee-reporting-vvp1\data\Laboratory.csv'
        df = pd.read_csv(csv_file, sep=';', low_memory=False, encoding='utf-8')

        logger.info(f"Loaded {len(df)} rows, {len(df.columns)} columns")
        logger.info(f"Columns: {df.columns.tolist()}")

        # Basic data cleaning
        df.columns = df.columns.str.strip().str.lower().str.replace(' ', '_')  # Normalize column names

        # Handle missing values (log counts)
        missing_summary = df.isnull().sum()
        if missing_summary.sum() > 0:
            logger.info(f"Missing values found: {missing_summary[missing_summary > 0].to_dict()}")

        # Replace empty strings with None for proper NULL handling
        df = df.replace('', None)

        # Connect and load
        logger.info("Connecting to Azure SQL...")
        conn = pyodbc.connect(CONNECTION_STRING)
        cursor = conn.cursor()

        # Drop table if exists (for idempotency)
        cursor.execute("IF OBJECT_ID('raw.laboratory', 'U') IS NOT NULL DROP TABLE raw.laboratory")
        conn.commit()

        # Create table — all columns as NVARCHAR(MAX) to avoid type conversion issues
        logger.info("Creating raw.laboratory table...")
        col_defs = [f"[{col}] NVARCHAR(MAX)" for col in df.columns]

        create_table_sql = f"CREATE TABLE raw.laboratory ({', '.join(col_defs)})"
        cursor.execute(create_table_sql)
        conn.commit()
        logger.info("Table created")

        # Insert data
        logger.info("Inserting data...")
        for idx, row in df.iterrows():
            placeholders = ', '.join(['?' for _ in range(len(row))])
            insert_sql = f"INSERT INTO raw.laboratory VALUES ({placeholders})"
            # Convert NaN to None for proper NULL handling
            row_values = tuple(None if pd.isna(v) else v for v in row)
            cursor.execute(insert_sql, row_values)
            if (idx + 1) % 100 == 0:
                logger.info(f"Inserted {idx + 1} rows...")

        conn.commit()
        logger.info(f"Successfully loaded {len(df)} rows into raw.laboratory")

        conn.close()

    except Exception as e:
        logger.error(f"Error loading Laboratory.csv: {e}")
        raise

def main():
    """Main ETL flow."""
    logger.info("Starting data load pipeline...")

    # Step 1: Create schema
    create_raw_schema()

    # Step 2: Load Laboratory data
    load_laboratory_csv()

    logger.info("Data load complete!")

if __name__ == '__main__':
    main()
