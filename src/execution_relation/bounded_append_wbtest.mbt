///|
fn bounded_append_source(
  rows : String,
  schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    rows +
    "},\"as\":\"source\"}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    10000,
    1000,
  ).unwrap()
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
  ).unwrap()
  (owner, completed_output(completed, @pipeline.Step(0)).unwrap())
}

///|
fn bounded_append_fixture(
  max_work? : Int = 1000,
  max_entries? : Int = 100,
  left_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  right_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  left_rows? : String = "[{\"id\":1},{\"id\":2}]",
  right_rows? : String = "[{\"id\":3}]",
  input_nodes? : Int = 1000,
) -> (
  @bounded.Control,
  Result[BoundedAppendExecution, BoundedAppendIssue],
  Array[ProducerRead],
) raise {
  let (left_owner, left_output) = bounded_append_source(
    left_rows,
    schema=left_schema,
  )
  let (right_owner, right_output) = bounded_append_source(
    right_rows,
    schema=right_schema,
  )
  let left_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(left_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let right_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(right_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"l\",\"append\":{\"with\":\"r\"}}]"),
    [
      ("l", @pipeline.ProducedInput(left_producer)),
      ("r", @pipeline.ProducedInput(right_producer)),
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
  let receiver = @lower.bind_parameters(
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
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["append_0"],
    10000,
    1000,
  ).unwrap()
  let left = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, left_owner, left_output).unwrap(),
    100,
    10000,
  ).unwrap()
  let right = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 1, right_owner, right_output).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_append(
    control,
    generated,
    left,
    right,
    3,
    {
      max_nodes: input_nodes,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 10000,
    },
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    1000,
  )
  (control, execution, [left, right])
}

///|
test "bounded append admits both input occurrences cumulatively" {
  let (_, zero, _) = bounded_append_fixture(input_nodes=0)
  let rejected = zero.unwrap()
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_append(rejected, 1).unwrap() {
        BoundedAppendFailed(InputLimit, ..) => failed = true
        BoundedAppendContinue(..) => ()
        _ => fail("zero input budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_append(rejected).unwrap())
  let (_, exact, _) = bounded_append_fixture(input_nodes=6)
  let execution = exact.unwrap()
  let mut complete = false
  for _ in 0..<100 {
    if !complete {
      match advance_bounded_append(execution, 1).unwrap() {
        BoundedAppendComplete(_, ..) => complete = true
        BoundedAppendContinue(..) => ()
        _ => fail("exact input budget rejected")
      }
    }
  }
  assert_true(complete)
  assert_true(cleanup_bounded_append(execution).unwrap())
  let (_, short, _) = bounded_append_fixture(input_nodes=5)
  let rejected = short.unwrap()
  failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_append(rejected, 1).unwrap() {
        BoundedAppendFailed(InputLimit, ..) => failed = true
        BoundedAppendContinue(..) => ()
        _ => fail("one-short input budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_append(rejected).unwrap())
}

///|
test "bounded append admits nested input values incrementally" {
  let schema = "{\"id\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
  let (_, exact, _) = bounded_append_fixture(
    left_schema=schema,
    right_schema=schema,
    left_rows="[{\"id\":[1,2]}]",
    right_rows="[{\"id\":[3,4]}]",
    input_nodes=8,
  )
  let execution = exact.unwrap()
  let mut complete = false
  let mut polls = 0
  while !complete && polls < 100 {
    polls += 1
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendComplete(_, ..) => complete = true
      BoundedAppendContinue(..) => ()
      _ => fail("exact nested input budget rejected")
    }
  }
  assert_true(complete)
  assert_true(polls > 10)
  assert_true(cleanup_bounded_append(execution).unwrap())
  let (_, short, _) = bounded_append_fixture(
    left_schema=schema,
    right_schema=schema,
    left_rows="[{\"id\":[1,2]}]",
    right_rows="[{\"id\":[3,4]}]",
    input_nodes=7,
  )
  let rejected = short.unwrap()
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_append(rejected, 1).unwrap() {
        BoundedAppendFailed(InputLimit, ..) => failed = true
        BoundedAppendContinue(..) => ()
        _ => fail("one-short nested input budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_append(rejected).unwrap())
}

///|
test "bounded append stops during nested input admission" {
  let schema = "{\"id\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
  let (control, started, inputs) = bounded_append_fixture(
    left_schema=schema,
    right_schema=schema,
    left_rows="[{\"id\":[1,2]}]",
    right_rows="[{\"id\":[3,4]}]",
  )
  let execution = started.unwrap()
  for _ in 0..<2 {
    assert_true(
      advance_bounded_append(execution, 1).unwrap() is BoundedAppendContinue(..),
    )
  }
  let scan = bounded_append_state(execution).input_scan
  assert_true(scan.frames.length() > 0)
  assert_true(scan.workspace.live >= scan.frames.length())
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_append(execution, 1).unwrap() is BoundedAppendStopped(_),
  )
  assert_true(cleanup_bounded_append(execution).unwrap())
  assert_eq(scan.frames.length(), 0)
  assert_eq(scan.workspace.live, 0)
  assert_false(cleanup_bounded_append(execution).unwrap())
  assert_eq(scan.workspace.live, 0)
  assert_true(producer_read_available(inputs[0]))
  assert_true(producer_read_available(inputs[1]))
}

///|
test "bounded append drops text and vector scan frames after cancellation" {
  let text_schema = "{\"id\":{\"type\":\"string\",\"nullable\":false}}"
  let object_schema = "{\"id\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}}"
  let vector_schema = "{\"id\":{\"type\":\"vector\",\"nullable\":false,\"dimensions\":2}}"
  for
    (schema, rows) in [
      (text_schema, "[{\"id\":{\"literal\":\"long value\"}}]"),
      (object_schema, "[{\"id\":{\"literal\":{\"x\":\"value\"}}}]"),
      (vector_schema, "[{\"id\":{\"literal\":[1,2]}}]"),
    ] {
    let (control, started, inputs) = bounded_append_fixture(
      left_schema=schema,
      right_schema=schema,
      left_rows=rows,
      right_rows=rows,
    )
    let execution = started.unwrap()
    for _ in 0..<2 {
      assert_true(
        advance_bounded_append(execution, 1).unwrap()
        is BoundedAppendContinue(..),
      )
    }
    let scan = bounded_append_state(execution).input_scan
    assert_true(scan.frames.length() > 0)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_append(execution, 1).unwrap()
      is BoundedAppendStopped(@bounded.Cancelled, ..),
    )
    assert_true(cleanup_bounded_append(execution).unwrap())
    assert_eq(scan.frames.length(), 0)
    assert_eq(scan.workspace.live, 0)
    assert_true(producer_read_available(inputs[0]))
    assert_true(producer_read_available(inputs[1]))
  }
}

///|
test "bounded append releases active scan frames on work failure" {
  let schema = "{\"id\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
  let (_, started, _) = bounded_append_fixture(
    max_work=2,
    left_schema=schema,
    right_schema=schema,
    left_rows="[{\"id\":[1,2]}]",
    right_rows="[{\"id\":[3,4]}]",
  )
  let execution = started.unwrap()
  for _ in 0..<2 {
    assert_true(
      advance_bounded_append(execution, 1).unwrap() is BoundedAppendContinue(..),
    )
  }
  let scan = bounded_append_state(execution).input_scan
  assert_true(scan.frames.length() > 0)
  assert_true(
    advance_bounded_append(execution, 1).unwrap()
    is BoundedAppendFailed(Rows(RowLimit), ..),
  )
  assert_true(cleanup_bounded_append(execution).unwrap())
  assert_eq(scan.frames.length(), 0)
  assert_eq(scan.workspace.live, 0)
}

///|
test "bounded append releases sibling scan frames on value failure" {
  let schema = "{\"id\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}}"
  let (_, started, inputs) = bounded_append_fixture(
    input_nodes=4,
    left_schema=schema,
    right_schema=schema,
    left_rows="[{\"id\":[[1,2],[3,4]]}]",
    right_rows="[{\"id\":[[5,6],[7,8]]}]",
  )
  let execution = started.unwrap()
  let scan = bounded_append_state(execution).input_scan
  let mut failed = false
  for _ in 0..<20 {
    if !failed {
      match advance_bounded_append(execution, 1).unwrap() {
        BoundedAppendContinue(..) => ()
        BoundedAppendFailed(InputLimit, ..) => failed = true
        _ => fail("nested value limit did not fail")
      }
    }
  }
  assert_true(failed)
  assert_true(scan.frames.length() > 0)
  assert_true(cleanup_bounded_append(execution).unwrap())
  assert_eq(scan.frames.length(), 0)
  assert_eq(scan.workspace.live, 0)
  assert_true(producer_read_available(inputs[0]))
  assert_true(producer_read_available(inputs[1]))
}

///|
test "binary input scan releases a frame after partial workspace failure" {
  let schema = "{\"id\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
  let (parent_control, started, inputs) = bounded_append_fixture(
    left_schema=schema,
    right_schema=schema,
    left_rows="[{\"id\":[1,2]}]",
    right_rows="[{\"id\":[3,4]}]",
  )
  let execution = started.unwrap()
  let limits = bounded_append_state(execution).input_scan.budget.limits
  let workspace = row_workspace(1)
  let control : ControlBudget = { remaining: 100, max_frames: 10, }
  let scan = binary_input_scan(inputs[0], inputs[1], limits, control, workspace).unwrap()
  assert_true(advance_binary_input_scan(scan) is Ok(false))
  assert_true(advance_binary_input_scan(scan) is Err(WorkspaceLimit))
  assert_eq(scan.frames.length(), 1)
  assert_eq(workspace.live, 1)
  cleanup_binary_input_scan(scan)
  assert_eq(scan.frames.length(), 0)
  assert_eq(workspace.live, 0)
  cleanup_binary_input_scan(scan)
  assert_eq(workspace.live, 0)
  assert_true(producer_read_available(inputs[0]))
  assert_true(producer_read_available(inputs[1]))
  assert_true(@bounded.request_cancel(parent_control))
  assert_true(
    advance_bounded_append(execution, 1).unwrap()
    is BoundedAppendStopped(@bounded.Cancelled, ..),
  )
  assert_true(cleanup_bounded_append(execution).unwrap())
}

///|
test "bounded append preserves order across quantum-one resumes" {
  let (_, started, _) = bounded_append_fixture()
  let execution = started.unwrap()
  let mut done = false
  let mut accepted : CompletedOutput? = None
  let mut polls = 0
  let mut progress = 0L
  let mut work = 0L
  while !done && polls < 100 {
    polls += 1
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(progress=next_progress, work=next_work) => {
        assert_true(next_work - work <= 1L)
        progress = next_progress
        work = next_work
      }
      BoundedAppendComplete(output, progress=next_progress, work=next_work) => {
        assert_true(next_work - work <= 1L)
        progress = next_progress
        work = next_work
        assert_eq(completed_row_count(output), 3)
        assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
        assert_true(completed_cell(output, 1, 0) is Some(Number(2)))
        assert_true(completed_cell(output, 2, 0) is Some(Number(3)))
        accepted = Some(output)
        done = true
      }
      _ => fail("bounded append did not complete")
    }
  }
  assert_true(done)
  assert_eq(progress, 3L)
  assert_true(work > 3L)
  assert_true(cleanup_bounded_append(execution).unwrap())
  guard accepted is Some(output) else { fail("append output was not accepted") }
  assert_eq(completed_row_count(output), 3)
  assert_true(completed_cell(output, 2, 0) is Some(Number(3)))
}

///|
test "bounded append admits independently calculated work and workspace" {
  // One name costs 1 + 2 control units. Three rows cost two units each.
  // Input admission adds 17 row, field and text transitions: 26 total.
  let (_, exact, _) = bounded_append_fixture(max_work=26, max_entries=10)
  let execution = exact.unwrap()
  let mut done = false
  while !done {
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendComplete(_, ..) => done = true
      _ => fail("exact append resource boundary failed")
    }
  }
  assert_true(cleanup_bounded_append(execution).unwrap())
  let (_, short_work, _) = bounded_append_fixture(max_work=25, max_entries=10)
  let rejected_work = short_work.unwrap()
  let mut failed_work = false
  while !failed_work {
    match advance_bounded_append(rejected_work, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendFailed(Rows(RowLimit), ..) => failed_work = true
      _ => fail("one-short append work had another outcome")
    }
  }
  assert_true(cleanup_bounded_append(rejected_work).unwrap())
  let (_, short_space, _) = bounded_append_fixture(max_work=26, max_entries=9)
  let rejected_space = short_space.unwrap()
  let mut failed_space = false
  while !failed_space {
    match advance_bounded_append(rejected_space, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendFailed(Rows(RowLimit), ..) => failed_space = true
      _ => fail("one-short append workspace had another outcome")
    }
  }
  assert_true(cleanup_bounded_append(rejected_space).unwrap())
}

///|
test "bounded append stops after row progress and discards partial output" {
  let (control, started, _) = bounded_append_fixture()
  let execution = started.unwrap()
  let mut progressed = false
  while !progressed {
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(progress~, ..) => progressed = progress > 0L
      _ => fail("append completed before cancellation")
    }
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_append(execution, 1).unwrap() is BoundedAppendStopped(_),
  )
  assert_true(cleanup_bounded_append(execution).unwrap())
}

///|
test "bounded append aligns nullable fields in authored left order" {
  let (_, started, _) = bounded_append_fixture(
    left_schema="{\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":true}}",
    right_schema="{\"tag\":{\"type\":\"string\",\"nullable\":true},\"id\":{\"type\":\"number\",\"nullable\":false}}",
    left_rows="[{\"id\":1,\"tag\":null}]",
    right_rows="[{\"tag\":{\"literal\":\"right\"},\"id\":2}]",
  )
  let execution = started.unwrap()
  let mut done = false
  while !done {
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendComplete(output, ..) => {
        assert_eq(completed_column_name(output, 0), Some("id"))
        assert_eq(completed_column_name(output, 1), Some("tag"))
        assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
        assert_true(completed_cell(output, 0, 1) is Some(Null))
        assert_true(completed_cell(output, 1, 0) is Some(Number(2)))
        assert_true(completed_cell(output, 1, 1) is Some(Text("right")))
        done = true
      }
      _ => fail("aligned append did not complete")
    }
  }
  assert_true(cleanup_bounded_append(execution).unwrap())
}
