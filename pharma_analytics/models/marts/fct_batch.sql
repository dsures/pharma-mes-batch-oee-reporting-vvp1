{{
    config(
        materialized='table',
        schema='marts'
    )
}}

select
    row_number() over (order by stg.batch_id) as batch_key,
    stg.batch_id,
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
    stg.api_batch_id,
    stg.lactose_batch_id,
    stg.smcc_batch_id,
    stg.starch_batch_id,
    stg.loaded_at
from {{ ref('stg_laboratory') }} stg
left join {{ ref('dim_product') }} dp
    on stg.product_code = dp.product_code
    and stg.strength = dp.strength
left join {{ ref('dim_date') }} dd
    on stg.batch_start_month = dd.batch_start_month
