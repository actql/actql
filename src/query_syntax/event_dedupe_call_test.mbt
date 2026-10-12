///|
test "P2 dedupe roles preserve repeated fields and shorthand quotation" {
  let call = parse_sga_call(
    "dedupe_events(by: [bucket, BUCKET], order_by: [{`event.id`: 'desc'}, {field: SCORE, DIR: 'asc', NULLS: 'first'}])",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments[0].1, ListValue([
    FieldReference([{ value: "bucket", quoted: false, }]),
    FieldReference([{ value: "BUCKET", quoted: false, }]),
  ]))
  assert_eq(call.arguments[1].1, ListValue([
    FieldMapValue([([{ value: "event.id", quoted: true, }], TextValue("desc"))]),
    ObjectValue([
      ("field", FieldReference([{ value: "SCORE", quoted: false, }])),
      ("dir", TextValue("asc")),
      ("nulls", TextValue("first")),
    ]),
  ]))
  assert_eq(parse_sga_call("dedupe_events(by: [], order_by: [{field: 'asc'}])", query_limits()).unwrap().arguments[1].1,
    ListValue([FieldMapValue([([{ value: "field", quoted: false, }], TextValue("asc"))])]))
}

///|
test "P2 dedupe fields do not become literal Strings or bare direction enums" {
  for text in [
    "dedupe_events(by: ['bucket'], order_by: [{score: 'asc'}])",
    "dedupe_events(by: [], order_by: [{field: 'score', dir: 'asc', nulls: 'last'}])",
    "dedupe_events(by: [], order_by: [{score: asc}])",
    "dedupe_events(by: [], order_by: [{field: score, DIR: 'asc', dir: 'desc', nulls: 'last'}])",
  ] {
    assert_true(parse_sga_call(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "P2 copied dedupe shorthand retains receiver scope without sharing paths" {
  let query = parse_query("FROM rows |> dedupe_events(by: [], order_by: [{r.score: 'asc'}])", query_limits()).unwrap()
  guard operation_at(query, 0) is Some(GraphCall(call)) else { fail("Expected dedupe") }
  guard call.arguments[1].1 is ListValue([FieldMapValue([(path, _)])]) else { fail("Expected typed order field") }
  assert_eq(path, [{value: "r", quoted: false,}, {value: "score", quoted: false,}])
  path[0] = {value: "changed", quoted: false,}
  guard operation_at(query, 0) is Some(GraphCall(original)) else { fail("Expected dedupe") }
  assert_eq(original.arguments[1].1, ListValue([FieldMapValue([([
    {value: "r", quoted: false,}, {value: "score", quoted: false,}], TextValue("asc"))])]))
}
