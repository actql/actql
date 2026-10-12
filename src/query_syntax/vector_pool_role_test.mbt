///|
test "P2 vector pooling separates fields output names and exact method data" {
  let call = parse_sga_call(
    "pool_vectors(by: [LABEL], vector: embedding, method: 'sum', output_id: `SELECT`)",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments, [
    ("by", ListValue([FieldReference([{ value: "LABEL", quoted: false, }])])),
    ("vector", FieldReference([{ value: "embedding", quoted: false, }])),
    ("method", TextValue("sum")),
    ("output_id", OutputName({ value: "SELECT", quoted: true, })),
  ])
}

///|
test "P2 vector pooling does not reinterpret retired field Strings or reserved output names" {
  for text in [
    "pool_vectors(by: ['label'], method: 'sum')",
    "pool_vectors(by: [label], vector: 'embedding', method: 'sum')",
    "pool_vectors(by: [label], method: sum)",
    "pool_vectors(by: [label], method: 'sum', output_id: SELECT)",
    "pool_vectors(by: [label], method: 'sum', output_id: 'pooled')",
  ] {
    assert_true(parse_sga_call(text, query_limits()) is Err(_), msg=text)
  }
  assert_eq(
    parse_sga_call("pool_vectors(by: [label], method: 'SUM')", query_limits()).unwrap().arguments[1].1,
    TextValue("SUM"),
  )
}
