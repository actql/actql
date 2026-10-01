FROM {{ ref('eph_pipe') }}
|> SELECT id, amount
