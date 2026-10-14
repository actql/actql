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
    event_window_cursor(
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
  let owner = event_window_bind(checked)
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
fn calendar_kernel_values() -> @execution.ValueLimits {
  { max_nodes: 10000, max_text_bytes: 100000, max_depth: 10, max_work: 100000, }
}

///|
test "Calendar bounded series preserves full intervals and logical work across quantum" {
  let generated = calendar_kernel_generated(
    "1999-12-31T12:00:00.000Z", "2000-01-02T06:00:00.000Z",
  )
  let expected = [
    ("1999-12-31T00:00:00.000Z", "2000-01-01T00:00:00.000Z"),
    ("2000-01-01T00:00:00.000Z", "2000-01-02T00:00:00.000Z"),
    ("2000-01-02T00:00:00.000Z", "2000-01-03T00:00:00.000Z"),
  ]
  let mut first_work = None
  for quantum in [1, 7, 64] {
    let active = start_calendar_series(
      @bounded.control(),
      generated,
      0,
      4,
      calendar_kernel_values(),
      1000,
      1000,
    ).unwrap()
    let mut completed = None
    let mut prior_work = 0L
    let mut total_work = 0L
    for _ in 0..<2000 {
      if completed is None {
        match advance_calendar_series(active, quantum).unwrap() {
          CalendarContinue(work~, ..) => {
            assert_true(
              work >= prior_work && work - prior_work <= quantum.to_int64(),
            )
            prior_work = work
          }
          CalendarComplete(output, progress~, work~) => {
            assert_eq(progress, 3L)
            assert_true(
              work >= prior_work && work - prior_work <= quantum.to_int64(),
            )
            total_work = work
            completed = Some(output)
          }
          _ => fail("original Calendar interval realization must complete")
        }
      }
    }
    let output = completed.unwrap()
    assert_eq(@execution.completed_row_count(output), 3)
    // The shared physical Schema uses canonical name order. Authored Named
    // Result order remains a separate existing projection, not these slots.
    assert_eq(@execution.completed_column_name(output, 0), Some("end"))
    assert_eq(@execution.completed_column_name(output, 1), Some("start"))
    for row, (start, end) in expected {
      assert_true(
        @execution.completed_cell(output, row, 1)
        is Some(Captured(@value.Timestamp(actual))) &&
        actual == start,
      )
      assert_true(
        @execution.completed_cell(output, row, 0)
        is Some(Captured(@value.Timestamp(actual))) &&
        actual == end,
      )
    }
    if first_work is Some(work) {
      assert_eq(total_work, work)
    } else {
      first_work = Some(total_work)
    }
    assert_true(cleanup_calendar_series(active).unwrap())
    assert_false(calendar_series_cleanup_pending(active))
    assert_true(@execution.completed_output_available(output))
    assert_true(
      advance_calendar_series(active, 1)
      is Err(CalendarExecution(@bounded.Terminal)),
    )
  }
}

///|
test "Calendar bounded empty range needs only finalization and refuses wrong coordinate" {
  let generated = calendar_kernel_generated(
    "2000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.000Z",
  )
  assert_true(
    start_calendar_series(
      @bounded.control(),
      generated,
      1,
      0,
      calendar_kernel_values(),
      1000,
      1000,
    )
    is Err(InvalidCalendarKernel),
  )
  assert_true(
    start_calendar_series(
      @bounded.control(),
      generated,
      0,
      0,
      calendar_kernel_values(),
      1000,
      1000,
      control_work_limit=Some(0),
    )
    is Err(CalendarControlWorkLimit),
  )
  let active = start_calendar_series(
    @bounded.control(),
    generated,
    0,
    0,
    calendar_kernel_values(),
    1000,
    1000,
    control_work_limit=Some(1),
  ).unwrap()
  match advance_calendar_series(active, 1).unwrap() {
    CalendarComplete(output, progress~, work~) => {
      assert_eq(progress, 0L)
      assert_eq(work, 1L)
      assert_eq(@execution.completed_row_count(output), 0)
    }
    _ => fail("empty range retains a real typed zero-row completion")
  }
  assert_true(cleanup_calendar_series(active).unwrap())
  assert_false(calendar_series_cleanup_pending(active))
}

///|
test "Calendar cancellation retains the original output handle for sliced reclamation" {
  let generated = calendar_kernel_generated(
    "2000-01-01T00:00:00.000Z", "2001-01-01T00:00:00.000Z",
  )
  let control = @bounded.control()
  let active = start_calendar_series(
    control,
    generated,
    0,
    400,
    calendar_kernel_values(),
    1000,
    1000,
  ).unwrap()
  let emitted = Ref(0L)
  for _ in 0..<1000 {
    if emitted.val < 130L {
      match advance_calendar_series(active, 64).unwrap() {
        CalendarContinue(progress~, ..) => emitted.val = progress
        _ => fail("cancel control must still own a live partial output")
      }
    }
  }
  assert_true(emitted.val >= 130L)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_calendar_series(active, 1).unwrap() is CalendarStopped(_, ..),
  )
  assert_true(calendar_series_cleanup_pending(active))
  assert_false(cleanup_calendar_series(active).unwrap())
  assert_true(calendar_series_cleanup_pending(active))
  let mut done = false
  for _ in 0..<10 {
    if !done {
      done = cleanup_calendar_series(active).unwrap()
    }
  }
  assert_true(done)
  assert_false(calendar_series_cleanup_pending(active))
  assert_true(
    advance_calendar_series(active, 1)
    is Err(CalendarExecution(@bounded.Terminal)),
  )
}

///|
test "Calendar bounded value admission retains exact and one short work limits" {
  let generated = calendar_kernel_generated(
    "2000-01-01T00:00:00.000Z", "2000-01-03T00:00:00.000Z",
  )
  // Original value-weight law: one row node, eight field-name UTF8 bytes and
  // two timestamp values of one node plus 24 bytes each = 59 per row.
  // This is independent of cursor/control work and is not a capacity estimate.
  for work in [118, 117] {
    let active = start_calendar_series(
      @bounded.control(),
      generated,
      0,
      4,
      { ..calendar_kernel_values(), max_work: work, },
      1000,
      1000,
      control_work_limit=Some(10000),
    ).unwrap()
    let mut terminal = false
    for _ in 0..<1000 {
      if !terminal {
        match advance_calendar_series(active, 7).unwrap() {
          CalendarContinue(_) => ()
          CalendarComplete(output, ..) => {
            assert_eq(work, 118)
            assert_eq(@execution.completed_row_count(output), 2)
            terminal = true
          }
          CalendarFailed(CalendarOutput(CaptureLimit), ..) => {
            assert_eq(work, 117)
            terminal = true
          }
          _ => fail("the original value budget must classify the first failure")
        }
      }
    }
    assert_true(terminal)
    let mut cleaned = false
    for _ in 0..<10 {
      if !cleaned {
        cleaned = cleanup_calendar_series(active).unwrap()
      }
    }
    assert_true(cleaned)
    assert_false(calendar_series_cleanup_pending(active))
  }
}

///|
test "Calendar actual row quota remains distinct from conservative preparation bound" {
  let generated = calendar_kernel_generated(
    "2000-01-01T00:00:00.000Z", "2000-01-03T00:00:00.000Z",
  )
  for limit in [2, 1] {
    let active = start_calendar_series(
      @bounded.control(),
      generated,
      0,
      limit,
      calendar_kernel_values(),
      1000,
      1000,
    ).unwrap()
    let mut terminal = false
    for _ in 0..<1000 {
      if !terminal {
        match advance_calendar_series(active, 7).unwrap() {
          CalendarContinue(_) => ()
          CalendarComplete(output, ..) => {
            assert_eq(limit, 2)
            assert_eq(@execution.completed_row_count(output), 2)
            terminal = true
          }
          CalendarFailed(CalendarBoundary(SeriesRowLimit), ..) => {
            assert_eq(limit, 1)
            terminal = true
          }
          _ => fail("actual row quota must be enforced by the original cursor")
        }
      }
    }
    assert_true(terminal)
    let mut cleaned = false
    for _ in 0..<10 {
      if !cleaned {
        cleaned = cleanup_calendar_series(active).unwrap()
      }
    }
    assert_true(cleaned)
    assert_false(calendar_series_cleanup_pending(active))
  }
}

///|
test "Calendar selected policy quota retains exact occurrence and cannot widen" {
  let generated = calendar_kernel_generated(
    "2000-01-01T00:00:00.000Z", "2000-01-03T00:00:00.000Z",
  )
  assert_true(
    @execution.constrain_generated_calendar_output(generated, 1, 2L)
    is Err(InputSet),
  )
  assert_true(
    @execution.constrain_generated_calendar_output(generated, 0, -1L)
    is Err(InvalidLimits),
  )
  assert_eq(@execution.generated_calendar_output_ceiling(generated, 0), None)
  let exact = @execution.constrain_generated_calendar_output(generated, 0, 2L).unwrap()
  assert_eq(@execution.generated_calendar_output_ceiling(exact, 0), Some(2L))
  let widened = @execution.constrain_generated_calendar_output(exact, 0, 1000L).unwrap()
  assert_eq(@execution.generated_calendar_output_ceiling(widened, 0), Some(2L))
  let selected = @execution.select_generated_sequence_step(widened, 0).unwrap()
  assert_eq(@execution.generated_calendar_output_ceiling(selected, 0), Some(2L))
  let short = @execution.constrain_generated_calendar_output(selected, 0, 1L).unwrap()
  for (original, succeeds) in [(selected, true), (short, false)] {
    let active = start_calendar_series(
      @bounded.control(),
      original,
      0,
      1000,
      calendar_kernel_values(),
      1000,
      1000,
    ).unwrap()
    let mut terminal = false
    for _ in 0..<1000 {
      if !terminal {
        match advance_calendar_series(active, 7).unwrap() {
          CalendarContinue(_) => ()
          CalendarComplete(output, ..) => {
            assert_true(succeeds)
            assert_eq(@execution.completed_row_count(output), 2)
            terminal = true
          }
          CalendarFailed(CalendarBoundary(SeriesRowLimit), ..) => {
            assert_false(succeeds)
            terminal = true
          }
          _ => fail("selected policy must retain the exact Calendar quota")
        }
      }
    }
    assert_true(terminal)
    while !cleanup_calendar_series(active).unwrap() {

    }
    assert_false(calendar_series_cleanup_pending(active))
  }
}
