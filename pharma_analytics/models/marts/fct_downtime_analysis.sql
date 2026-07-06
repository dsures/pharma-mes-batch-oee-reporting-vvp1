{{
    config(
        materialized='table',
        schema='marts'
    )
}}
-- breaking down each downtime event into a single row with start and end timestamps, duration, and number of readings
WITH ordered AS (
    SELECT
        equipment_code,
        event_ts,
        equipment_state,
        batch_id,
        LAG(equipment_state) OVER (
            PARTITION BY equipment_code ORDER BY event_ts
        ) AS prev_state
    FROM {{ ref('stg_process_timeseries') }}
    WHERE equipment_code IS NOT NULL
      AND event_ts IS NOT NULL
),

flagged AS (
    SELECT
        *,
        CASE
            WHEN prev_state IS NULL OR prev_state <> equipment_state THEN 1
            ELSE 0
        END AS is_new_island
    FROM ordered
),

islands AS (
    SELECT
        *,
        SUM(is_new_island) OVER (
            PARTITION BY equipment_code ORDER BY event_ts
        ) AS island_id
    FROM flagged
),

downtime_islands AS (
    SELECT
        equipment_code,
        island_id,
        MIN(event_ts) AS downtime_start,
        MAX(event_ts) AS downtime_end,
        COUNT(*) AS reading_count,
        COUNT(DISTINCT batch_id) AS batches_affected
    FROM islands
    -- this downtime classification can be changed
    WHERE equipment_state = 'idle_or_down'
    GROUP BY equipment_code, island_id
)

SELECT
    ROW_NUMBER() OVER (ORDER BY equipment_code, downtime_start) AS downtime_id,
    equipment_code,
    downtime_start,
    downtime_end,
    -- duration of downtime in minutes
    DATEDIFF(MINUTE, downtime_start, downtime_end) AS duration_minutes,
    reading_count,
    batches_affected,
    GETDATE() AS loaded_at
FROM downtime_islands
WHERE DATEDIFF(MINUTE, downtime_start, downtime_end) BETWEEN 10 AND 1440  -- 10 min to 24 hrs; anything longer is considered a baseline downtime event
