///|
fn stage_bound_context(
  result : @results.CheckedResults,
  pipeline : @pipeline.CheckedPipeline,
  values : @parameter.BoundValues,
) -> BoundParameters {
  let context = check(result, [Some(values)], [capacity(pipeline)], policy(), {
    max_steps: 10,
    max_results: 10,
    max_work: 10000,
    max_text_bytes: 10000,
  }).unwrap()
  check_parameter_bindings(context, max_work=20000, max_text_bytes=20000).unwrap()
}

///|
test "all stage contexts share source Results bindings policy and cumulative work" {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","params":{"n":{"type":"number","default":1}},"stages":[{"id":"first","inputs":{"a":{}},"steps":[{"derive":{"x":"$n"}}],"results":{"out":{"from":"a","fields":["id"]}}},{"id":"second","inputs":{"a":{}},"steps":[{"derive":{"x":"$n"}}],"results":{"out":{"from":"a","fields":["id"]}}}],"results":{"out":{"from":{"stage":"second","result":"out"}}}}
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let declarations = @stages.declarations(source)
  guard @parameter.bind(declarations, None, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is Ready(values) else {
    fail("missing default")
  }
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  let pipelines : Array[@pipeline.CheckedPipeline] = []
  for i in 0..<2 {
    let body = @decode.open_object(
      @syntax.stage_body(@stages.stage_at(source, i).unwrap()),
    ).unwrap()
    pipelines.push(
      @pipeline.check(
        @decode.required(body, "steps").unwrap(),
        [("a", schema)],
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
      ).unwrap(),
    )
  }
  let operations = @stages.collect_operations(source, pipelines, {
    max_work: 10000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }).unwrap()
  let bound = @stages.bind_operations(operations, values, max_work=20000).unwrap()
  let results = @stage_results.check(operations, {
    max_results: 10,
    max_work: 20000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let contexts = [
    stage_bound_context(
      @stage_results.stage_at(results, 0).unwrap(),
      pipelines[0],
      values,
    ),
    stage_bound_context(
      @stage_results.stage_at(results, 1).unwrap(),
      pipelines[1],
      values,
    ),
  ]
  let attached = attach_stage_contexts(
    bound,
    results,
    contexts,
    policy(),
    max_work=100000,
    max_text_bytes=100000,
  ).unwrap()
  assert_true(physical_equal(stage_operations(attached), bound))
  let reference_values = reference_values_for(operations, values)
  let joined = attach_program_references(
    attached,
    reference_values,
    max_work=10000000,
  ).unwrap()
  assert_true(physical_equal(program_reference_stages(joined), attached))
  assert_true(
    physical_equal(program_reference_values(joined), reference_values),
  )
  let exact = program_reference_work(joined)
  assert_eq(
    exact,
    stage_usage(attached).0 + @program_refs.parameter_work(reference_values) + 2,
  )
  assert_true(
    attach_program_references(attached, reference_values, max_work=exact)
    is Ok(_),
  )
  assert_true(
    attach_program_references(attached, reference_values, max_work=exact - 1)
    is Err(WorkLimit),
  )
  assert_true(
    attach_program_references(attached, reference_values, max_work=-1)
    is Err(InvalidLimits),
  )
  let replaced = reference_operations(source, [
    pipelines[0],
    reference_pipeline(source, 1),
  ])
  assert_true(
    attach_program_references(
      attached,
      reference_values_for(replaced, values),
      max_work=10000000,
    )
    is Err(ForeignPipeline(1)),
  )
  let other_source = @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  guard @parameter.bind(@stages.declarations(other_source), None, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is Ready(other_values) else {
    fail("missing defaults")
  }
  let foreign_operations = reference_operations(other_source, [
    reference_pipeline(other_source, 0),
    reference_pipeline(other_source, 1),
  ])
  assert_true(
    attach_program_references(
      attached,
      reference_values_for(foreign_operations, other_values),
      max_work=10000000,
    )
    is Err(ForeignSource),
  )
  assert_true(physical_equal(stage_results(attached), results))
  assert_eq(@policy.cid(stage_policy(attached)), @policy.cid(policy()))
  let (work, text) = stage_usage(attached)
  let prior = @stages.bindings_usage(bound)
  let ru = @stage_results.usage(results)
  let (w0, t0) = parameter_usage(contexts[0])
  let (w1, t1) = parameter_usage(contexts[1])
  assert_eq(
    work,
    prior.work +
    ru.work -
    @stages.operations_usage(operations).work +
    w0 +
    w1 +
    4,
  )
  assert_eq(text, prior.direct_text_bytes + ru.text_bytes + t0 + t1)
  assert_true(
    attach_stage_contexts(
      bound,
      results,
      contexts,
      policy(),
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    attach_stage_contexts(
      bound,
      results,
      contexts,
      policy(),
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(BudgetExceeded(1)),
  )
  assert_true(
    attach_stage_contexts(
      bound,
      results,
      contexts,
      policy(),
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(BudgetExceeded(1)),
  )
  assert_true(
    attach_stage_contexts(
      bound,
      results,
      [contexts[0]],
      policy(),
      max_work=work,
      max_text_bytes=text,
    )
    is Err(StageCount),
  )
  assert_true(
    attach_stage_contexts(
      bound,
      results,
      [contexts[1], contexts[0]],
      policy(),
      max_work=work,
      max_text_bytes=text,
    )
    is Err(ForeignResults(0)),
  )
  guard @parameter.bind(declarations, Some(cursor("{\"n\":2}")), {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is Ready(other) else {
    fail("missing alternate binding")
  }
  let other_context = stage_bound_context(
    @stage_results.stage_at(results, 1).unwrap(),
    pipelines[1],
    other,
  )
  assert_true(
    attach_program_references(
      attached,
      reference_values_for(operations, other),
      max_work=10000000,
    )
    is Err(ForeignValues),
  )
  assert_true(
    attach_stage_contexts(
      bound,
      results,
      [contexts[0], other_context],
      policy(),
      max_work=100000,
      max_text_bytes=100000,
    )
    is Err(ForeignBindings(1, 0)),
  )
  let second = contexts[1]
  contexts.clear()
  assert_true(physical_equal(stage_context_at(attached, 1).unwrap(), second))
  assert_true(stage_context_at(attached, -1) is None)
  assert_true(stage_context_at(attached, 2) is None)
}
