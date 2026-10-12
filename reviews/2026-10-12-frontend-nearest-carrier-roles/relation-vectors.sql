WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding))
FROM queries |> NEAREST cv AS c QUERY KEY (request_id) VECTOR embedding METRIC dot K 2 AS hit
  |> ORDER BY hit.rank
  |> RESULT answer
