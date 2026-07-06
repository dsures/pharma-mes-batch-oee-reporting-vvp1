{{
    config(
        materialized='table',
        schema='staging'
    )
}}

WITH parsed AS (
    SELECT
        j.raw_timestamp,
        j.campaign,
        j.batch,
        j.equipment_code,
        j.tbl_speed,
        j.fom,
        j.main_comp,
        j.tbl_fill,
        j.srel,
        j.pre_comp,
        j.produced,
        j.waste,
        j.cyl_main,
        j.cyl_pre,
        j.stiffness,
        j.ejection,
        j.source_file
    FROM {{ source('raw', 'process_timeseries') }} r
    -- extract all the fields from the raw JSON data in one go
    CROSS APPLY OPENJSON(r.raw_data) WITH (
        raw_timestamp   NVARCHAR(50)   '$.timestamp',
        campaign        NVARCHAR(50)   '$.campaign',
        batch           NVARCHAR(50)   '$.batch',
        equipment_code  NVARCHAR(50)   '$.code',
        tbl_speed       NVARCHAR(50)   '$.tbl_speed',
        fom             NVARCHAR(50)   '$.fom',
        main_comp       NVARCHAR(50)   '$.main_comp',
        tbl_fill        NVARCHAR(50)   '$.tbl_fill',
        srel            NVARCHAR(50)   '$.SREL',
        pre_comp        NVARCHAR(50)   '$.pre_comp',
        produced        NVARCHAR(50)   '$.produced',
        waste           NVARCHAR(50)   '$.waste',
        cyl_main        NVARCHAR(50)   '$.cyl_main',
        cyl_pre         NVARCHAR(50)   '$.cyl_pre',
        stiffness       NVARCHAR(50)   '$.stiffness',
        ejection        NVARCHAR(50)   '$.ejection',
        source_file     NVARCHAR(255)  '$.source_file'
    ) j
),

typed AS (
    SELECT
        *,
        -- data quality issue with timestamp format, case statemement to handle different formats
        --   'YYYY-MM-DD HH:MM:SS'  e.g. 2018-11-22 23:07:27  (most files)
        --   'DDMMYYYY HH:MM'       e.g. 22112018 00:18        (file 15.csv)
        CASE
            WHEN raw_timestamp LIKE '____-__-__ __:__:__'
                THEN TRY_CONVERT(DATETIME2, raw_timestamp, 120)
            WHEN raw_timestamp LIKE '________ __:__'
                 AND raw_timestamp NOT LIKE '%-%'
                THEN TRY_CONVERT(
                    DATETIME2,
                    SUBSTRING(raw_timestamp, 5, 4) + '-' +
                    SUBSTRING(raw_timestamp, 3, 2) + '-' +
                    SUBSTRING(raw_timestamp, 1, 2) + ' ' +
                    RIGHT(raw_timestamp, 5) + ':00',
                    120
                )
            ELSE NULL
        END AS event_ts
    FROM parsed
)

SELECT
    event_ts,
    TRY_CAST(TRY_CAST(campaign AS FLOAT) AS INT) AS campaign,
    CAST(batch AS NVARCHAR(50)) AS batch_id,
    TRY_CAST(TRY_CAST(equipment_code AS FLOAT) AS INT) AS equipment_code,
    TRY_CAST(tbl_speed AS FLOAT) AS tablet_press_speed,
    TRY_CAST(fom AS FLOAT) AS fom,
    TRY_CAST(main_comp AS FLOAT) AS main_compression_force,
    TRY_CAST(tbl_fill AS FLOAT) AS tablet_fill,
    TRY_CAST(srel AS FLOAT) AS srel,
    TRY_CAST(pre_comp AS FLOAT) AS pre_compression_force,
    TRY_CAST(TRY_CAST(produced AS FLOAT) AS INT) AS tablets_produced,
    TRY_CAST(TRY_CAST(waste AS FLOAT) AS INT) AS tablets_waste,
    TRY_CAST(cyl_main AS FLOAT) AS cyl_main,
    TRY_CAST(cyl_pre AS FLOAT) AS cyl_pre,
    TRY_CAST(stiffness AS FLOAT) AS stiffness,
    TRY_CAST(ejection AS FLOAT) AS ejection,
    source_file,
    CASE
        WHEN TRY_CAST(tbl_speed AS FLOAT) > 0 THEN 'running'
        ELSE 'idle_or_down'
    END AS equipment_state,
    GETDATE() AS loaded_at
FROM typed
WHERE event_ts IS NOT NULL
