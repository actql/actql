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
fn carrier_events_owner(source : @lower.BoundPrepared) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"watermark_events\":{\"watermark_ms\":10,\"policy\":\"mark\"}},{\"events\":true}]",
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
