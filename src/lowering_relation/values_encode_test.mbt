///|
fn values_owner(raw : String) -> @lowering_relation.BoundPrepared {
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(
      @pipeline.check(
        cursor("[{\"values\":" + raw + ",\"as\":\"seed\"}]"),
        [],
        None,
        None,
        {
          max_steps: 100,
          max_work: 100000,
          max_text_bytes: 100000,
          max_nodes: 10000,
          max_tokens: 10000,
          max_depth: 100,
        },
      ).unwrap(),
      limits(),
    ).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn values_params_wire(owner : @lowering_relation.BoundPrepared) -> String raise {
  let prepared = @lowering_relation.prepare_values_node(
    owner,
    0,
    max_rows=100,
    max_cells=10000,
  ).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_values_params(prepared, writer)
  @encode.finish(writer)
}

///|
test "values execution params preserve empty schema row order and multiplicity" {
  // Fixed params from main's ordinary/empty/repeated/reversed vectors.
  for
    (rows, expected_rows) in [
      ("[{\"x\":1},{\"x\":2}]", "[{\"x\":1},{\"x\":2}]"),
      ("[]", "[]"),
      ("[{\"x\":1},{\"x\":1}]", "[{\"x\":1},{\"x\":1}]"),
      ("[{\"x\":2},{\"x\":1}]", "[{\"x\":2},{\"x\":1}]"),
    ] {
    let owner = values_owner(
      "{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
      rows +
      "}",
    )
    assert_eq(
      values_params_wire(owner),
      "{\"rows\":" +
      expected_rows +
      ",\"schema\":{\"x\":{\"nullable\":false,\"type\":\"number\"}}}",
    )
  }
}

///|
test "values wire resolves admitted parameter with exact owner before node emission" {
  let d = declarations()
  let owner = @lowering_relation.bind_parameters(
    prepared_with(d),
    Some(bound(d)),
    max_parameters=1,
    max_name_bytes=6,
  ).unwrap()
  let prepared = @lowering_relation.prepare_values_node(
    owner,
    0,
    max_rows=1,
    max_cells=1,
  ).unwrap()
  let expected = "{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":7}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}}"
  let writer = @encode.writer(expected.length(), 1000, 100)
  @lowering_relation.emit_values_node(prepared, writer)
  assert_eq(@encode.finish(writer), expected)
  let short = @encode.writer(expected.length() - 1, 1000, 100)
  let failed = try {
    @lowering_relation.emit_values_node(prepared, short)
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(failed)
  assert_true(
    @lowering_relation.prepare_values_node(owner, 0, max_rows=0, max_cells=1)
    is Err(@lowering_relation.ValuesLimit),
  )
  assert_true(
    @lowering_relation.prepare_values_node(owner, 0, max_rows=1, max_cells=0)
    is Err(@lowering_relation.ValuesLimit),
  )
}
