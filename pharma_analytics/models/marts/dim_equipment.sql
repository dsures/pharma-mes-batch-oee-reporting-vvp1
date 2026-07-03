{{
    config(
        materialized='table',
        schema='marts'
    )
}}

SELECT
    equipment_code,
    ROW_NUMBER() OVER (ORDER BY equipment_code) AS equipment_key,
    CONCAT('Press-', equipment_code) AS equipment_name,
    MIN(event_ts) AS first_seen,
    MAX(event_ts) AS last_seen,
    COUNT(*) AS reading_count

FROM {{ ref('stg_process_timeseries') }}
WHERE equipment_code IS NOT NULL
GROUP BY equipment_code
