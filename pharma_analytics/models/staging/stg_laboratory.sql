{{
    config(
        materialized='table',
        schema='staging'
    )
}}

SELECT
    CAST(batch AS NVARCHAR(50)) AS batch_id,
    CAST(code AS NVARCHAR(50)) AS product_code,
    CAST(strength AS NVARCHAR(50)) AS strength,
    CAST(size AS INT) AS batch_size,
    CAST(start AS NVARCHAR(50)) AS batch_start_month,

    -- Material genealogy
    CAST(api_batch AS NVARCHAR(50)) AS api_batch_id,
    CAST(lactose_batch AS NVARCHAR(50)) AS lactose_batch_id,
    CAST(smcc_batch AS NVARCHAR(50)) AS smcc_batch_id,
    CAST(starch_batch AS NVARCHAR(50)) AS starch_batch_id,

    -- Quality metrics (CQAs)
    CAST(tbl_yield AS FLOAT) AS tablet_yield,
    CAST(batch_yield AS FLOAT) AS batch_yield,
    CAST(dissolution_av AS FLOAT) AS dissolution_average,
    CAST(dissolution_min AS FLOAT) AS dissolution_minimum,
    CAST(impurities_total AS FLOAT) AS total_impurities,
    CAST(resodual_solvent AS FLOAT) AS residual_solvent,

    -- Derived: Pass/Fail flag (simplified - you'll refine this with specs)
    CASE
        WHEN
            CAST(batch_yield AS FLOAT) >= 90
            AND CAST(impurities_total AS FLOAT) < 0.5
            THEN 'PASS'
        ELSE 'FAIL'
    END AS quality_status,

    GETDATE() AS loaded_at

FROM {{ source('raw', 'laboratory') }}

WHERE batch IS NOT NULL
