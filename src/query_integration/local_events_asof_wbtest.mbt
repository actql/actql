///|
fn events_asof_owner(
  events : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"events\",\"asof_join\":{\"with\":\"right\"," +
      "\"kind\":\"left\",\"by\":[],\"left_time\":\"occurred_at\"," +
      "\"right_time\":\"occurred_at\",\"direction\":\"backward\"," +
      "\"tolerance\":10,\"right_tie_break\":[\"event_id\"]," +
      "\"select\":{\"id\":\"left.event_id\",\"value\":\"right.payload\"}}}]",
    ),
    [
      (
        "events",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(events)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
      (
        "right",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(right)),
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
fn events_asof_material(
  source_owner : @lower.BoundPrepared,
) -> (@lower.BoundPrepared, @carrier_runtime.Material) raise {
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let events_generated = task_test_generated(events_owner)
  let limits = dispatch_test_limits()
  let storage = carrier_events_storage_limits()
  let external = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let events_provider = @local_tea_provider.provider(
    storage,
    4096L,
    @execution.generated_sequence_capacity(
      events_generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let construction = @local_connector.start_managed_provider(
    events_provider,
    events_generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut material = None
  for _ in 0..<1000 {
    if material is None {
      match
        @local_connector.advance_managed_provider(construction, 1).unwrap() {
        @local_connector.Continue(..) => ()
        @local_connector.CarrierComplete(value, ..) => material = Some(value)
        _ => fail("Events construction failed")
      }
    }
  }
  assert_true(@local_connector.cleanup_managed_provider(construction).unwrap())
  (events_owner, material.unwrap())
}

///|
test "registered as-of provider consumes exact Events and Relation ports" {
  let (events_owner, material) = events_asof_material(
    carrier_events_source_owner(),
  )
  let limits = dispatch_test_limits()
  let storage = carrier_events_storage_limits()
  let right_owner = carrier_events_source_owner_with(
    "number",
    "[{\"event_id\":10,\"occurred_at\":8,\"payload\":\"eight\"}," +
    "{\"event_id\":11,\"occurred_at\":10,\"payload\":\"ten\"}]",
  )
  let right_output = carrier_events_source_output(right_owner)
  let owner = events_asof_owner(events_owner, right_owner)
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  assert_true(@lower.node_supports_selected_managed_execution(node))
  assert_true(@lower.node_accepts_managed_carrier_view(node, 0))
  assert_false(@lower.node_accepts_managed_carrier_view(node, 1))
  let generated = @execution.constrain_generated_asof_search(
    task_test_generated(owner),
    0,
    4L,
  ).unwrap()
  let view = @carrier_runtime.material_prepare_view(
    material, owner, 0, events_owner,
  ).unwrap()
  let right = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, right_owner, right_output).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_tea_provider.asof_join_provider(
    storage,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider_with_inputs_and_execution(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(view),
      @local_connector.managed_provider_relation_input(right),
    ],
    10,
    1000,
    limits.local_execution,
  ).unwrap()
  // Port identity is not interchangeable with the original Stage input index.
  assert_true(
    @local_connector.start_managed_provider_with_inputs_and_execution(
      provider,
      generated,
      [
        @local_connector.managed_provider_relation_input(right),
        @local_connector.managed_provider_carrier_input(view),
      ],
      10,
      1000,
      limits.local_execution,
    )
    is Err(_),
  )
  let foreign_owner = events_asof_owner(events_owner, right_owner)
  let foreign_view = @carrier_runtime.material_prepare_view(
    material, foreign_owner, 0, events_owner,
  ).unwrap()
  assert_true(
    @local_connector.start_managed_provider_with_inputs_and_execution(
      provider,
      generated,
      [
        @local_connector.managed_provider_carrier_input(foreign_view),
        @local_connector.managed_provider_relation_input(right),
      ],
      10,
      1000,
      limits.local_execution,
    )
    is Err(_),
  )
  let other = @local_connector.start_managed_provider_with_inputs_and_execution(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(view),
      @local_connector.managed_provider_relation_input(right),
    ],
    10,
    1000,
    limits.local_execution,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(other, 1).unwrap()
    is @local_connector.Continue(work=1L, ..),
  )
  assert_true(@local_connector.cancel_managed_provider(other))
  assert_false(@local_connector.managed_provider_stopped(other))
  assert_false(@local_connector.cleanup_managed_provider(other).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  assert_true(
    @local_connector.advance_managed_provider(other, 1).unwrap()
    is @local_connector.Stopped(..),
  )
  assert_true(@local_connector.managed_provider_stopped(other))
  assert_true(@local_connector.cleanup_managed_provider(other).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  let mut output = None
  for _ in 0..<1000 {
    if output is None {
      match @local_connector.advance_managed_provider(execution, 1).unwrap() {
        @local_connector.Continue(work~, ..) => assert_true(work <= 1L)
        @local_connector.Complete(value, ..) => output = Some(value)
        _ => fail("Events as-of failed")
      }
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  // The as-of contract orders by left time, then identity: 9 precedes 11.
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(@execution.Number(2)),
  )
  assert_true(
    @execution.completed_cell(output, 0, 1) is Some(@execution.Text("eight")),
  )
  assert_true(
    @execution.completed_cell(output, 1, 0) is Some(@execution.Number(1)),
  )
  assert_true(
    @execution.completed_cell(output, 1, 1) is Some(@execution.Text("ten")),
  )
  assert_true(@local_connector.cleanup_managed_provider(execution).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  // Six metadata slots, four clocks, and two ordered indices remain live.
  // Two output cells and their checked copies raise the peak to sixteen.
  // This oracle follows live allocations, not a successful run's meter.
  // Field lookup charges 24 + 24 + 9 + 9 + 9 + 24 = 99 units;
  // four numeric clocks and two identity comparisons add six. Output time
  // sorting and untied empty-key candidates need no further control charge.
  for
    (entries, work, accepted) in [
      (16, 105, true),
      (15, 105, false),
      (16, 104, false),
    ] {
    let bounded = @execution.start_bounded_asof_join_events(
      @bounded.control(),
      generated,
      view,
      right,
      10,
      limits.local_execution.rows.output_values,
      work,
      limits.local_execution.max_frames,
      entries,
      1000,
    ).unwrap()
    let mut terminal = false
    for _ in 0..<1000 {
      if !terminal {
        match @execution.advance_bounded_asof_join(bounded, 1).unwrap() {
          @execution.BoundedAsOfJoinContinue(..) => ()
          @execution.BoundedAsOfJoinComplete(result, ..) => {
            assert_true(accepted)
            assert_eq(@execution.completed_row_count(result), 2)
            terminal = true
          }
          @execution.BoundedAsOfJoinFailed(
            @execution.Rows(@execution.RowLimit),
            ..
          ) => {
            assert_false(accepted)
            terminal = true
          }
          _ => fail("unexpected Events as-of boundary failure")
        }
      }
    }
    assert_true(terminal)
    assert_true(@execution.cleanup_bounded_asof_join(bounded).unwrap())
    assert_true(@carrier_runtime.material_available(material))
    assert_true(@execution.producer_read_available(right))
  }
  let limited_provider = @local_tea_provider.asof_join_provider(
    { ..storage, max_workspace_slots: 15, },
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let limited = @local_connector.start_managed_provider_with_inputs_and_execution(
    limited_provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(view),
      @local_connector.managed_provider_relation_input(right),
    ],
    10,
    1000,
    limits.local_execution,
  ).unwrap()
  let mut limited_failed = false
  for _ in 0..<1000 {
    if !limited_failed {
      match @local_connector.advance_managed_provider(limited, 1).unwrap() {
        @local_connector.Continue(..) => ()
        @local_connector.Failed(
          @connector.Execution(@execution.Rows(0, @execution.RowLimit)),
          ..
        ) => limited_failed = true
        _ => fail("provider lost the typed as-of workspace failure")
      }
    }
  }
  assert_true(limited_failed)
  assert_true(@local_connector.cleanup_managed_provider(limited).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "bounded Events as-of terminates with empty left input" {
  let (events_owner, material) = events_asof_material(
    carrier_events_source_owner_with("number", "[]"),
  )
  let right_owner = carrier_events_source_owner()
  let owner = events_asof_owner(events_owner, right_owner)
  let generated = @execution.constrain_generated_asof_search(
    task_test_generated(owner),
    0,
    0L,
  ).unwrap()
  let view = @carrier_runtime.material_prepare_view(
    material, owner, 0, events_owner,
  ).unwrap()
  let right = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(
      owner,
      1,
      right_owner,
      carrier_events_source_output(right_owner),
    ).unwrap(),
    100,
    1000,
  ).unwrap()
  let limits = dispatch_test_limits().local_execution
  let active = @execution.start_bounded_asof_join_events(
    @bounded.control(),
    generated,
    view,
    right,
    10,
    limits.rows.output_values,
    limits.max_work,
    limits.max_frames,
    1000,
    1000,
  ).unwrap()
  let mut complete = false
  for _ in 0..<100 {
    if !complete {
      match @execution.advance_bounded_asof_join(active, 1).unwrap() {
        @execution.BoundedAsOfJoinContinue(..) => ()
        @execution.BoundedAsOfJoinComplete(output, ..) => {
          assert_eq(@execution.completed_row_count(output), 0)
          complete = true
        }
        _ => fail("empty Events as-of did not complete")
      }
    }
  }
  assert_true(complete)
  assert_true(@execution.cleanup_bounded_asof_join(active).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@execution.producer_read_available(right))
  assert_true(@carrier_runtime.reclaim_material(material))
}
