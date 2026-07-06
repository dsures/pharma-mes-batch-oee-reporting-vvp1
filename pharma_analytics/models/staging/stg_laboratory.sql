{{
    config(
        materialized='table',
        schema='staging'
    )
}}

-- parsing the raw JSON data
WITH parsed AS (
    SELECT
        JSON_VALUE(raw_data, '$.batch')            AS batch,
        JSON_VALUE(raw_data, '$.code')              AS code,
        JSON_VALUE(raw_data, '$.strength')          AS strength,
        JSON_VALUE(raw_data, '$.size')              AS size,
        JSON_VALUE(raw_data, '$.start')             AS start,
        JSON_VALUE(raw_data, '$.api_batch')         AS api_batch,
        JSON_VALUE(raw_data, '$.lactose_batch')     AS lactose_batch,
        JSON_VALUE(raw_data, '$.smcc_batch')        AS smcc_batch,
        JSON_VALUE(raw_data, '$.starch_batch')      AS starch_batch,
        JSON_VALUE(raw_data, '$.tbl_yield')         AS tbl_yield,
        JSON_VALUE(raw_data, '$.batch_yield')       AS batch_yield,
        JSON_VALUE(raw_data, '$.dissolution_av')    AS dissolution_av,
        JSON_VALUE(raw_data, '$.dissolution_min')   AS dissolution_min,
        JSON_VALUE(raw_data, '$.impurities_total')  AS impurities_total,
        JSON_VALUE(raw_data, '$.resodual_solvent')  AS resodual_solvent,
        JSON_VALUE(raw_data, '$.source_file')       AS source_file
    FROM {{ source('raw', 'laboratory') }}
)

SELECT
    CAST(batch AS NVARCHAR(50)) AS batch_id,
    CAST(code AS NVARCHAR(50)) AS product_code,
    CAST(strength AS NVARCHAR(50)) AS strength,
    TRY_CAST(size AS INT) AS batch_size,
    CAST(start AS NVARCHAR(50)) AS batch_start_month,

    -- Materials
    CAST(api_batch AS NVARCHAR(50)) AS api_batch_id,
    CAST(lactose_batch AS NVARCHAR(50)) AS lactose_batch_id,
    CAST(smcc_batch AS NVARCHAR(50)) AS smcc_batch_id,
    CAST(starch_batch AS NVARCHAR(50)) AS starch_batch_id,

    -- Quality metrics
    TRY_CAST(tbl_yield AS FLOAT) AS tablet_yield,
    TRY_CAST(batch_yield AS FLOAT) AS batch_yield,
    TRY_CAST(dissolution_av AS FLOAT) AS dissolution_average,
    TRY_CAST(dissolution_min AS FLOAT) AS dissolution_minimum,
    TRY_CAST(impurities_total AS FLOAT) AS total_impurities,
    TRY_CAST(resodual_solvent AS FLOAT) AS residual_solvent,

    -- Pass/Fail flag to simulate real world
    CASE
        WHEN TRY_CAST(batch_yield AS FLOAT) >= 90
            AND TRY_CAST(impurities_total AS FLOAT) < 0.5
            THEN 'PASS'
        ELSE 'FAIL'
    END AS quality_status,

    source_file,
    GETDATE() AS loaded_at

FROM parsed
WHERE batch IS NOT NULL
