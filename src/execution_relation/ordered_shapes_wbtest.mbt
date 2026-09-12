///|
test "ordered shapes bind complete checked input output to the originating params" {
  let params = params_for(",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"}]}")
  let shapes = prepare_ordered_shapes(params, registry_limits()).unwrap()
  assert_true(physical_equal(shapes.params, params))
  assert_eq(
    shapes.input_cid,
    "sha256:c030d98219de8ae68a7cf15c7b541d4657b82ad1274a67ad3f0c8a5feb056cb1",
  )
  let out = @encode.writer(10000, 1000, 100)
  emit_closed_row_shape(shapes.input, out)
  assert_eq(
    @encode.finish(out),
    "{\"additional_fields\":false,\"fields\":{\"a\":{\"nullable\":false,\"type\":\"number\"},\"b\":{\"nullable\":false,\"type\":\"number\"}},\"required_fields\":[\"a\",\"b\"],\"version\":\"actql-derive-row-shape/0.1\"}",
  )
  assert_true(shapes.input_cid != shapes.output_cid)
  let after = @encode.writer(10000, 1000, 100)
  emit_closed_row_shape(shapes.output, after)
  assert_true(
    @encode.finish(after).contains("\"required_fields\":[\"a\",\"b\",\"old\"]"),
  )
  assert_true(
    prepare_ordered_shapes(params, { ..registry_limits(), max_body_bytes: 1, })
    is Err(ShapeLimit),
  )
}

///|
test "ordered context uses the exact authored prefix and retains original input" {
  let shapes = prepare_ordered_shapes(
    params_for(
      ",{\"derive\":[{\"old\":\"a\"},{\"a\":{\"literal\":\"shadow\"}},{\"z\":\"a\"}]}",
    ),
    registry_limits(),
  ).unwrap()
  let before = @encode.writer(10000, 1000, 100)
  emit_ordered_context(shapes, 0, before)
  assert_eq(
    @encode.finish(before),
    "{\"input_contract_cid\":\"" +
    shapes.input_cid +
    "\",\"prior_slots\":[],\"version\":\"actql-derive-row-context/0.1\"}",
  )
  let prefix = @encode.writer(10000, 1000, 100)
  emit_ordered_context(shapes, 2, prefix)
  assert_eq(
    @encode.finish(prefix),
    "{\"input_contract_cid\":\"" +
    shapes.input_cid +
    "\",\"prior_slots\":[{\"contract\":{\"nullable\":false,\"type\":\"number\"},\"name\":\"old\"},{\"contract\":{\"max_utf8_bytes\":6,\"nullable\":false,\"type\":\"string\"},\"name\":\"a\"}],\"version\":\"actql-derive-row-context/0.1\"}",
  )
  for invalid in [-1, 4] {
    let out = @encode.writer(10000, 1000, 100)
    let rejected = try {
      emit_ordered_context(shapes, invalid, out)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
