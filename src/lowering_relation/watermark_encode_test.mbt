///|
fn watermark_kernel(source : String) -> @lowering_relation.PreparedKernel {
  let owner = expression_pipeline(
    ",{\"watermark_rows\":{\"time\":\"id\",\"late_policy\":\"mark\"," +
    source +
    "}}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    abort("watermark kernel")
  }
  kernel
}

///|
test "watermark emits bound fixed and prefix thresholds" {
  for
    (source, expected, prefix) in [
      (
        "\"watermark_ms\":-0.5",
        "{\"id\":\"watermark_1\",\"in\":[\"values_0\"],\"op\":" +
        "\"REL.watermark\",\"params\":{\"late_policy\":\"mark\"," +
        "\"time\":\"id\",\"watermark_ms\":-0.5}}",
        false,
      ),
      (
        "\"max_skew\":3",
        "{\"id\":\"watermark_1\",\"in\":[\"values_0\"],\"op\":" +
        "\"REL.watermark\",\"params\":{\"late_policy\":\"mark\"," +
        "\"max_skew_ms\":3,\"time\":\"id\"}}",
        true,
      ),
    ] {
    let kernel = watermark_kernel(source)
    guard @lowering_relation.kernel_watermark(kernel)
      is Some((time, timestamp, policy, threshold)) else {
      fail("watermark view")
    }
    assert_eq(@schema.reference_name(time), "id")
    assert_false(timestamp)
    assert_true(policy is @relation.MarkLate)
    assert_eq(@lowering_relation.watermark_is_prefix(threshold), prefix)
    assert_eq(
      @lowering_relation.watermark_input_order(threshold) is Some(_),
      prefix,
    )
    let writer = @encode.writer(10000, 1000, 100)
    @lowering_relation.emit_kernel_node(kernel, writer)
    assert_eq(@encode.finish(writer), expected)
  }
}

///|
test "watermark binds number and duration parameters before publication" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"fixed\":{\"type\":\"number\"}," +
        "\"skew\":{\"type\":\"string\",\"format\":\"duration\"}}",
      ),
    ),
    { max_parameters: 2, max_nodes: 20, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  guard @parameter.bind(
      declarations,
      Some(cursor("{\"fixed\":12.5,\"skew\":\"3ms\"}")),
      { max_nodes: 20, max_depth: 10, max_text_bytes: 1000, },
    ).unwrap()
    is Ready(values) else {
    fail("complete bindings")
  }
  for
    (source, expected, prefix) in [
      ("\"watermark_ms\":{\"$param\":\"fixed\"}", 12.5, false),
      ("\"max_skew\":{\"$param\":\"skew\"}", 3.0, true),
    ] {
    let checked = @pipeline.check(
      cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\"," +
        "\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"}," +
        "{\"watermark_rows\":{\"time\":\"id\",\"late_policy\":" +
        "\"drop\"," +
        source +
        "}}]",
      ),
      [],
      Some(declarations),
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap()
    let owner = @lowering_relation.bind_parameters(
      @lowering_relation.prepare(checked, limits()).unwrap(),
      Some(values),
      max_parameters=2,
      max_name_bytes=32,
    ).unwrap()
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    guard @lowering_relation.sequence_step(sequence, 1)
      is Some(@lowering_relation.RowStep(kernel)) &&
      @lowering_relation.kernel_watermark(kernel) is Some((_, _, _, threshold)) else {
      fail("bound watermark")
    }
    assert_eq(@lowering_relation.watermark_is_prefix(threshold), prefix)
    assert_eq(@lowering_relation.watermark_threshold_value(threshold), expected)
  }
}

///|
test "prefix watermark requires checked input order" {
  let owner = top_k_owner(
    "\"watermark_rows\":{\"time\":\"id\",\"late_policy\":\"mark\"," +
    "\"max_skew\":1}",
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, sequence_limits())
    is Err(
      @lowering_relation.KernelFailure(
        0,
        @lowering_relation.PendingWatermarkOrder
      )
    ),
  )
}

///|
test "watermark lowering charges its field and threshold atomically" {
  let owner = expression_pipeline(
    ",{\"watermark_rows\":{\"time\":\"id\",\"late_policy\":\"mark\"," +
    "\"watermark_ms\":0}}",
  )
  let exact = {
    ..sequence_limits(),
    max_bindings: 2,
    max_name_bytes: 2,
    expressions: { ..expression_limits(), max_work: 2, },
  }
  assert_true(@lowering_relation.prepare_sequence(owner, exact) is Ok(_))
  for
    short in [
      { ..exact, max_bindings: 1, },
      { ..exact, max_name_bytes: 1, },
      { ..exact, expressions: { ..exact.expressions, max_work: 1, }, },
    ] {
    assert_true(
      @lowering_relation.prepare_sequence(owner, short)
      is Err(
        @lowering_relation.KernelFailure(
          1,
          @lowering_relation.KernelBudgetExceeded
        )
      ),
    )
  }
}
