///|
// The raw Input and computed export are both authored. No identity projection
// or replacement ResultPort is inserted to hide a physical capability limit.
let debug_mixed_input_exports_document : String =
  #|{"version":"actql/0.1","id":"debug.mixed_input_exports.fused","stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":0},{"n":2}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}},{"id":"producer","inputs":{"left":{"result":{"stage":"seed","result":"rows"}},"right":{"result":{"stage":"seed","result":"rows"}}},"steps":[{"from":"left","join":{"kind":"inner","with":"right","on":[{"left":"n","right":"n"}],"select":{"n":"left.n"},"max_output_rows":2},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["n"]}}},{"id":"mixed","inputs":{"source":{"result":{"stage":"producer","result":"rows"}}},"steps":[{"from":"source","filter":"n > 0","as":"filtered"},{"from":"filtered","select":["n"],"as":"selected"}],"results":{"raw":{"from":"source","fields":["n"]},"computed":{"from":"selected","fields":["n"]}}},{"id":"downstream","inputs":{"source":{"result":{"stage":"mixed","result":"raw"}}},"steps":[],"results":{"rows":{"from":"source","fields":["n"]}}}],"results":{"raw":{"from":{"stage":"mixed","result":"raw"}},"computed":{"from":{"stage":"mixed","result":"computed"}},"downstream":{"from":{"stage":"downstream","result":"rows"}}}}

///|
test "mixed Input and computed Results keep originals and refuse unavailable Debug Input boundary before remap" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = match
    prepare_effect_free_client_program(
      debug_mixed_input_exports_document,
      Json,
      environment,
      None,
      run_materials_limits().preparation,
    ) {
    Ok(value) => value
    Err(Graph(issue)) =>
      fail("Original normal Graph: " + @debug.to_string(issue))
    Err(Check(diagnostic)) =>
      fail(
        "Original normal Check: " +
        @debug.to_string(@checked.diagnostic_category(diagnostic)),
      )
    Err(Syntax(_)) => fail("Original normal Syntax")
    Err(NeedsInputs(_)) => fail("Original normal NeedsInputs")
    Err(EffectNotSupported(_)) => fail("Original normal EffectNotSupported")
    Err(ValuesProfileUnsupported) =>
      fail("Original normal ValuesProfileUnsupported")
    Err(MissingCheckedStage(stage)) =>
      fail("Original normal MissingCheckedStage " + stage.to_string())
    Err(MissingStageIdentity(stage)) =>
      fail("Original normal MissingStageIdentity " + stage.to_string())
    Err(Lowering(_)) => fail("Original normal Lowering")
    Err(Binding(_)) => fail("Original normal Binding")
  }
  let normal = prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(normal), 4)
  // The actual Normal classifier retains ONE fused mixed Stage. The two
  // checked JOIN input ports remain distinct even though their seed is shared.
  assert_eq(@strategy.graph_task_selected_step(normal, 2), None)
  assert_eq(@strategy.graph_task_prefix_end(normal, 2), None)
  assert_eq(@strategy.graph_stage_operation_task(normal, 2, 0), Some(2))
  assert_eq(@strategy.graph_stage_operation_task(normal, 2, 1), Some(2))
  assert_eq(@strategy.graph_result_count(normal), 3)
  let owners = debug_graph_stage_owners(prepared)
  for index in 0..<3 {
    let occurrence = @strategy.graph_result_occurrence(normal, index).unwrap()
    let name = @strategy.graph_result_name(normal, index).unwrap()
    let target = @results.port_target(
      @execution.managed_result_occurrence_port(occurrence),
    )
    if name == "raw" {
      assert_eq(target, @pipeline.Input(0))
      assert_true(
        physical_equal(
          @execution.managed_result_occurrence_owner(occurrence),
          owners[2],
        ),
      )
    } else if name == "computed" {
      assert_eq(target, @pipeline.Step(1))
      assert_true(
        physical_equal(
          @execution.managed_result_occurrence_owner(occurrence),
          owners[2],
        ),
      )
    } else {
      assert_eq(name, "downstream")
      assert_eq(target, @pipeline.Input(0))
      assert_true(
        physical_equal(
          @execution.managed_result_occurrence_owner(occurrence),
          owners[3],
        ),
      )
    }
  }
  assert_eq(@strategy.graph_data_count(normal), 4)
  for index, expected in [(0, 1, 0), (0, 1, 1), (1, 2, 0)] {
    let edge = @strategy.graph_data_at(normal, index).unwrap()
    assert_eq((edge.producer, edge.consumer, edge.input), expected)
    assert_eq(edge.target, @pipeline.Step(0))
  }
  let raw = @strategy.graph_data_at(normal, 3).unwrap()
  assert_eq((raw.producer, raw.consumer, raw.input), (2, 3, 0))
  assert_eq(raw.target, @pipeline.Input(0))
  assert_true(@strategy.graph_ordered_inputs_complete(normal))
  match
    @strategy.prepare_checked_debug_dag(
      @strategy.graph_program(normal),
      owners,
      8,
      100000,
      source_free_root=true,
    ) {
    Err(InputBoundaryUnavailable(2, 0)) => ()
    Err(issue) => fail("Original Debug preparation: " + @debug.to_string(issue))
    Ok(_) => fail("unavailable mixed Input boundary admitted")
  }
}
