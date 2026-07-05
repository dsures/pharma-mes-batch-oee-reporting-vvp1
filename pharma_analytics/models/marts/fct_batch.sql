{{
    config(
        materialized='table',
        schema='marts'
    )
}}

WITH bounds AS (
    SELECT
        MIN(dissolution_average) AS min_dissolution, MAX(dissolution_average) AS max_dissolution,
        MIN(batch_yield) AS min_yield, MAX(batch_yield) AS max_yield,
        MIN(total_impurities) AS min_impurities, MAX(total_impurities) AS max_impurities,
        MIN(residual_solvent) AS min_solvent, MAX(residual_solvent) AS max_solvent
    FROM {{ ref('stg_laboratory') }}
),

scored AS (
    SELECT
        stg.*,
        100.0 * (stg.dissolution_average - b.min_dissolution) / NULLIF(b.max_dissolution - b.min_dissolution, 0) AS dissolution_score,
        100.0 * (stg.batch_yield - b.min_yield) / NULLIF(b.max_yield - b.min_yield, 0) AS yield_score,
        100.0 * (b.max_impurities - stg.total_impurities) / NULLIF(b.max_impurities - b.min_impurities, 0) AS impurities_score,
        100.0 * (b.max_solvent - stg.residual_solvent) / NULLIF(b.max_solvent - b.min_solvent, 0) AS solvent_score
    FROM {{ ref('stg_laboratory') }} stg
    CROSS JOIN bounds b
)

SELECT
    ROW_NUMBER() OVER (ORDER BY s.batch_id) AS batch_key,
    s.batch_id,
    dp.product_key,
    dd.date_id,
    s.batch_size,
    s.tablet_yield,
    s.batch_yield,
    s.dissolution_average,
    s.dissolution_minimum,
    s.total_impurities,
    s.residual_solvent,
    s.quality_status,
    ROUND(
        0.35 * ISNULL(s.dissolution_score, 0)
        + 0.35 * ISNULL(s.impurities_score, 0)
        + 0.15 * ISNULL(s.solvent_score, 0)
        + 0.15 * ISNULL(s.yield_score, 0),
    2) AS quality_score,
    s.api_batch_id,
    s.lactose_batch_id,
    s.smcc_batch_id,
    s.starch_batch_id,
    s.loaded_at
FROM scored s
LEFT JOIN {{ ref('dim_product') }} dp
    ON s.product_code = dp.product_code
   AND s.strength = dp.strength
LEFT JOIN {{ ref('dim_date') }} dd
    ON s.batch_start_month = dd.batch_start_month
