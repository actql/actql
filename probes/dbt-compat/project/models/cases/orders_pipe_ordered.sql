FROM {{ ref('stg_orders') }}
|> WHERE id > 1
|> SELECT id, amount
|> ORDER BY id DESC
