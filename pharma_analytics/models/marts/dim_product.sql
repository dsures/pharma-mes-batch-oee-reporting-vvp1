{{
    config(
        materialized='table',
        schema='marts',
        unique_id='product_key'
    )
}}
-- useful if we would like to filter by product_code and strength in the future, not used in dashboard for now
SELECT
    product_code,
    strength,
    ROW_NUMBER() OVER (ORDER BY product_code, strength) AS product_key,
    CONCAT(product_code, ' - ', strength) AS product_name,
    COUNT(*) AS batch_count_in_source

FROM {{ ref('stg_laboratory') }}

GROUP BY product_code, strength
