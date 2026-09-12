///|
test "ordered limits match independent shared canonical vector" {
  let params = params_for(",{\"derive\":[{\"x\":\"a + b\"}]}")
  let limits : LogicalLimits = {
    max_input_rows: 2L,
    max_value_bytes: 64L,
    max_live_value_bytes: 128L,
    max_work: 100L,
  }
  let context = prepare_ordered_limits(params, limits, 2L, 64L).unwrap()
  // portability/corpus/ordered-derive.json, row-limits (not product output).
  assert_eq(
    context.cid,
    "sha256:efe844a0d2119cb62b7b44887ba4f8e623aff5cdb62000cfd12dddb7af41c0da",
  )
  let out = @encode.writer(1024, 16, 2)
  emit_ordered_limits_body(limits, None, out)
  assert_eq(
    @encode.finish(out),
    "{\"max_input_rows\":2,\"max_live_value_bytes\":128,\"max_value_bytes\":64,\"max_work\":100,\"version\":\"actql-derive-row-limits/0.1\"}",
  )
  let sealed = @encode.writer(1024, 16, 2)
  emit_ordered_limits_body(limits, Some(context.cid), sealed)
  assert_true(@encode.finish(sealed).contains("\"self_cid\":\"sha256:efe844"))
  assert_true(
    ordered_limits_for_kernel(context, ordered_params_kernel(params)) is Ok(_),
  )
  // Identical source and identical limits do not substitute another owner.
  let other = params_for(",{\"derive\":[{\"x\":\"a + b\"}]}")
  assert_true(
    ordered_limits_for_kernel(context, ordered_params_kernel(other))
    is Err(ForeignKernel),
  )
  assert_true(
    prepare_ordered_limits(params, limits, 1L, 64L) is Err(EnclosingLimit),
  )
  assert_true(
    prepare_ordered_limits(params, limits, 2L, 63L) is Err(EnclosingLimit),
  )
}

///|
test "ordered limit integers are exact and invalid values fail before hashing" {
  let params = params_for(",{\"derive\":[{\"x\":\"a\"}]}")
  for n in [0L, 9007199254740991L] {
    let limits : LogicalLimits = {
      max_input_rows: n,
      max_value_bytes: n,
      max_live_value_bytes: n,
      max_work: n,
    }
    let context = prepare_ordered_limits(params, limits, n, n).unwrap()
    let out = @encode.writer(1024, 16, 2)
    emit_ordered_limits_body(context.limits, None, out)
    assert_true(@encode.finish(out).contains("\"max_work\":" + n.to_string()))
  }
  let limits : LogicalLimits = {
    max_input_rows: 0L,
    max_value_bytes: 0L,
    max_live_value_bytes: 0L,
    max_work: 0L,
  }
  for n in [-1L, 9007199254740992L] {
    for
      invalid in [
        { ..limits, max_input_rows: n, },
        { ..limits, max_value_bytes: n, },
        { ..limits, max_live_value_bytes: n, },
        { ..limits, max_work: n, },
      ] {
      assert_true(
        prepare_ordered_limits(params, invalid, 0L, 0L) is Err(InvalidLimits),
      )
    }
    assert_true(
      prepare_ordered_limits(params, limits, n, 0L) is Err(InvalidLimits),
    )
    assert_true(
      prepare_ordered_limits(params, limits, 0L, n) is Err(InvalidLimits),
    )
  }
}
