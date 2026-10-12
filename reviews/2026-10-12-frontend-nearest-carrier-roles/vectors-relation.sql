WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding))
FROM qv |> NEAREST candidates AS c CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 AS hit
  |> ORDER BY hit.rank
  |> RESULT answer
