///|
fn calendar_provider_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="local-tea-window.aql",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn calendar_kernel_profile() -> @calendar_profile.Profile {
  @calendar_profile.admit(
    @utf8.encode(
      "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}",
    ),
    "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
    "test-fixture",
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
}

///|
fn calendar_kernel_generated(
  start : String,
  end : String,
) -> @execution.GeneratedSequence raise {
  let checked = @pipeline.check(
    calendar_provider_cursor(
      "[{\"calendar_series\":{\"start\":\"" +
      start +
      "\",\"end\":\"" +
      end +
      "\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"}]",
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
    calendar_profile=Some(calendar_kernel_profile()),
  ).unwrap()
  let owner = @lower.bind_parameters(
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
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 10,
    max_rows: 1000,
    max_cells: 2000,
    max_bindings: 10,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 1000,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 1000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
  let contracts = @execution.admit_relation_registry(
    calendar_runtime_registered_body(),
    calendar_runtime_registered_values(),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  @execution.prepare_generated_sequence(
    contracts,
    sequence,
    [],
    ["calendar_series_0"],
    100000,
    10000,
  ).unwrap()
}

///|
test "installed Calendar family preserves selected quota output work and cleanup" {
  let base = calendar_kernel_generated(
    "2000-01-01T00:00:00.000Z", "2000-01-03T00:00:00.000Z",
  )
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 1000,
      metadata_entries: 1000,
      retained_entries: 1000,
      operation_entries: 1000,
      input_values: {
        max_nodes: 10000,
        max_text_bytes: 100000,
        max_depth: 100,
        max_work: 100000,
      },
      output_values: {
        max_nodes: 10000,
        max_text_bytes: 100000,
        max_depth: 100,
        max_work: 100000,
      },
    },
    max_work: 100000,
    max_frames: 1000,
  }
  let provider = calendar_series_provider(
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
  for quota in [2L, 1L] {
    let constrained = @execution.constrain_generated_calendar_output(
      base, 0, quota,
    ).unwrap()
    let selected = @execution.select_generated_sequence_step(constrained, 0).unwrap()
    assert_true(@local.managed_provider_accepts(provider, selected))
    let active = @local.start_managed_provider_with_execution(
      provider,
      selected,
      [],
      1000,
      100000,
      execution,
    ).unwrap()
    let mut terminal = false
    let mut total_progress = 0L
    let mut total_work = 0L
    for _ in 0..<1000 {
      if !terminal {
        let poll = @local.advance_managed_provider(active, 7).unwrap()
        match poll {
          Continue(progress~, work~) => {
            total_progress += progress
            total_work += work
            assert_true(work >= 0L && work <= 7L)
          }
          Complete(output, progress~, work~) => {
            assert_eq(quota, 2L)
            total_progress += progress
            total_work += work
            assert_eq(@execution.completed_row_count(output), 2)
            assert_eq(@execution.completed_column_name(output, 0), Some("end"))
            assert_eq(
              @execution.completed_column_name(output, 1),
              Some("start"),
            )
            assert_true(
              @execution.completed_cell(output, 0, 1)
              is Some(Captured(@value.Timestamp("2000-01-01T00:00:00.000Z"))),
            )
            assert_true(
              @execution.completed_cell(output, 1, 0)
              is Some(Captured(@value.Timestamp("2000-01-03T00:00:00.000Z"))),
            )
            terminal = true
          }
          Failed(@connector.Execution(@execution.InputSet), progress~, work~) => {
            assert_eq(quota, 1L)
            total_progress += progress
            total_work += work
            terminal = true
          }
          _ => fail("Calendar must keep its original managed terminal boundary")
        }
      }
    }
    assert_true(terminal)
    assert_eq(total_progress, quota)
    assert_true(total_work > 0L)
    assert_eq(
      @local.managed_provider_cumulative_work(active).unwrap(),
      total_work,
    )
    assert_true(@local.managed_provider_stopped(active))
    while !@local.cleanup_managed_provider(active).unwrap() {

    }
    assert_true(@local.cleanup_managed_provider(active).unwrap())
  }
}
