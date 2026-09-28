FROM orders
|> WHERE status = 'open'
|> SELECT id, customer_id, amount
|> ORDER BY amount DESC, id ASC;
