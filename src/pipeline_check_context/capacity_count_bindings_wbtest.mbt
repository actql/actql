///|
fn count_binding_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 30,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn count_binding_declarations() -> @parameter.Declarations {
  @parameter.read_declarations(
    Some(
      count_binding_cursor(
        "{\"n\":{\"type\":\"number\",\"default\":7},\"dt\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"3ms\"}}",
      ),
    ),
    { max_parameters: 2, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn count_binding_pipeline(
  declarations : @parameter.Declarations,
) -> @pipeline.CheckedPipeline {
  @pipeline.check(
    count_binding_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"generated\"}]",
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 1,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 30,
    },
  ).unwrap()
}

///|
test "count binding session shares values and exact pipeline attachments with incremental accounting" {
  let declarations = count_binding_declarations()
  let result = @parameter.bind(declarations, None, {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
  guard result is @parameter.Ready(values) else {
    fail("complete bindings expected")
  }
  let first = count_binding_pipeline(declarations)
  let second = count_binding_pipeline(declarations)
  let session = capacity_count_bindings(values)
  // Initial lookup + retained attachment + two values. Names/token: 1+2+3.
  assert_true(
    capacity_count_binding(session, first, 3, 6)
    is Err(@step_bounds.BindingWorkLimit),
  )
  assert_true(session.parameters is None)
  assert_true(
    capacity_count_binding(session, first, 4, 5)
    is Err(@step_bounds.BindingTextLimit),
  )
  assert_true(session.parameters is None)
  let (a, work, text) = capacity_count_binding(session, first, 4, 6).unwrap()
  assert_eq((work, text), (4, 6))
  // Equal source positions/content only pick a bucket, not a checked owner.
  let (b, work, text) = capacity_count_binding(session, second, 3, 0).unwrap()
  assert_eq((work, text), (3, 0))
  assert_false(physical_equal(a.unwrap(), b.unwrap()))
  assert_true(
    physical_equal(
      @step_bounds.binding_parameters(a.unwrap()),
      @step_bounds.binding_parameters(b.unwrap()),
    ),
  )
  assert_true(
    capacity_count_binding(session, second, 2, 0)
    is Err(@step_bounds.BindingWorkLimit),
  )
  let (again, work, text) = capacity_count_binding(session, second, 3, 0).unwrap()
  assert_eq((work, text), (3, 0))
  assert_true(physical_equal(again.unwrap(), b.unwrap()))
  let (again, work, text) = capacity_count_binding(session, first, 2, 0).unwrap()
  assert_eq((work, text), (2, 0))
  assert_true(physical_equal(again.unwrap(), a.unwrap()))
  let foreign = count_binding_pipeline(count_binding_declarations())
  assert_true(
    capacity_count_binding(session, foreign, 100, 100)
    is Err(@step_bounds.BindingOwnerMismatch),
  )
  let separate = capacity_count_bindings(values)
  let (other, _, _) = capacity_count_binding(separate, first, 4, 6).unwrap()
  assert_false(physical_equal(other.unwrap(), a.unwrap()))
  assert_false(
    physical_equal(
      @step_bounds.binding_parameters(other.unwrap()),
      @step_bounds.binding_parameters(a.unwrap()),
    ),
  )
}
