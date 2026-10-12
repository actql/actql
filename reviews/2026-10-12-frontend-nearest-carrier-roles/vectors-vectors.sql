WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding))
FROM qv |> NEAREST cv AS c METRIC dot K 2 AS hit
  |> ORDER BY hit.rank
  |> RESULT answer
