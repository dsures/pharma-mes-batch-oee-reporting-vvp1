{{
    config(
        materialized='table',
        schema='marts'
    )
}}

WITH batch_readings AS (
    SELECT
        s.equipment_code,
        s.batch_id,
        s.event_ts,
        s.equipment_state,
        s.tablet_press_speed
    FROM {{ ref('stg_process_timeseries') }} s
    INNER JOIN {{ ref('int_batch_production') }} b
        ON s.equipment_code = b.equipment_code
       AND s.batch_id = b.batch_id
),

agg AS (
    SELECT
        equipment_code,
        batch_id,
        COUNT(*) AS total_readings,
        SUM(CASE WHEN equipment_state = 'running' THEN 1 ELSE 0 END) AS running_readings,
        AVG(tablet_press_speed) AS avg_speed,
        MAX(tablet_press_speed) AS max_speed_observed
    FROM batch_readings
    GROUP BY equipment_code, batch_id
)

SELECT
    b.equipment_code,
    b.batch_id,
    b.batch_start_ts,
    b.batch_end_ts,
    b.batch_end_date,
    a.total_readings,
    a.running_readings,
    CAST(a.running_readings AS FLOAT) / NULLIF(a.total_readings, 0) AS availability_pct,
    CASE
        WHEN a.max_speed_observed > 0 THEN a.avg_speed / a.max_speed_observed
        ELSE NULL
    END AS performance_pct,
    b.batch_produced,
    b.batch_waste,
    b.batch_quality_pct AS quality_pct,
    ISNULL(CAST(a.running_readings AS FLOAT) / NULLIF(a.total_readings, 0), 0)
        * ISNULL(CASE WHEN a.max_speed_observed > 0 THEN a.avg_speed / a.max_speed_observed ELSE NULL END, 0)
        * ISNULL(b.batch_quality_pct, 0) AS oee_pct,
    GETDATE() AS loaded_at
FROM {{ ref('int_batch_production') }} b
INNER JOIN agg a
    ON b.equipment_code = a.equipment_code
   AND b.batch_id = a.batch_id
