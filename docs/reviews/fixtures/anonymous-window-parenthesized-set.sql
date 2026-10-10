DATA r = SELECT 1 AS x UNION ALL SELECT 2 AS x;
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM r
  |> AS original
  |> SET x = x + 10
  |> SELECT ROW_NUMBER() OVER (ORDER BY original.x),
            ROW_NUMBER() OVER (ORDER BY x DESC)
)
ORDER BY a, b;
