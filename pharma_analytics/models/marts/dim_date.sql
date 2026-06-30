{{
    config(
        materialized='table',
        schema='marts'
    )
}}

with date_mapping as (
    select distinct
        batch_start_month,
        datefromparts(
            2000 + cast(right(batch_start_month, 2) as int),
            cast(left(batch_start_month, charindex('.', batch_start_month) - 1) as int),
            1
        ) as date_key
    from {{ ref('stg_laboratory') }}
    where batch_start_month is not null
)

select
    row_number() over (order by date_key) as date_id,
    date_key,
    batch_start_month,
    year(date_key) as year,
    month(date_key) as month,
    datename(month, date_key) as month_name
from date_mapping
where date_key is not null
