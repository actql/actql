///|
fn carrier_events_source_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"event_id\":{\"type\":\"number\",\"nullable\":false},\"occurred_at\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"event_id\":1,\"occurred_at\":11,\"payload\":\"first\"},{\"event_id\":2,\"occurred_at\":9,\"payload\":\"late\"}]},\"as\":\"source\"}]",
    ),
    [],
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
fn local_carrier_events_program(variant? : String = "watermark") -> String {
  let dedupe = variant == "dedupe"
  let window = variant == "window_fixed" || variant == "window_sliding"
  let session = variant.has_prefix("session")
  let session_global = variant == "session_global"
  let session_parameter = variant == "session_parameter"
  let fields = if dedupe {
    "[\"event_id\",\"occurred_at\",\"payload\"]"
  } else if window {
    "[\"event_id\",\"occurred_at\",\"payload\"," +
    "\"window_start_ms\",\"window_end_ms\"]"
  } else if session {
    "[\"event_id\",\"occurred_at\",\"payload\"," +
    "\"session_start_ms\",\"session_end_ms\",\"session_id\"]"
  } else {
    "[\"event_id\",\"occurred_at\",\"payload\"," +
    "\"watermark_ms\",\"late\",\"watermark_decision\"]"
  }
  let rows = if dedupe {
    "[{\"event_id\":1,\"occurred_at\":20,\"payload\":\"a\"}," +
    "{\"event_id\":2,\"occurred_at\":10,\"payload\":\"a\"}," +
    "{\"event_id\":3,\"occurred_at\":30,\"payload\":\"b\"}," +
    "{\"event_id\":4,\"occurred_at\":5,\"payload\":\"b\"}]"
  } else if session_global {
    "[{\"event_id\":2,\"occurred_at\":1,\"payload\":\"a\"}," +
    "{\"event_id\":1,\"occurred_at\":3,\"payload\":\"b\"}," +
    "{\"event_id\":3,\"occurred_at\":13,\"payload\":\"a\"}]"
  } else if session {
    "[{\"event_id\":2,\"occurred_at\":1,\"payload\":\"a\"}," +
    "{\"event_id\":1,\"occurred_at\":3,\"payload\":\"a\"}," +
    "{\"event_id\":3,\"occurred_at\":13,\"payload\":\"a\"}]"
  } else {
    "[{\"event_id\":1,\"occurred_at\":3,\"payload\":\"first\"}," +
    "{\"event_id\":2,\"occurred_at\":1,\"payload\":\"late\"}," +
    "{\"event_id\":3,\"occurred_at\":2,\"payload\":\"edge\"}]"
  }
  let transform = if dedupe {
    "{\"dedupe_events\":{\"by\":[\"payload\"],\"order_by\":[{" +
    "\"field\":\"occurred_at\",\"dir\":\"asc\"," +
    "\"nulls\":\"last\"}]}}"
  } else if variant == "window_fixed" {
    "{\"window_events\":{\"kind\":\"fixed\",\"size\":10}}"
  } else if variant == "window_sliding" {
    "{\"window_events\":{\"kind\":\"sliding\",\"size\":10," + "\"step\":5}}"
  } else if session {
    "{\"session\":{\"by\":" +
    (if session_global { "[]" } else { "[\"payload\"]" }) +
    ",\"gap\":" +
    (if session_parameter { "{\"$param\":\"minimum\"}" } else { "10" }) +
    "}}"
  } else {
    "{\"watermark_events\":{\"watermark_ms\":2," + "\"policy\":\"mark\"}}"
  }
  let second_fields = if dedupe {
    "[\"payload\",\"event_id\"]"
  } else if window {
    "[\"payload\",\"window_start_ms\",\"event_id\"]"
  } else if session {
    "[\"payload\",\"session_id\",\"event_id\"]"
  } else {
    "[\"watermark_decision\",\"late\",\"event_id\"]"
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{" +
  "\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{" +
  "\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{" +
  "\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{" +
  "\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}},{" +
  "\"id\":\"values\",\"inputs\":{},\"steps\":[{\"values\":{" +
  "\"schema\":{\"event_id\":{\"type\":\"number\",\"nullable\":false}," +
  "\"occurred_at\":{\"type\":\"number\",\"nullable\":false}," +
  "\"payload\":{\"type\":\"string\",\"nullable\":false}}," +
  "\"rows\":" +
  rows +
  "}," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"event_id\",\"occurred_at\",\"payload\"]}}},{" +
  "\"id\":\"events\",\"inputs\":{\"rows\":{\"result\":{" +
  "\"stage\":\"values\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\"," +
  "\"time\":\"occurred_at\"}}," +
  transform +
  ",{" +
  "\"events\":true,\"as\":\"out\"}],\"results\":{\"r\":{" +
  "\"from\":\"out\",\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"events\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  fields +
  "}}},{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{" +
  "\"stage\":\"events\",\"result\":\"r\"}}},\"steps\":[{" +
  "\"select\":" +
  second_fields +
  "," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  second_fields +
  "}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\"," +
  "\"result\":\"r\"}}}}"
}

///|
fn carrier_events_owner(
  source : @lower.BoundPrepared,
  variant? : String = "watermark",
) -> @lower.BoundPrepared {
  let session = variant.has_prefix("session")
  let session_global = variant == "session_global"
  let session_parameter = variant == "session_parameter"
  let transform = if variant == "dedupe" {
    "{\"dedupe_events\":{\"by\":[\"payload\"],\"order_by\":[{" +
    "\"field\":\"occurred_at\",\"dir\":\"asc\"," +
    "\"nulls\":\"last\"}]}}"
  } else if variant == "window_fixed" {
    "{\"window_events\":{\"kind\":\"fixed\",\"size\":10}}"
  } else if variant == "window_sliding" {
    "{\"window_events\":{\"kind\":\"sliding\",\"size\":10," + "\"step\":5}}"
  } else if session {
    "{\"session\":{\"by\":" +
    (if session_global { "[]" } else { "[\"payload\"]" }) +
    ",\"gap\":" +
    (if session_parameter { "{\"$param\":\"gap\"}" } else { "10" }) +
    "}}"
  } else {
    "{\"watermark_events\":{\"watermark_ms\":10," + "\"policy\":\"mark\"}}"
  }
  let declarations = if session_parameter {
    Some(
      @parameter.read_declarations(
        Some(input_cursor("{\"gap\":{\"type\":\"number\",\"nullable\":false}}")),
        {
          max_parameters: 1,
          max_nodes: 10,
          max_depth: 10,
          max_text_bytes: 100,
        },
      ).unwrap(),
    )
  } else {
    None
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\"," +
      "\"time\":\"occurred_at\"}}," +
      transform +
      ",{\"events\":true}]",
    ),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    declarations,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let bound = match declarations {
    Some(declarations) =>
      match
        @parameter.bind(declarations, Some(input_cursor("{\"gap\":2}")), {
          max_nodes: 10,
          max_depth: 10,
          max_text_bytes: 100,
        }).unwrap() {
        @parameter.Ready(value) => Some(value)
        @parameter.NeedsBindings(_) => abort("missing session gap binding")
      }
    None => None
  }
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    bound,
    max_parameters=if session_parameter { 1 } else { 0 },
    max_name_bytes=if session_parameter { 3 } else { 0 },
  ).unwrap()
}

///|
fn carrier_events_output_owner(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"rows\",\"to_events\":{" +
      "\"id\":\"event_id\",\"time\":\"occurred_at\"}}]",
    ),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(input_cursor("\"rows\"")),
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
fn carrier_events_storage_limits() -> @record_storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn delayed_cleanup_provider(
  provider : @local_connector.ManagedProvider,
  attempts : Ref[Int],
) -> @local_connector.ManagedProvider {
  @local_connector.managed_provider(
    sequence => @local_connector.managed_provider_accepts(provider, sequence),
    sequence => @local_connector.managed_provider_capacity(provider, sequence),
    fn(sequence, inputs, max_rows, max_value_bytes) {
      match
        @local_connector.start_managed_provider(
          provider, sequence, inputs, max_rows, max_value_bytes,
        ) {
        Err(issue) => Err(issue)
        Ok(active) =>
          Ok(
            @local_connector.managed_provider_execution(
              quantum => {
                @local_connector.advance_managed_provider(active, quantum)
              },
              fn() { @local_connector.cancel_managed_provider(active) },
              fn() { @local_connector.managed_provider_stopped(active) },
              fn() {
                attempts.val += 1
                if attempts.val == 1 {
                  Ok(false)
                } else {
                  @local_connector.cleanup_managed_provider(active)
                }
              },
            ),
          )
      }
    },
  )
}

///|
fn finish_rows_to_events(
  execution : @local_bridge.RowsToEventsExecution,
) -> @records.Completed {
  while true {
    match @local_bridge.advance_rows_to_events(execution, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      @local_bridge.Failed(_, ..) => abort("rows-to-events failed")
      @local_bridge.Stopped(_, ..) => abort("rows-to-events stopped")
    }
  }
  abort("unreachable")
}

///|
fn finish_event_watermark(
  execution : @local_tea.WatermarkExecution,
) -> @records.Completed {
  while true {
    match @local_tea.advance_watermark(execution, 1).unwrap() {
      @local_tea.Continue(..) => ()
      @local_tea.Complete(output, ..) => return output
      @local_tea.Failed(_, ..) => abort("event watermark failed")
      @local_tea.Stopped(_, ..) => abort("event watermark stopped")
    }
  }
  abort("unreachable")
}

///|
fn finish_events_to_rows(
  execution : @local_bridge.EventsToRowsExecution,
) -> @execution.CompletedOutput {
  while true {
    match @local_bridge.advance_events_to_rows(execution, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      @local_bridge.Failed(_, ..) => abort("events-to-rows failed")
      @local_bridge.Stopped(_, ..) => abort("events-to-rows stopped")
    }
  }
  abort("unreachable")
}

///|
fn carrier_events_source_output(
  owner : @lower.BoundPrepared,
) -> @execution.CompletedOutput raise {
  let result = @execution.execute_generated_sequence(
    compute_test_sequence(owner),
    [],
    compute_test_limits(),
  ).unwrap()
  @execution.completed_output(result, @pipeline.Step(0)).unwrap()
}

///|
fn carrier_events_consumer_output(
  producer : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
  projection : String,
) -> @execution.CompletedOutput raise {
  let consumer = typed_receiver(producer, projection, target=@pipeline.Step(2))
  let binding = @execution.bind_completed_input(consumer, 0, producer, output).unwrap()
  let result = @execution.execute_generated_sequence(
    compute_test_sequence(consumer),
    [],
    compute_test_limits(),
    produced=[binding],
  ).unwrap()
  @execution.completed_output(result, @pipeline.Step(0)).unwrap()
}

///|
test "bounded Events bridge round trip feeds two Relation consumers" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_owner(source_owner)
  let generated = task_test_generated(owner)
  assert_true(
    physical_equal(@execution.generated_sequence_owner(generated), owner),
  )
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let storage_limits = carrier_events_storage_limits()

  let rows_execution = @local_bridge.start_rows_to_events(
    @bounded.control(),
    sequence,
    0,
    external,
    storage_limits,
    4096L,
    fn() { true },
  ).unwrap()
  let events = finish_rows_to_events(rows_execution)
  assert_eq(@local_bridge.cleanup_rows_to_events(rows_execution), Ok(true))

  let watermark_input = @records.prepare_step_read(owner, 1, 0, events).unwrap()
  let watermark_execution = @local_tea.start_watermark(
    @bounded.control(),
    sequence,
    1,
    watermark_input,
    storage_limits,
    4096L,
    fn() { true },
  ).unwrap()
  let watermarked = finish_event_watermark(watermark_execution)
  assert_eq(@local_tea.cleanup_watermark(watermark_execution), Ok(true))

  let projection_input = @records.prepare_step_read(owner, 2, 0, watermarked).unwrap()
  let projection = @local_bridge.start_events_to_rows(
    @bounded.control(),
    task_test_completion(owner),
    sequence,
    2,
    projection_input,
    10,
    { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    1000,
    [external],
  ).unwrap()
  let rows = finish_events_to_rows(projection)
  assert_eq(@local_bridge.cleanup_events_to_rows(projection), Ok(true))
  assert_true(@execution.completed_output_available(rows))
  assert_true(@execution.completed_output_matches_inputs(rows, [external]))
  assert_eq(@execution.completed_row_count(rows), 2)

  let first = carrier_events_consumer_output(
    owner, rows, "[{\"select\":[\"event_id\",\"late\",\"watermark_decision\"]}]",
  )
  let second = carrier_events_consumer_output(
    owner, rows, "[{\"select\":[\"payload\",\"watermark_ms\",\"late\"]}]",
  )
  assert_true(@execution.completed_cell(first, 0, 1) is Some(Boolean(false)))
  assert_true(@execution.completed_cell(first, 1, 1) is Some(Boolean(true)))
  assert_true(@execution.completed_cell(first, 1, 2) is Some(Text("mark")))
  assert_true(@execution.completed_cell(second, 0, 0) is Some(Text("first")))
  assert_true(@execution.completed_cell(second, 1, 1) is Some(Number(10.0)))
}

///|
test "registered Events provider advances and reclaims one typed pipeline" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_owner(source_owner)
  let generated = task_test_generated(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_tea_provider.provider(
    carrier_events_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let execution = @local_connector.start_managed_provider(
    provider,
    generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut output = None
  while output is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.Complete(value, ..) => output = Some(value)
      @local_connector.CarrierComplete(_, ..) =>
        fail("provider returned a Carrier output")
      @local_connector.Failed(_, ..) => fail("provider failed")
      @local_connector.Stopped(..) => fail("provider stopped")
    }
  }
  let completed = output.unwrap()
  assert_eq(@execution.completed_row_count(completed), 2)
  assert_true(@execution.completed_output_matches_inputs(completed, [external]))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@execution.completed_output_available(completed))
}

///|
test "registered Events provider returns retained Carrier material" {
  let source_owner = carrier_events_source_owner()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_output_owner(source_owner)
  let generated = task_test_generated(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let provider = @local_tea_provider.provider(
    carrier_events_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let execution = @local_connector.start_managed_provider(
    provider,
    generated,
    [external],
    10,
    1000,
  ).unwrap()
  let mut material = None
  while material is None {
    match @local_connector.advance_managed_provider(execution, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(value, ..) => material = Some(value)
      @local_connector.Complete(_, ..) => fail("provider returned rows")
      @local_connector.Failed(_, ..) => fail("provider failed")
      @local_connector.Stopped(..) => fail("provider stopped")
    }
  }
  let retained = material.unwrap()
  assert_eq(
    @carrier_runtime.material_kind(retained),
    @carrier_contract.EventsKind,
  )
  assert_eq(@carrier_runtime.material_storage_bytes(retained), Some(4096L))
  assert_true(@local_connector.managed_provider_stopped(execution))
  assert_true(
    @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
  )
  assert_true(@carrier_runtime.material_available(retained))
  assert_true(@carrier_runtime.reclaim_material(retained))
}

///|
test "registered Events provider separates stop from cleanup" {
  for
    variant in [
      "watermark", "dedupe", "window_fixed", "window_sliding", "session", "session_global",
      "session_parameter",
    ] {
    let source_owner = carrier_events_source_owner()
    let source = carrier_events_source_output(source_owner)
    let owner = carrier_events_owner(source_owner, variant~)
    let generated = task_test_generated(owner)
    let external = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
      100,
      1000,
    ).unwrap()
    let provider = @local_tea_provider.provider(
      carrier_events_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        generated,
        dispatch_test_limits().local_execution,
        dispatch_test_limits().guards,
      ).unwrap(),
    )
    let execution = @local_connector.start_managed_provider(
      provider,
      generated,
      [external],
      10,
      1000,
    ).unwrap()
    assert_true(@local_connector.cancel_managed_provider(execution))
    assert_true(
      @local_connector.advance_managed_provider(execution, 1).unwrap()
      is @local_connector.Stopped(..),
    )
    assert_true(@local_connector.managed_provider_stopped(execution))
    assert_true(
      @local_connector.cleanup_managed_provider(execution).unwrap_or(false),
    )
    assert_true(@execution.producer_read_available(external))
  }
}

///|
test "standard Host runs registered bounded Events provider" {
  for
    variant in [
      "watermark", "dedupe", "window_fixed", "window_sliding", "session", "session_global",
      "session_parameter",
    ] {
    let publication = variant == "session"
    let (run, issuer) = captured_graph_fixture(
      local_carrier_events_chain=true,
      local_carrier_events_variant=variant,
      managed_publication=publication,
      parameter_json=if variant == "session_parameter" {
        "{\"minimum\":2}"
      } else {
        "{\"minimum\":1}"
      },
    )
    if publication {
      assert_true(
        @strategy.configure_captured_managed_identity_policy(
          run, true, false, false, false,
        ),
      )
    }
    let registry = search_registry()
    let limits = dispatch_test_limits()
    let sequences = dispatch_test_generated(run)
    let cleanup_attempts = Ref(0)
    let provider = delayed_cleanup_provider(
      @local_tea_provider.provider(
        carrier_events_storage_limits(),
        4096L,
        @execution.generated_sequence_capacity(
          sequences[1],
          limits.local_execution,
          limits.guards,
        ).unwrap(),
      ),
      cleanup_attempts,
    )
    let modules = @builtin.configure_compute_modules(
      @host_driver.open_dispatch_driver(run),
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          @connector.capability_registration_at(registry, 0).unwrap(),
          {
            sequences,
            managed_providers: [provider],
            managed_capacity: limits.capacity,
            execution: limits.local_execution,
            measurement: limits.guards,
            max_work: limits.candidate_work,
          },
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      ),
    ).unwrap()
    let installed = @builtin.configured_local_module(modules).unwrap()
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.input_values,
        wire: {
          max_bytes: 3000,
          max_nodes: 300,
          max_depth: 10,
          max_columns: 10,
          max_order_work: 1000,
        },
        row: {
          max_bytes: 3000,
          max_nodes: 300,
          max_depth: 10,
          max_text_bytes: 3000,
        },
        max_batch_bytes: 3000,
      },
      None,
    ).unwrap()

    let values_live = Ref(true)
    let (values_ops, values) = run_local_managed_test_task(
      installed,
      run,
      1,
      [],
      [],
      1,
      values_live,
      obligations?=if publication {
        Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
      } else {
        None
      },
    )
    let values_rows = local_managed_test_rows(values_ops)
    let events_live = Ref(true)
    let event_obligations = if publication {
      Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
    } else {
      None
    }
    let (events_ops, events) = run_local_managed_test_task(
      installed,
      run,
      2,
      [values],
      [values_rows],
      2,
      events_live,
      obligations?=event_obligations,
    )
    let event_rows = local_managed_test_rows(events_ops)
    let expected_rows = if variant == "dedupe" {
      2
    } else if variant == "window_sliding" {
      6
    } else {
      3
    }
    assert_eq(event_rows.length(), expected_rows)
    if variant == "dedupe" {
      assert_true(event_rows[0].contains("\"event_id\":2"))
      assert_true(event_rows[1].contains("\"event_id\":4"))
    } else if variant == "window_fixed" || variant == "window_sliding" {
      assert_true(event_rows[0].contains("\"window_start_ms\""))
      assert_true(event_rows[0].contains("\"window_end_ms\""))
    } else if variant.has_prefix("session") {
      assert_true(event_rows[0].contains("\"event_id\":2"))
      assert_true(event_rows[1].contains("\"event_id\":1"))
      assert_true(event_rows[2].contains("\"event_id\":3"))
      assert_true(event_rows[0].contains("\"session_start_ms\":1"))
      assert_true(event_rows[0].contains("\"session_id\":\"session:"))
      assert_true(event_rows[2].contains("\"session_start_ms\":13"))
      if variant == "session_parameter" {
        assert_true(event_rows[0].contains("\"session_end_ms\":3"))
        assert_true(event_rows[1].contains("\"session_start_ms\":3"))
        assert_true(event_rows[1].contains("\"session_end_ms\":5"))
        assert_true(event_rows[2].contains("\"session_end_ms\":15"))
      } else {
        assert_true(event_rows[0].contains("\"session_end_ms\":13"))
        assert_true(event_rows[2].contains("\"session_end_ms\":23"))
      }
    } else {
      assert_true(event_rows[0].contains("\"watermark_decision\":\"keep\""))
      assert_true(event_rows[1].contains("\"late\":true"))
    }
    if publication {
      let requirements = @execution.managed_obligations_identities(
        event_obligations.unwrap(),
      )
      let published = requirements.filter(requirement => {
        requirement.domain == @execution.LogicalRelation &&
        requirement.subject == @execution.NamedResult
      })
      assert_eq(published.length(), 1)
      match
        @execution.managed_completed_identity_requirement_status(
          events,
          published[0],
        ) {
        Some(@execution.EstablishedSourceRetained(contract, cid)) => {
          assert_eq(
            contract,
            @execution.logical_relation_canonical_contract_cid(),
          )
          assert_eq(
            cid, "sha256:cdb4e95a24f02c009ed6e25c03c17311d529d7941e7f594b24e73b5bc1d23ba3",
          )
        }
        _ => fail("session output did not establish publication identity")
      }
      assert_true(
        @execution.managed_completed_deadline_satisfied(
          events,
          @execution.BeforePublication,
        ),
      )
    }

    let first_live = Ref(true)
    let (first_ops, first) = run_local_managed_test_task(
      installed,
      run,
      3,
      [events],
      [event_rows],
      3,
      first_live,
      obligations?=if publication {
        Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
      } else {
        None
      },
    )
    let second_live = Ref(true)
    let (second_ops, second) = run_local_managed_test_task(
      installed,
      run,
      4,
      [events],
      [event_rows],
      4,
      second_live,
      obligations?=if publication {
        Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
      } else {
        None
      },
    )
    assert_eq(local_managed_test_rows(first_ops).length(), expected_rows)
    assert_eq(local_managed_test_rows(second_ops).length(), expected_rows)

    first_live.val = false
    @strategy.close_captured_task_output(run, 3)
    (first_ops.close)()
    (first_ops.cleanup_refresh)() |> ignore
    assert_false(@execution.managed_completed_output_available(first))
    assert_true(@execution.managed_completed_output_available(second))
    assert_true(@execution.managed_completed_output_available(events))

    second_live.val = false
    @strategy.close_captured_task_output(run, 4)
    (second_ops.close)()
    (second_ops.cleanup_refresh)() |> ignore
    events_live.val = false
    @strategy.close_captured_task_output(run, 2)
    (events_ops.close)()
    assert_false((events_ops.cleanup_refresh)())
    assert_true((events_ops.cleanup_refresh)())
    assert_eq(cleanup_attempts.val, 2)
    values_live.val = false
    @strategy.close_captured_task_output(run, 1)
    (values_ops.close)()
    (values_ops.cleanup_refresh)() |> ignore
    @strategy.stop_captured_dag(run)
    @strategy.close_captured_task_output(run, 0)
    @strategy.refresh_captured_retention(run)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.held_bytes, 0L)
    @mock.close_mock_query_issuer(issuer)
  }
}
