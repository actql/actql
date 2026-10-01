select id, amount from {{ source('shop', 'raw_orders') }}
