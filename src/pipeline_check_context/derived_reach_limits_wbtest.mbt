///|
test "derived Reach and Traverse limits retain exact subjects and Host ceilings" {
  for operation in ["reach", "traverse"] {
    let selected_policy = sequence_limit_policy(false)
    let traversal = if operation == "reach" {
      (
        #|{"reach":{"start":1,"direction":"out","max_depth":2},"as":"out"}
      )
    } else {
      (
        #|{"traverse":{"start":{"ids":[1]},"direction":"out","min_hops":0,"max_hops":2,"emit":"paths"},"as":"out"}
      )
    }
    let text = (
        #|{"version":"actql/0.1","id":"derived-reach","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"src":1,"dst":2}]},"as":"seed"},{"graph":{"source":"src","target":"dst"},"as":"g"},
      ) +
      traversal +
      (
        #|],"results":{"answer":{"from":"out","fields":["start_id"]}}}],"results":{"answer":{"from":{"stage":"s","result":"answer"}}}}
      )
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
    let prepared = @stage_results.prepare_local_source(
      program,
      None,
      max_parameters=0,
      {
        max_stages: 1,
        max_steps: 4,
        max_results: 2,
        max_work: 1000000,
        max_nodes: 100000,
        max_tokens: 10000,
        max_text_bytes: 1000000,
        max_depth: 100,
      },
    ).unwrap()
    let inputs = bind_capacity_inputs(program, [], 1000).unwrap()
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
      selected_policy,
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
      if consumer is @capacity.Traversal(step~, paths~, output~) {
        assert_eq(step, 2)
        let limits = @step_bounds.check_traversal_limits(
          pipeline,
          step,
          sources,
          applications,
          selected_policy,
          paths,
          output,
          max_work=10000,
        ).unwrap()
        for
          (scope, suffix) in [
            (@step_bounds.SearchPaths, ":paths"),
            (@step_bounds.OutputRows, ""),
          ] {
          assert_eq(
            @wire.limit_subject(
              @step_bounds.traversal_limit_claim(limits, scope),
            ),
            operation + ":checked-step:2" + suffix,
          )
          assert_eq(
            @step_bounds.traversal_limit_effective_maximum(limits, scope),
            7L,
          )
        }
        assert_true(
          @step_bounds.check_traversal_limits(
            pipeline,
            step,
            sources,
            applications,
            selected_policy,
            output,
            paths,
            max_work=10000,
          )
          is Err(SubjectMismatch(_)),
        )
        checked = true
      }
    }
    assert_true(checked)
    assert_true(
      prepare_local_stage_contexts_from_inputs(
        prepared,
        result.inputs,
        selected_policy,
        {
          max_work: 1000000,
          max_text_bytes: 1000000,
          max_name_bytes: 100000,
          max_input_work: 100000,
          max_operand_work: 100000,
        },
      )
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
        selected_policy,
      )
      is Err(_),
    )
  }
}
