SELECT id, customer_id, amount
FROM orders
WHERE status = 'open'
ORDER BY amount DESC, id ASC;
