FROM {{ ref('eph_select') }}
|> SELECT id, amount
