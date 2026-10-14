///|
// Keep SQL's existing entry-form contract. A bare Pipe source is text, whereas
// WITH preserves the original Source as a named producer before NEAREST.
test "nearest explicit SQL fixture retains the public selector form" {
  let tail = " |> NEAREST candidates AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC cosine K 2 KEEP (queries.*) AS hit |> ORDER BY hit.rank"
  assert_true(parse_query("FROM queries" + tail, Sql) is Err(WrongQueryForm))
  assert_true(
    parse_query(
      "WITH q AS (FROM queries) FROM q |> NEAREST candidates AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC cosine K 2 KEEP (q.*) AS hit |> ORDER BY hit.rank",
      Sql,
    )
    is Ok(_),
  )
  assert_true(parse_query("FROM queries" + tail, Text) is Ok(_))
}
