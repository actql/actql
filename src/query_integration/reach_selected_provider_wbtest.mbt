///|
fn selected_reach_relation_owner(
  graph : @lower.BoundPrepared,
  selector : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"g\",\"reach\":{\"start\":{\"from\":\"seeds\"," +
      "\"id\":\"key\"},\"direction\":\"out\",\"max_depth\":2}," +
      "\"as\":\"reached\"},{\"from\":\"reached\",\"filter\":\"true\"}]",
    ),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(graph)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
      (
        "seeds",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(selector)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
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
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn selected_reach_relation_read(
  owner : @lower.BoundPrepared,
  selector : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
) -> @execution.ProducerRead {
  @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, selector, output).unwrap(),
    100,
    1000,
  ).unwrap()
}

///|
fn selected_reach_provider(
  generated : @execution.GeneratedSequence,
) -> @local_connector.ManagedProvider {
  @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
}

///|
fn selected_reach_complete(
  run : @local_connector.ManagedProviderExecution,
) -> @execution.CompletedOutput raise {
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(run, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(output, ..) => return output
      _ => fail("selected Reach did not complete with Relation rows")
    }
  }
  fail("selected Reach exceeded the test's finite progress allowance")
}

///|
fn selected_reach_reject_foreign(
  run : @local_connector.ManagedProviderExecution,
) -> Unit raise {
  let mut failed = false
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(run, 1).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.Failed(_, ..) => {
        failed = true
        break
      }
      _ => fail("selected Reach accepted an input from a different owner")
    }
  }
  assert_true(failed)
  assert_true(@local_connector.managed_provider_stopped(run))
  assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
}

///|
test "selected Reach accepts exactly one retained Relation selector" {
  let source = carrier_graph_components_source_owner()
  let graph = carrier_graph_material_owner(source)
  let material = carrier_graph_diagnostic_material(graph, source)
  for
    (rows, nullable, expected) in [
      (
        "[{\"key\":2},{\"key\":1},{\"key\":2}]",
        false,
        [
          (1.0, 1.0, 0.0),
          (1.0, 2.0, 1.0),
          (1.0, 3.0, 2.0),
          (2.0, 1.0, 1.0),
          (2.0, 2.0, 0.0),
          (2.0, 3.0, 1.0),
        ],
      ),
      ("[]", false, []),
      (
        "[{\"key\":1}]",
        true,
        [(1.0, 1.0, 0.0), (1.0, 2.0, 1.0), (1.0, 3.0, 2.0)],
      ),
    ] {
    let selector = carrier_graph_selector_source_owner(rows, nullable~)
    let output = carrier_events_source_output(selector)
    let owner = selected_reach_relation_owner(graph, selector)
    let generated = @execution.select_generated_sequence_step(
      task_test_generated(owner),
      0,
    ).unwrap()
    let provider = selected_reach_provider(generated)
    let read = selected_reach_relation_read(owner, selector, output)
    let run = @local_connector.start_managed_provider_with_inputs(
      provider,
      generated,
      [
        @local_connector.managed_provider_carrier_input(
          @carrier_runtime.material_prepare_view(material, owner, 0, graph).unwrap(),
        ),
        @local_connector.managed_provider_relation_input(read),
      ],
      6,
      1000,
    ).unwrap()
    let actual = selected_reach_complete(run)
    assert_eq(@execution.completed_row_count(actual), expected.length())
    for index, (start, node, depth) in expected {
      assert_true(
        @execution.completed_cell(actual, index, 0) is Some(Number(v)) &&
        v == depth,
      )
      assert_true(
        @execution.completed_cell(actual, index, 1) is Some(Number(v)) &&
        v == node,
      )
      assert_true(
        @execution.completed_cell(actual, index, 2) is Some(Number(v)) &&
        v == node,
      )
      assert_true(
        @execution.completed_cell(actual, index, 3) is Some(Number(v)) &&
        v == start,
      )
    }
    assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
    assert_true(@execution.producer_read_available(read))
    assert_true(@carrier_runtime.material_available(material))
  }
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "selected Reach rejects wrong cardinality and retains exact input binding" {
  let source = carrier_graph_components_source_owner()
  let graph = carrier_graph_material_owner(source)
  let material = carrier_graph_diagnostic_material(graph, source)
  let selector = carrier_graph_selector_source_owner("[{\"key\":1}]")
  let output = carrier_events_source_output(selector)
  let owner = selected_reach_relation_owner(graph, selector)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let provider = selected_reach_provider(generated)
  let read = selected_reach_relation_read(owner, selector, output)
  let graph_input = @local_connector.managed_provider_carrier_input(
    @carrier_runtime.material_prepare_view(material, owner, 0, graph).unwrap(),
  )
  let relation_input = @local_connector.managed_provider_relation_input(read)
  for
    inputs in [
      [],
      [graph_input],
      [relation_input],
      [graph_input, graph_input, relation_input],
      [graph_input, relation_input, relation_input],
    ] {
    assert_true(
      @local_connector.start_managed_provider_with_inputs(
        provider, generated, inputs, 6, 1000,
      )
      is Err(@connector.Execution(@execution.InputSet)),
    )
  }
  assert_true(
    @carrier_runtime.material_prepare_view(material, owner, 1, graph) is Err(_),
  )
  assert_true(
    @execution.bind_completed_input(owner, 0, selector, output) is Err(_),
  )

  let foreign = selected_reach_relation_owner(graph, selector)
  let foreign_graph = @local_connector.managed_provider_carrier_input(
    @carrier_runtime.material_prepare_view(material, foreign, 0, graph).unwrap(),
  )
  let foreign_relation = @local_connector.managed_provider_relation_input(
    selected_reach_relation_read(foreign, selector, output),
  )
  for
    inputs in [[foreign_graph, relation_input], [graph_input, foreign_relation]] {
    selected_reach_reject_foreign(
      @local_connector.start_managed_provider_with_inputs(
        provider, generated, inputs, 6, 1000,
      ).unwrap(),
    )
  }
  assert_true(@execution.producer_read_available(read))
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "selected Reach scalar IDs and predicates still require no Relation" {
  let source = carrier_graph_components_source_owner()
  let graph = carrier_graph_material_owner(source)
  let material = carrier_graph_diagnostic_material(graph, source)
  let selector = carrier_graph_selector_source_owner("[{\"key\":1}]")
  let selector_output = carrier_events_source_output(selector)
  let relation_owner = selected_reach_relation_owner(graph, selector)
  let extra_relation = @local_connector.managed_provider_relation_input(
    selected_reach_relation_read(relation_owner, selector, selector_output),
  )
  for
    (start, expected_rows) in [
      ("1", 3),
      ("{\"ids\":[2,1,2]}", 6),
      ("{\"where\":{\"literal\":false}}", 0),
    ] {
    let owner = carrier_selected_graph_diagnostic_owner(
      graph,
      "\"reach\":{\"start\":" +
      start +
      ",\"direction\":\"out\",\"max_depth\":2}",
    )
    let generated = @execution.select_generated_sequence_step(
      task_test_generated(owner),
      0,
    ).unwrap()
    let provider = selected_reach_provider(generated)
    let graph_input = @local_connector.managed_provider_carrier_input(
      @carrier_runtime.material_prepare_view(material, owner, 0, graph).unwrap(),
    )
    assert_true(
      @local_connector.start_managed_provider_with_inputs(
        provider,
        generated,
        [graph_input, extra_relation],
        6,
        1000,
      )
      is Err(@connector.Execution(@execution.InputSet)),
    )
    let run = @local_connector.start_managed_provider_with_inputs(
      provider,
      generated,
      [graph_input],
      6,
      1000,
    ).unwrap()
    assert_eq(
      @execution.completed_row_count(selected_reach_complete(run)),
      expected_rows,
    )
    assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
    assert_true(@carrier_runtime.material_available(material))
  }
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "selected Reach Relation cancellation preserves both retained inputs" {
  let source = carrier_graph_components_source_owner()
  let graph = carrier_graph_material_owner(source)
  let material = carrier_graph_diagnostic_material(graph, source)
  let selector = carrier_graph_selector_source_owner(
    "[{\"key\":1},{\"key\":2}]",
  )
  let output = carrier_events_source_output(selector)
  let owner = selected_reach_relation_owner(graph, selector)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let read = selected_reach_relation_read(owner, selector, output)
  let run = @local_connector.start_managed_provider_with_inputs(
    selected_reach_provider(generated),
    generated,
    [
      @local_connector.managed_provider_carrier_input(
        @carrier_runtime.material_prepare_view(material, owner, 0, graph).unwrap(),
      ),
      @local_connector.managed_provider_relation_input(read),
    ],
    6,
    1000,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(run, 1).unwrap()
    is @local_connector.Continue(work=1L, ..),
  )
  assert_true(@local_connector.cancel_managed_provider(run))
  assert_true(
    @local_connector.advance_managed_provider(run, 1).unwrap()
    is @local_connector.Stopped(..),
  )
  assert_true(@local_connector.cleanup_managed_provider(run).unwrap())
  assert_true(@execution.producer_read_available(read))
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}
