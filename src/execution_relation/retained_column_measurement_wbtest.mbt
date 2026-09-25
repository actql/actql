///|
test "retained column facts come only from the bound live generation and named column" {
  let owner = capture_fixture()
  let live = Ref(true)
  let (source, _) = retained_fixture(
    owner,
    live,
    capture_value_measurement=true,
  )
  // Read positions resolve to stored columns by name, never by position.
  let input = retained_scan_fixture(owner, source)
  let scan = prepare_retained_producer_scan(
    input,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  assert_true(retained_producer_scan_column_measurement(scan, 0) is None)
  // A proof for another generation of the same Program cannot bind this read.
  let (other, _) = retained_fixture(
    owner,
    Ref(true),
    capture_value_measurement=true,
  )
  let foreign = prepare_trusted_retained_scan_reuse(
    retained_scan_fixture(owner, other),
    (),
    (_, _) => true,
  ).unwrap()
  assert_false(reuse_retained_scan_identity(scan, foreign))
  assert_true(retained_producer_scan_column_measurement(scan, 0) is None)
  let proof = prepare_trusted_retained_scan_reuse(input, live, (live, _) => {
    live.val
  }).unwrap()
  assert_true(reuse_retained_scan_identity(scan, proof))
  let evidence = source.representation.unwrap().value_measurement.unwrap()
  for column in 0..<scan.wire_columns.length() {
    let stored = scan.wire_columns[column]
    let (bytes, nodes) = evidence.column_usage[stored]
    assert_eq(
      retained_producer_scan_column_measurement(scan, column),
      Some({
        rows: 2,
        bytes,
        nodes,
        null_rows: 0,
        value_bytes_bound: evidence.ceiling,
        depth: 0,
      }),
    )
  }
  // `n` (two one-byte numbers) and `s` (two UTF-8 strings) stay distinct.
  let facts = [0, 1].map(column => {
    retained_producer_scan_column_measurement(scan, column).unwrap().bytes
  })
  facts.sort()
  assert_eq(facts, [2, 10])
  assert_true(retained_producer_scan_column_measurement(scan, 2) is None)
  assert_true(retained_producer_scan_column_measurement(scan, -1) is None)
  live.val = false
  assert_true(retained_producer_scan_column_measurement(scan, 0) is None)
}

///|
test "retained column facts require recorded value evidence" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let scan = prepare_retained_producer_scan(
    input,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let proof = prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap()
  assert_true(reuse_retained_scan_identity(scan, proof))
  assert_true(source.representation.unwrap().value_measurement is None)
  assert_true(retained_producer_scan_column_measurement(scan, 0) is None)
}

///|
test "captured value evidence counts exact nulls per column" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":true},\"s\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[{\"n\":null,\"s\":\"a\"}]},\"as\":\"v\"},{\"select\":[\"s\",\"n\"]}]",
  )
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(1),
  ).unwrap()
  let stream = prepare_admitted_output_stream(
    owner,
    Step(1),
    3,
    stream_value_limits(),
    row_wire_limits(),
    64,
    capture_value_measurement=true,
  ).unwrap()
  let rows : Array[Map[String, String]] = [
    { "n": "null", "s": "\"a\"" },
    { "n": "2", "s": "null" },
    { "n": "null", "s": "\"b\"" },
  ]
  for row in rows {
    let supplied = Array::makei(@schema.field_count(schema), column => {
      let field = @schema.field_at(schema, column).unwrap()
      @admitted.admit(
        field.contract,
        input_cursor(row.get(@schema.reference_name(field.name)).unwrap()),
        { max_nodes: 10, max_text_bytes: 100, max_depth: 2, },
      ).unwrap()
    })
    append_admitted_output_stream(stream, supplied.length(), column => {
      supplied.get(column)
    }).unwrap()
    |> ignore
  }
  let (receipt, _) = finish_admitted_output_stream(stream).unwrap()
  let evidence = receipt.value_measurement.unwrap()
  let nulls : Map[String, Int] = Map([])
  for index, column in evidence.columns {
    let name = @schema.reference_name(
      @schema.field_at(receipt.schema, column).unwrap().name,
    )
    nulls[name] = evidence.column_nulls[index]
  }
  assert_eq(nulls.get("n"), Some(2))
  assert_eq(nulls.get("s"), Some(1))
}
