{{
    config(
        materialized='table',
        schema='staging'
    )
}}

WITH per_batch AS (
    SELECT
        equipment_code,
        batch_id,
        MIN(event_ts) AS batch_start_ts,
        MAX(event_ts) AS batch_end_ts,
        MAX(tablets_produced) AS batch_produced,
        MAX(tablets_waste) AS batch_waste
    FROM {{ ref('stg_process_timeseries') }}
    WHERE equipment_code IS NOT NULL
      AND batch_id IS NOT NULL
      AND event_ts IS NOT NULL
    GROUP BY equipment_code, batch_id
)

SELECT
    equipment_code,
    batch_id,
    batch_start_ts,
    batch_end_ts,
    CAST(batch_end_ts AS DATE) AS batch_end_date,
    batch_produced,
    batch_waste,
    CASE
        WHEN (batch_produced + batch_waste) > 0
            THEN CAST(batch_produced AS FLOAT) / (batch_produced + batch_waste)
        ELSE NULL
    END AS batch_quality_pct
FROM per_batch
