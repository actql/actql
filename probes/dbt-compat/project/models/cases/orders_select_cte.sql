with large_orders as (
  select id, amount from {{ ref('stg_orders') }} where amount > 10
)
select id, amount from large_orders
