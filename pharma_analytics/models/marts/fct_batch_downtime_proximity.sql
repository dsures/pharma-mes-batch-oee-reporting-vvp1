{{
    config(
        materialized='table',
        schema='marts'
    )
}}

WITH batch_equipment AS (
    SELECT DISTINCT
        equipment_code,
        batch_id,
        batch_start_ts
    FROM {{ ref('int_batch_production') }}
),

nearest_downtime AS (
    SELECT
        be.equipment_code,
        be.batch_id,
        be.batch_start_ts,
        (
            SELECT MAX(d.downtime_end)
            FROM {{ ref('fct_downtime_analysis') }} d
            WHERE d.equipment_code = be.equipment_code
              AND d.downtime_end <= be.batch_start_ts
        ) AS nearest_prior_downtime_end
    FROM batch_equipment be
),

bucketed AS (
    SELECT
        nd.*,
        DATEDIFF(MINUTE, nd.nearest_prior_downtime_end, nd.batch_start_ts) AS minutes_since_downtime,
        CASE
            WHEN nd.nearest_prior_downtime_end IS NULL THEN 'no_prior_downtime'
            WHEN DATEDIFF(MINUTE, nd.nearest_prior_downtime_end, nd.batch_start_ts) <= 120 THEN 'within_2hrs'
            WHEN DATEDIFF(MINUTE, nd.nearest_prior_downtime_end, nd.batch_start_ts) <= 1440 THEN '2_to_24hrs'
            ELSE '24hrs_plus_baseline'
        END AS downtime_proximity_bucket
    FROM nearest_downtime nd
)

SELECT
    b.batch_id,
    b.equipment_code,
    b.batch_start_ts,
    b.nearest_prior_downtime_end,
    b.minutes_since_downtime,
    b.downtime_proximity_bucket,
    fb.quality_score,
    GETDATE() AS loaded_at
FROM bucketed b
LEFT JOIN {{ ref('fct_batch') }} fb
    ON b.batch_id = fb.batch_id
