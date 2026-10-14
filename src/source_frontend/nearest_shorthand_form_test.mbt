///|
// Keep SQL's existing entry-form contract. A bare Pipe source is text, whereas
// SELECT * preserves the exact query columns before the same NEAREST clause.
test "nearest explicit SQL fixture retains the public selector form" {
  let tail = " |> NEAREST candidates AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC cosine K 2 KEEP (queries.*) AS hit |> ORDER BY hit.rank"
  assert_true(parse_query("FROM queries" + tail, Sql) is Err(WrongQueryForm))
  assert_true(parse_query("SELECT * FROM queries" + tail, Sql) is Ok(_))
  assert_true(parse_query("FROM queries" + tail, Text) is Ok(_))
}
