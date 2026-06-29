{{
    config(
        materialized='table',
        schema='marts'
    )
}}

SELECT
    stg.stg.batch_id,
    dp.product_key,
    dd.date_id,
    stg.batch_size,

    stg.tablet_yield,
    stg.batch_yield,
    stg.dissolution_average,
    stg.dissolution_minimum,
    stg.total_impurities,
    stg.residual_solvent,
    stg.quality_status,
    stg.api_stg.batch_id,

    stg.lactose_stg.batch_id,
    stg.smcc_stg.batch_id,
    stg.starch_stg.batch_id,
    stg.loaded_at,

    ROW_NUMBER() OVER (ORDER BY stg.batch_id) AS batch_key

FROM {{ ref('stg_laboratory') }} AS stg
LEFT JOIN {{ ref('dim_product') }} AS dp
    ON
        stg.product_code = dp.product_code
        AND stg.strength = dp.strength
LEFT JOIN {{ ref('dim_date') }} AS dd
    ON stg.batch_start_month = dd.batch_start_month
