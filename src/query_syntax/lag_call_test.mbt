///|
test "P2 Lag named call retains field output and scalar roles" {
  let call = parse_sga_call(
    "lag(partition_by: [r.bucket, r.bucket], order_by: [{r.amount: 'desc'}, {field: id, DIR: 'asc', NULLS: 'last'}], field: r.amount, output: `SELECT`, offset: @p)",
    query_limits(),
  ).unwrap()
  assert_eq(call.operation, "lag")
  assert_true(call.arguments[0].1 is ListValue([FieldReference(_), FieldReference(_)]))
  assert_true(call.arguments[1].1 is ListValue([FieldMapValue(_), ObjectValue(_)]))
  assert_true(call.arguments[2].1 is FieldReference(_))
  assert_true(call.arguments[3].1 is OutputName({value:"SELECT",quoted:true}))
  assert_true(call.arguments[4].1 is ParameterValue("p"))
}

///|
test "P2 Lag rejects retired String references and bare reserved output names" {
  for text in [
    "lag(partition_by: ['id'], order_by: [{id: 'asc'}], field: amount, output: previous)",
    "lag(partition_by: [], order_by: [{field: 'id', dir: 'asc', nulls: 'first'}], field: amount, output: previous)",
    "lag(partition_by: [], order_by: [{id: 'asc'}], field: 'amount', output: previous)",
    "lag(partition_by: [], order_by: [{id: 'asc'}], field: amount, output: 'previous')",
    "lag(partition_by: [], order_by: [{id: 'asc'}], field: amount, output: SELECT)",
    "lag(partition_by: [], order_by: [{id: 'asc'}], field: amount, output: NULL)",
  ] {
    assert_true(parse_sga_call(text, query_limits()) is Err(_), msg=text)
  }
}
