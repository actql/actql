///|
test "fragment request binds local schema typed parameters and preserved source" {
  let d = declarations()
  let owner = @lowering_relation.bind_parameters(
    prepared_with(d, tail=",{\"derive\":{\"v\":{\"$param\":\"amount\"}}}"),
    Some(bound(d)),
    max_parameters=1,
    max_name_bytes=6,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let pipeline = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  let request = @lowering_relation.prepare_fragment_request(
    pipeline, 100L, 1000L,
  ).unwrap()
  let out = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_fragment_request(request, out)
  assert_eq(
    @encode.finish(out),
    "{\"max_rows\":100,\"max_value_bytes\":1000,\"parameters\":{\"amount\":{\"contract\":{\"nullable\":false,\"type\":\"number\"},\"value\":7}},\"pipeline\":{\"output\":\"derive_1\",\"sources\":{\"input\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"derive_1\",\"in\":[\"input\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{\"v\":{\"$param\":\"amount\"}}}}],\"version\":\"aoa-pipeline/0.1\"},\"source_schemas\":{\"input\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}}",
  )
  for n in [0L, -1L, 9007199254740992L] {
    assert_true(
      @lowering_relation.prepare_fragment_request(pipeline, n, 1L)
      is Err(@lowering_relation.InvalidRequestCeiling),
    )
    assert_true(
      @lowering_relation.prepare_fragment_request(pipeline, 1L, n)
      is Err(@lowering_relation.InvalidRequestCeiling),
    )
  }
  assert_true(
    @lowering_relation.prepare_fragment_request(
      pipeline, 9007199254740991L, 9007199254740991L,
    )
    is Ok(_),
  )
}

///|
test "request preserves expression shaped literal data and shares output budget" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(
      ",{\"derive\":{\"x\":{\"literal\":{\"$param\":\"unknown\"}}}}",
    ),
    sequence_limits(),
  ).unwrap()
  let pipeline = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  let request = @lowering_relation.prepare_fragment_request(pipeline, 1L, 1000L).unwrap()
  let out = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_fragment_request(request, out)
  let text = @encode.finish(out)
  assert_true(text.contains("\"parameters\":{}"))
  assert_true(text.contains("\"literal\":{\"$param\":\"unknown\"}"))
  assert_false(text.contains("null_contexts"))
  let short = @encode.writer(text.length() - 1, 1000, 100)
  let rejected = try {
    @lowering_relation.emit_fragment_request(request, short)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
