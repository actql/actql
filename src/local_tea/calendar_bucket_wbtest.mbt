///|
fn calendar_bucket_generated() -> @execution.GeneratedSequence raise {
  let checked = @pipeline.check(
    event_window_cursor(
      "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-03T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"},{\"calendar_bucket\":{\"time\":\"start\",\"into\":\"month\",\"unit\":\"month\",\"timezone\":\"UTC\"},\"as\":\"bucketed\"}]",
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
    max_cells: 4000,
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
    ["calendar_series_0", "calendar_bucket_1"],
    100000,
    10000,
  ).unwrap()
}

///|
fn calendar_bucket_source(
  generated : @execution.GeneratedSequence,
) -> @execution.CompletedOutput raise {
  let active = start_calendar_series(
    @bounded.control(),
    @execution.select_generated_sequence_step(generated, 0).unwrap(),
    0,
    2,
    calendar_kernel_values(),
    1000,
    1000,
  ).unwrap()
  let mut output = None
  for _ in 0..<1000 {
    if output is None {
      match advance_calendar_series(active, 64).unwrap() {
        CalendarContinue(_) => ()
        CalendarComplete(value, ..) => output = Some(value)
        _ => fail("original two-day source must complete")
      }
    }
  }
  assert_true(cleanup_calendar_series(active).unwrap())
  output.unwrap()
}

///|
fn calendar_bucket_read(
  generated : @execution.GeneratedSequence,
  source : @execution.CompletedOutput,
) -> @execution.ProducerRead raise {
  let owner = @execution.generated_sequence_owner(generated)
  let binding = @execution.bind_completed_operation_input(
    owner, 1, 0, owner, source,
  ).unwrap()
  @execution.prepare_producer_read(owner, binding, 1000, 1000).unwrap()
}

///|
test "Calendar bucket preserves original rows schema and full month boundaries across quantum" {
  let generated = calendar_bucket_generated()
  let source = calendar_bucket_source(generated)
  let read = calendar_bucket_read(generated, source)
  let selected = @execution.select_generated_sequence_step(generated, 1).unwrap()
  let mut logical_work = None
  for quantum in [1, 7, 64] {
    let active = start_calendar_bucket(
      @bounded.control(),
      selected,
      1,
      read,
      2,
      calendar_kernel_values(),
      1000,
      1000,
    ).unwrap()
    let mut output = None
    let mut previous = 0L
    let mut final_work = 0L
    for _ in 0..<10000 {
      if output is None {
        match advance_calendar_bucket(active, quantum).unwrap() {
          BucketContinue(work~, ..) => {
            assert_true(
              work >= previous && work - previous <= quantum.to_int64(),
            )
            previous = work
          }
          BucketComplete(value, progress~, work~) => {
            assert_eq(progress, 2L)
            assert_true(
              work >= previous && work - previous <= quantum.to_int64(),
            )
            output = Some(value)
            final_work = work
          }
          _ => fail("original Calendar bucket must complete")
        }
      }
    }
    let output = output.unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_eq(@execution.completed_column_name(output, 0), Some("end"))
    assert_eq(@execution.completed_column_name(output, 1), Some("month"))
    assert_eq(@execution.completed_column_name(output, 2), Some("start"))
    assert_true(
      @execution.completed_output_matches_operation_inputs(output, 1, [read]),
    )
    for row in 0..<2 {
      assert_true(
        @execution.completed_cell(output, row, 0)
        is Some(Captured(@value.Timestamp(end))) &&
        @execution.completed_cell(source, row, 0)
        is Some(Captured(@value.Timestamp(original_end))) &&
        end == original_end,
      )
      assert_true(
        @execution.completed_cell(output, row, 2)
        is Some(Captured(@value.Timestamp(start))) &&
        @execution.completed_cell(source, row, 1)
        is Some(Captured(@value.Timestamp(original_start))) &&
        start == original_start,
      )
      guard @execution.completed_cell(output, row, 1)
        is Some(Captured(@value.Object(fields))) else {
        fail("closed month interval")
      }
      assert_eq(@value.element_count(fields), 2)
      assert_true(
        @value.element_at(fields, 0)
        is Some(("end", @value.Timestamp("2000-02-01T00:00:00.000Z"))),
      )
      assert_true(
        @value.element_at(fields, 1)
        is Some(("start", @value.Timestamp("2000-01-01T00:00:00.000Z"))),
      )
    }
    if logical_work is Some(original) {
      assert_eq(final_work, original)
    } else {
      logical_work = Some(final_work)
    }
    assert_true(cleanup_calendar_bucket(active).unwrap())
    assert_false(calendar_bucket_cleanup_pending(active))
    assert_true(@execution.completed_output_available(output))
    assert_true(
      advance_calendar_bucket(active, 1)
      is Err(CalendarBucketExecution(@bounded.Terminal)),
    )
  }
}

///|
test "Calendar bucket enforces selected quota and exact live producer binding" {
  let generated = calendar_bucket_generated()
  let source = calendar_bucket_source(generated)
  let read = calendar_bucket_read(generated, source)
  assert_eq(@execution.producer_read_cell_present(read, 0, 0), Ok(true))
  assert_true(
    @execution.producer_read_cell_present(read, 2, 0) is Err(InvalidLayout),
  )
  assert_true(
    @execution.producer_read_cell_present(read, 0, 2) is Err(InvalidLayout),
  )
  let selected = @execution.select_generated_sequence_step(generated, 1).unwrap()
  let short = @execution.constrain_generated_calendar_output(selected, 1, 1L).unwrap()
  let active = start_calendar_bucket(
    @bounded.control(),
    short,
    1,
    read,
    1000,
    calendar_kernel_values(),
    1000,
    1000,
  ).unwrap()
  let mut failed = false
  for _ in 0..<1000 {
    if !failed {
      match advance_calendar_bucket(active, 64).unwrap() {
        BucketContinue(_) => ()
        BucketFailed(
          CalendarBucketRow(@execution.OutputRowCapture(CaptureLimit)),
          progress~,
          ..
        ) => {
          assert_eq(progress, 1L)
          failed = true
        }
        _ => fail("one-short policy must refuse the second row")
      }
    }
  }
  assert_true(failed)
  while !cleanup_calendar_bucket(active).unwrap() {

  }
  assert_false(calendar_bucket_cleanup_pending(active))
  assert_true(
    start_calendar_bucket(
      @bounded.control(),
      selected,
      0,
      read,
      2,
      calendar_kernel_values(),
      1000,
      1000,
    )
    is Err(InvalidCalendarBucketKernel),
  )
  let foreign = calendar_bucket_generated()
  let foreign_read = calendar_bucket_read(
    foreign,
    calendar_bucket_source(foreign),
  )
  assert_true(
    start_calendar_bucket(
      @bounded.control(),
      selected,
      1,
      foreign_read,
      2,
      calendar_kernel_values(),
      1000,
      1000,
    )
    is Err(InvalidCalendarBucketKernel),
  )
}

///|
test "Calendar bucket cancellation retains cursor output and exact source custody" {
  let generated = calendar_bucket_generated()
  let original = calendar_bucket_source(generated)
  let live = Ref(true)
  let source = @execution.restrict_completed_output(original, () => live.val)
  let read = calendar_bucket_read(generated, source)
  let selected = @execution.select_generated_sequence_step(generated, 1).unwrap()
  let control = @bounded.control()
  let active = start_calendar_bucket(
    control,
    selected,
    1,
    read,
    2,
    calendar_kernel_values(),
    1000,
    1000,
  ).unwrap()
  assert_true(advance_calendar_bucket(active, 3) is Ok(BucketContinue(_)))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_calendar_bucket(active, 1) is Ok(BucketStopped(_)))
  while !cleanup_calendar_bucket(active).unwrap() {

  }
  assert_false(calendar_bucket_cleanup_pending(active))
  assert_true(@execution.completed_output_available(source))
  let invalid = start_calendar_bucket(
    @bounded.control(),
    selected,
    1,
    read,
    2,
    calendar_kernel_values(),
    1000,
    1000,
  ).unwrap()
  live.val = false
  assert_true(
    @execution.producer_read_cell_present(read, 0, 0) is Err(Unavailable),
  )
  assert_true(
    advance_calendar_bucket(invalid, 1)
    is Ok(BucketFailed(InvalidCalendarBucketInput, ..)),
  )
  while !cleanup_calendar_bucket(invalid).unwrap() {

  }
  assert_false(calendar_bucket_cleanup_pending(invalid))
}
