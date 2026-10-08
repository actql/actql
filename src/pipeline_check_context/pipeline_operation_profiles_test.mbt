///|
fn unbound_profile_pipeline(
  parameter : Bool,
  expression? : String? = None,
  suffix? : String = "",
  value_cell? : Bool = false,
) -> @pipeline.CheckedPipeline raise {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"x\":{\"type\":\"number\"}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  assert_true(
    @parameter.bind(declarations, None, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 100,
    })
    is Ok(NeedsBindings(_)),
  )
  let steps =
    #|[{"values":{"schema":{"seed":{"type":"boolean","nullable":false}},"rows":[{"seed":true}]},"as":"seed"},{"derive":{"n":"VALUE"}},{"select":["n"]}]
  let steps = steps.replace(
    old="VALUE",
    new=expression.unwrap_or(if parameter { "$x" } else { "1" }),
  )
  let steps = if value_cell {
    steps
    .replace(old="\"type\":\"boolean\"", new="\"type\":\"number\"")
    .replace(old="\"seed\":true", new="\"seed\":{\"$param\":\"x\"}")
  } else {
    steps
  }
  let steps = steps.replace(
    old="{\"select\":[\"n\"]}]",
    new="{\"select\":[\"n\"]}" + suffix + "]",
  )
  @pipeline.check(cursor(steps), [], Some(declarations), None, {
    max_steps: 10,
    max_work: 100000,
    max_nodes: 10000,
    max_tokens: 1000,
    max_text_bytes: 100000,
    max_depth: 100,
  }).unwrap()
}

///|
test "unbound Values derive and select require every actual RelA profile" {
  let declared : PureOperationProfiles = {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  }
  let expressions : ExpressionProfiles = { text_time: false, veca: false, }
  for parameter in [false, true] {
    let pipeline = unbound_profile_pipeline(parameter)
    let checked = check_pipeline_operation_profiles(
      pipeline, declared, expressions, 100,
    ).unwrap()
    assert_true(
      physical_equal(pipeline_operation_profiles_pipeline(checked), pipeline),
    )
    assert_eq(pipeline_operation_profiles_count(checked), 3)
    assert_eq(pipeline_operation_profiles_work(checked), 7)
    assert_eq(
      pipeline_operation_profiles_work(
        check_pipeline_operation_profiles(pipeline, declared, expressions, 7).unwrap(),
      ),
      7,
    )
    assert_true(
      check_pipeline_operation_profiles(pipeline, declared, expressions, 6)
      is Err(BudgetExceeded),
    )
    assert_true(
      check_pipeline_operation_profiles(pipeline, declared, expressions, 0)
      is Err(BudgetExceeded),
    )
    assert_true(
      check_pipeline_operation_profiles(pipeline, declared, expressions, -1)
      is Err(InvalidLimits),
    )
    assert_true(
      check_pipeline_operation_profiles(
        pipeline,
        { ..declared, rela: false, },
        expressions,
        100,
      )
      is Err(UnsupportedProfile(0, @pipeline.RelA)),
    )
  }
}
