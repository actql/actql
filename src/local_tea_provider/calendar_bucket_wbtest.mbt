///|
test "selected installed Calendar bucket keeps original producer result and cleanup" {
  let generated = calendar_kernel_generated(
    "2000-01-01T00:00:00.000Z",
    "2000-01-03T00:00:00.000Z",
    bucket=true,
  )
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
    max_work: 100000,
  }
  let source = @tea.start_calendar_series(
    @bounded.control(),
    @execution.select_generated_sequence_step(generated, 0).unwrap(),
    0,
    2,
    values,
    1000,
    1000,
  ).unwrap()
  let mut completed = None
  for _ in 0..<1000 {
    if completed is None {
      match @tea.advance_calendar_series(source, 64).unwrap() {
        CalendarContinue(_) => ()
        CalendarComplete(output, ..) => completed = Some(output)
        _ => fail("original Calendar source must complete")
      }
    }
  }
  assert_true(@tea.cleanup_calendar_series(source).unwrap())
  let owner = @execution.generated_sequence_owner(generated)
  let binding = @execution.bind_completed_operation_input(
    owner,
    1,
    0,
    owner,
    completed.unwrap(),
  ).unwrap()
  let read = @execution.prepare_producer_read(owner, binding, 1000, 1000).unwrap()
  let selected = @execution.select_generated_sequence_step(generated, 1).unwrap()
  let provider = calendar_bucket_provider(
    {
      max_input_records: 100,
      max_records: 100,
      max_fields_per_record: 100,
      max_value_bytes: 10000,
      max_total_value_bytes: 100000,
      max_retained_value_bytes: 100000,
      max_value_nodes: 10000,
      max_value_depth: 100,
      max_contract_work: 10000,
      max_work: 100000,
      max_workspace_slots: 10000,
    },
    @execution.execution_capacity(16777216L, 16777216L).unwrap(),
  )
  assert_true(@local.managed_provider_accepts(provider, selected))
  assert_false(
    @local.managed_provider_accepts(
      provider,
      @execution.select_generated_sequence_step(generated, 0).unwrap(),
    ),
  )
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 1000,
      metadata_entries: 1000,
      retained_entries: 1000,
      operation_entries: 1000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 1000,
  }
  assert_true(
    @local.start_managed_provider_with_inputs_and_execution(
      provider,
      selected,
      [],
      1000,
      100000,
      execution,
    )
    is Err(@connector.InvalidLimits),
  )
  let active = @local.start_managed_provider_with_inputs_and_execution(
    provider,
    selected,
    [@local.managed_provider_relation_input(read)],
    1000,
    100000,
    execution,
  ).unwrap()
  let mut result = None
  let mut total_work = 0L
  let mut total_progress = 0L
  for _ in 0..<1000 {
    if result is None {
      match @local.advance_managed_provider(active, 7).unwrap() {
        Continue(progress~, work~) => {
          total_work += work
          total_progress += progress
          assert_true(work >= 0L && work <= 7L)
        }
        Complete(output, progress~, work~) => {
          total_work += work
          total_progress += progress
          result = Some(output)
        }
        _ =>
          fail(
            "selected Calendar bucket must complete under its original owner",
          )
      }
    }
  }
  let result = result.unwrap()
  assert_eq(@execution.completed_row_count(result), 2)
  assert_eq(@execution.completed_column_name(result, 1), Some("month"))
  for row in 0..<2 {
    guard @execution.completed_cell(result, row, 1)
      is Some(Captured(@value.Object(fields))) else {
      fail("closed original month")
    }
    assert_true(
      @value.element_at(fields, 0)
      is Some(("end", @value.Timestamp("2000-02-01T00:00:00.000Z"))),
    )
    assert_true(
      @value.element_at(fields, 1)
      is Some(("start", @value.Timestamp("2000-01-01T00:00:00.000Z"))),
    )
  }
  assert_eq(total_progress, 2L)
  assert_eq(
    @local.managed_provider_cumulative_work(active).unwrap(),
    total_work,
  )
  assert_true(
    @execution.completed_output_matches_operation_inputs(result, 1, [read]),
  )
  while !@local.cleanup_managed_provider(active).unwrap() {

  }
  assert_true(@local.cleanup_managed_provider(active).unwrap())
  assert_true(@execution.completed_output_available(result))
  assert_true(@execution.producer_read_available(read))
}
