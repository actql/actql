{{ config(materialized='ephemeral') }}
FROM {{ ref('stg_orders') }}
|> WHERE amount > 10
