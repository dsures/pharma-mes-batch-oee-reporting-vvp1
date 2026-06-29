{{
    config(
        materialized='table',
        schema='marts'
    )
}}

with date_mapping as (
    select distinct
        batch_start_month,
        try_convert(
            date,
            case
                when
                    batch_start_month like '%18'
                    then '2018-' + right(batch_start_month, 2)
                when
                    batch_start_month like '%19'
                    then '2019-' + right(batch_start_month, 2)
                when
                    batch_start_month like '%20'
                    then '2020-' + right(batch_start_month, 2)
                when
                    batch_start_month like '%21'
                    then '2021-' + right(batch_start_month, 2)
            end + '-01'
        ) as date_key
    from {{ ref('stg_laboratory') }}
    where batch_start_month is not null
)

select
    date_key,
    batch_start_month,
    row_number() over (order by date_key) as date_id,
    year(date_key) as yr,
    month(date_key) as mnth,
    datename(month, date_key) as month_name
from date_mapping
where date_key is not null
order by date_key
