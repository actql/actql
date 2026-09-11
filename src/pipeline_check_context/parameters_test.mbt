///|
test "operation Parameters use the guard binding owner across repeated unused producers" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"p\":{\"type\":\"number\",\"default\":7}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  guard @parameter.bind(declarations, None, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is Ready(values) else {
    fail("default binding missing")
  }
  let producer = base(
    true,
    parameters=Some(declarations),
    steps=(
      #|[{"derive":{"x":"$p","y":"$p"}},{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":{"$param":"p"}}]},"as":"generated"}]
    ),
  )
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(producer, Input(0)).unwrap(),
  )
  let root = pipeline([("a", input), ("unused", input)])
  let result = results(root)
  let applications = [capacity(root), capacity(producer), capacity(producer)]
  let caps = { ..limits(), max_steps: 6, }
  let context = @pipeline_check_context.check(
    result,
    [None, Some(values), Some(values)],
    applications,
    policy(),
    caps,
  ).unwrap()
  let bound = @pipeline_check_context.check_parameter_bindings(
    context,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  assert_eq(@pipeline_check_context.parameter_visit_count(bound), 3)
  assert_true(
    physical_equal(@pipeline_check_context.parameter_context(bound), context),
  )
  assert_true(@pipeline_check_context.parameter_visit_at(bound, -1) is None)
  assert_true(@pipeline_check_context.parameter_visit_at(bound, 3) is None)
  assert_true(
    @pipeline_check_context.parameter_visit_at(bound, 0).unwrap().bound is None,
  )
  for visit in 1..<3 {
    let entry = @pipeline_check_context.parameter_visit_at(bound, visit).unwrap()
    assert_true(
      physical_equal(@parameter_slots.pipeline(entry.collected), producer),
    )
    let selected = entry.bound.unwrap()
    assert_true(physical_equal(@references.bound_values(selected), values))
    assert_true(
      physical_equal(
        @references.bound_index(selected),
        @parameter_slots.index(entry.collected),
      ),
    )
    assert_eq(@references.reference_count(@references.bound_index(selected)), 3)
    assert_eq(@references.used_value_count(selected), 1)
    assert_eq(
      @references.reference_at(@references.bound_index(selected), 0).unwrap().path,
      "/0/derive/x",
    )
  }
  let (work, text) = @pipeline_check_context.parameter_usage(bound)
  let (base_work, base_text) = @pipeline_check_context.usage(context)
  let mut expected_work = base_work + 3
  let mut expected_text = base_text
  for visit in 0..<3 {
    let entry = @pipeline_check_context.parameter_visit_at(bound, visit).unwrap()
    expected_work += @parameter_slots.work(entry.collected)
    expected_text += @parameter_slots.direct_text_bytes(entry.collected)
    if entry.bound is Some(selected) {
      expected_work += @references.binding_work(selected)
    }
  }
  assert_eq((work, text), (expected_work, expected_text))
  assert_true(text > base_text)
  assert_true(
    @pipeline_check_context.check_parameter_bindings(
      context,
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_check_context.check_parameter_bindings(
      context,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_check_context.check_parameter_bindings(
      context,
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_check_context.check_parameter_bindings(
      context,
      max_work=base_work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_check_context.check_parameter_bindings(
      context,
      max_work=-1,
      max_text_bytes=text,
    )
    is Err(InvalidLimits),
  )
  // Guard-free does not mean Parameter-free. The inventory must not skip this
  // unused producer just because no numeric guard needed a supplied value.
  let missing = @pipeline_check_context.check(
    result,
    [None, None, None],
    applications,
    policy(),
    caps,
  ).unwrap()
  assert_true(
    @pipeline_check_context.check_parameter_bindings(
      missing,
      max_work=10000,
      max_text_bytes=10000,
    )
    is Err(MissingBindings(1)),
  )
  let late = @pipeline_check_context.check(
    result,
    [None, Some(values), None],
    applications,
    policy(),
    caps,
  ).unwrap()
  assert_true(
    @pipeline_check_context.check_parameter_bindings(
      late,
      max_work=10000,
      max_text_bytes=10000,
    )
    is Err(MissingBindings(2)),
  )
}
