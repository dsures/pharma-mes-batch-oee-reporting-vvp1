{{
    config(
        materialized='table',
        schema='marts'
    )
}}

with month_mapping as (
    select 'jan' as month_abbr, 1 as month_num
    union all select 'feb', 2
    union all select 'mar', 3
    union all select 'apr', 4
    union all select 'may', 5
    union all select 'jun', 6
    union all select 'jul', 7
    union all select 'aug', 8
    union all select 'sep', 9
    union all select 'oct', 10
    union all select 'nov', 11
    union all select 'dec', 12
),

date_mapping as (
    select distinct
        stg.batch_start_month,
        datefromparts(
            2000 + cast(right(stg.batch_start_month, 2) as int),
            mm.month_num,
            1
        ) as date_key
    from {{ ref('stg_laboratory') }} stg
    left join month_mapping mm
        on lower(left(stg.batch_start_month, 3)) = mm.month_abbr
    where stg.batch_start_month is not null
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
