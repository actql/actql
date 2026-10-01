FROM {{ ref('stg_orders') }}
|> INFER `model-task:risk.v1` ITEM KEY (id) INPUT (n = amount) KEEP (id) AS assessment
