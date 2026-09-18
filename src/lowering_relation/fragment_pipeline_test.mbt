///|
fn fragment_wire(
  fragment : @lowering_relation.FragmentPipeline,
  source : Bool,
) -> String raise {
  let writer = @encode.writer(100000, 10000, 100)
  if source {
    @lowering_relation.emit_fragment_source_pipeline(fragment, writer)
  } else {
    @lowering_relation.emit_fragment_machine_pipeline(fragment, writer)
  }
  @encode.finish(writer)
}

///|
test "source and machine fragment pipelines share identity and only rebase local input" {
  let d = declarations()
  let owner = @lowering_relation.bind_parameters(
    prepared_with(d, tail=",{\"derive\":{\"v\":{\"$param\":\"amount\"}}}"),
    Some(bound(d)),
    max_parameters=1,
    max_name_bytes=6,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let fragment = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  assert_eq(@lowering_relation.fragment_pipeline_input(fragment), "values_0")
  let roots = @lowering_relation.fragment_pipeline_roots(fragment)
  assert_true(physical_equal(@lowering_relation.root_sequence(roots), sequence))
  assert_eq(@lowering_relation.root_step_range(roots), (1, 2))
  assert_eq(
    fragment_wire(fragment, true),
    "{\"output\":\"derive_1\",\"sources\":{\"input\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"derive_1\",\"in\":[\"input\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{\"v\":{\"$param\":\"amount\"}}}}],\"version\":\"aoa-pipeline/0.1\"}",
  )
  assert_eq(
    fragment_wire(fragment, false),
    "{\"output\":\"derive_1\",\"sources\":{\"input\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"derive_1\",\"in\":[\"input\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{\"v\":{\"body\":7,\"op\":\"literal\"}}}}],\"version\":\"aoa-pipeline/0.1\"}",
  )
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("kernel")
  }
  assert_eq(@lowering_relation.kernel_input(kernel), "values_0")
}

///|
test "empty map remains a node and filter fragment preserves outer producer" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(
      ",{\"derive\":{}},{\"filter\":\"TRUE\"},{\"select\":[\"id\"]}",
    ),
    sequence_limits(),
  ).unwrap()
  let empty = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  let expected = "{\"output\":\"derive_1\",\"sources\":{\"input\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"derive_1\",\"in\":[\"input\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{}}}],\"version\":\"aoa-pipeline/0.1\"}"
  assert_eq(fragment_wire(empty, true), expected)
  assert_eq(fragment_wire(empty, false), expected)
  assert_eq(
    @lowering_relation.root_count(
      @lowering_relation.fragment_pipeline_roots(empty),
    ),
    0,
  )
  let filtered = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    2,
    root_limits(),
  ).unwrap()
  assert_eq(@lowering_relation.fragment_pipeline_input(filtered), "derive_1")
  assert_eq(
    fragment_wire(filtered, true),
    "{\"output\":\"where_2\",\"sources\":{\"input\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"where_2\",\"in\":[\"input\"],\"op\":\"REL.where\",\"params\":{\"expr\":{\"literal\":true}}}],\"version\":\"aoa-pipeline/0.1\"}",
  )
  assert_eq(
    fragment_wire(filtered, false),
    "{\"output\":\"where_2\",\"sources\":{\"input\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"where_2\",\"in\":[\"input\"],\"op\":\"REL.where\",\"params\":{\"expr\":{\"body\":true,\"op\":\"literal\"}}}],\"version\":\"aoa-pipeline/0.1\"}",
  )
  for step in [0, 3] {
    assert_true(
      @lowering_relation.prepare_fragment_pipeline(
        sequence,
        step,
        root_limits(),
      )
      is Err(@lowering_relation.NotExpressionKernel),
    )
  }
  assert_eq(@lowering_relation.sequence_count(sequence), 4)
}

///|
test "group fragment retains source roots and canonical order expansion" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(
      ",{\"group\":{\"by\":[\"id\"],\"aggregates\":{" +
      "\"items\":{\"fn\":\"array_agg\",\"expr\":\"id + 1\"," +
      "\"filter\":\"id > 0\",\"distinct\":true," +
      "\"max_items\":3,\"order_by\":[{\"field\":\"id\"," +
      "\"dir\":\"desc\",\"nulls\":\"first\"}]}}}}",
    ),
    sequence_limits(),
  ).unwrap()
  let fragment = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  let source = fragment_wire(fragment, true)
  assert_eq(
    source,
    "{\"output\":\"group_1\",\"sources\":{\"input\":{" +
    "\"sort\":\"relation\"}},\"steps\":[{\"id\":\"group_1\"," +
    "\"in\":[\"input\"],\"op\":\"REL.groupBy\",\"params\":{" +
    "\"aggs\":{\"items\":{\"distinct\":true,\"expr\":{" +
    "\"add\":[{\"field\":\"id\"},{\"literal\":1}]},\"filter\":{" +
    "\"gt\":[{\"field\":\"id\"},{\"literal\":0}]},\"fn\":" +
    "\"array_agg\",\"max_items\":3,\"order_by\":[{\"dir\":" +
    "\"desc\",\"field\":\"id\",\"nulls\":\"first\"}]}},\"by\":" +
    "[\"id\"]}}],\"version\":\"aoa-pipeline/0.1\"}",
  )
  let machine = fragment_wire(fragment, false)
  assert_true(
    machine.contains(
      "{\"id\":\"aggregate_1\",\"in\":[\"input\"]," + "\"op\":\"REL.groupBy\"",
    ),
  )
  assert_true(
    machine.contains(
      "{\"id\":\"group_1\",\"in\":[\"aggregate_1\"]," +
      "\"op\":\"REL.orderByStable\"",
    ),
  )
  assert_eq(
    @lowering_relation.root_count(
      @lowering_relation.fragment_pipeline_roots(fragment),
    ),
    2,
  )
}

///|
test "fragment pipeline writer budgets are cumulative and overflow is not publishable" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{}}"),
    sequence_limits(),
  ).unwrap()
  let fragment = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  let expected = fragment_wire(fragment, true)
  let exact = @encode.writer(expected.length(), 100, 20)
  @lowering_relation.emit_fragment_source_pipeline(fragment, exact)
  assert_eq(@encode.finish(exact), expected)
  let short = @encode.writer(expected.length() - 1, 100, 20)
  let failed = try {
    @lowering_relation.emit_fragment_source_pipeline(fragment, short)
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(failed)
  let unpublished = try {
    let _ = @encode.finish(short)
    false
  } catch {
    _ => true
  }
  assert_true(unpublished)
  assert_eq(fragment_wire(fragment, false), expected)
}
