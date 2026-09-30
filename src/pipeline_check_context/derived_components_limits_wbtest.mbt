///|
test "derived Components limits bind node proof and output ceiling" {
  let text =
    #|{"version":"actql/0.1","id":"derived-components","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"id":1,"dst":2},{"id":2,"dst":3},{"id":3,"dst":1}]},"as":"seed"},{"graph":{"nodes":{"from":"seed","id":"id","fields":[]},"edges":{"from":"seed","source":"id","target":"dst","fields":[]}},"as":"g"},{"from":"g","components":{"kind":"strong"},"as":"out"}],"results":{"answer":{"from":"out","fields":["node_id","component_id","component_size"]}}}],"results":{"answer":{"from":{"stage":"s","result":"answer"}}}}
  let program = @syntax.parse(
    text,
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 1,
    },
    format=Json,
  ).unwrap()
  let preparation = @stage_results.prepare_local_source(
    program,
    None,
    max_parameters=0,
    {
      max_stages: 1,
      max_steps: 3,
      max_results: 2,
      max_work: 1000000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
  )
  if preparation is Err(issue) {
    match issue {
      Program(Pipeline(_, _)) => fail("Components Pipeline")
      Program(Results(_, _)) => fail("Components Results")
      Program(Order(_, _)) => fail("Components Order")
      Program(Ports(_, _)) => fail("Components Ports")
      Program(_) => fail("Components Program")
      ResultCollection(_) => fail("Components ResultCollection")
      Operations(_) => fail("Components Operations")
      _ => fail("Components preparation")
    }
  }
  let prepared = preparation.unwrap()
  let inputs = bind_capacity_inputs(program, [], 1000).unwrap()
  let policy = sequence_limit_policy(false)
  let result = derive_program_capacity(
    prepared,
    inputs,
    1000000,
    { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    100000,
    100000,
    capacity_count_bindings(@stage_results.local_source_values(prepared)),
    1000000,
    None,
    policy,
  ).unwrap()
  let sources = result.inputs.materials[0].sources
  let claims = @host.source_claims(sources)
  let port = @stage_results.wiring_stage_at(
    @stage_results.local_source_wiring(prepared),
    0,
  ).unwrap()
  let pipeline = @pipeline.contextual_orders_pipeline(
    @pipeline.contextual_closure_at(
      @results.checked_producer_orders(
        @results.ports_orders(@stage_results.stage_port_publications(port)),
      ),
      0,
    ).unwrap(),
  )
  let applications = @step_bounds.prepare_derived_applications(
    pipeline,
    claims,
    { max_work: 100000, max_input_work: 100000, max_operand_work: 100000, },
  ).unwrap()
  let mut checked = false
  for consumer in result.inputs.materials[0].consumers {
    if consumer is @capacity.Components(step~, nodes~, output~) {
      assert_eq(step, 2)
      let limits = @step_bounds.check_components_limits(
        pipeline,
        step,
        sources,
        applications,
        policy,
        nodes,
        output,
        max_work=10000,
      ).unwrap()
      assert_eq(
        @wire.limit_subject(
          @step_bounds.components_limit_claim(limits, InputNodes),
        ),
        "components:checked-step:2:nodes",
      )
      assert_eq(
        @wire.limit_subject(
          @step_bounds.components_limit_claim(limits, OutputRows),
        ),
        "components:checked-step:2",
      )
      assert_eq(
        @step_bounds.components_limit_effective_maximum(limits, InputNodes),
        3L,
      )
      assert_eq(
        @step_bounds.components_limit_effective_maximum(limits, OutputRows),
        3L,
      )
      assert_true(
        @step_bounds.check_components_limits(
          pipeline,
          step,
          sources,
          applications,
          policy,
          output,
          nodes,
          max_work=10000,
        )
        is Err(SubjectMismatch(_)),
      )
      checked = true
    }
  }
  assert_true(checked)
  assert_true(
    prepare_local_stage_contexts_from_inputs(prepared, result.inputs, policy, {
      max_work: 1000000,
      max_text_bytes: 1000000,
      max_name_bytes: 100000,
      max_input_work: 100000,
      max_operand_work: 100000,
    })
    is Ok(_),
  )
  assert_true(
    derive_program_capacity(
      prepared,
      inputs,
      result.work - 1,
      { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      100000,
      100000,
      capacity_count_bindings(@stage_results.local_source_values(prepared)),
      1000000,
      None,
      policy,
    )
    is Err(_),
  )
}
