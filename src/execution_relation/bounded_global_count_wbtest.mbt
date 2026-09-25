///|
fn bounded_global_count_fixture(
  rows : String,
  keyed? : Bool = false,
  unused_payload? : Bool = false,
  unused_text? : Bool = false,
  input_values? : ValueLimits = run_limits().input_values,
  max_work? : Int = 100,
  max_entries? : Int = 100,
) -> (@bounded.Control, BoundedGlobalCountExecution, CompletedOutput) raise {
  let schema = if unused_payload {
    "{\"id\":{\"type\":\"number\",\"nullable\":true},\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
  } else if unused_text {
    "{\"id\":{\"type\":\"number\",\"nullable\":true},\"payload\":{\"type\":\"string\",\"nullable\":false}}"
  } else {
    "{\"id\":{\"type\":\"number\",\"nullable\":true}}"
  }
  let source_text = "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    rows +
    "},\"as\":\"seed\"}]"
  let source_owner = bound_pipeline(source_text)
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(source_owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let group_text = if keyed {
    "[{\"from\":\"seed\",\"group\":{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"},\"present\":{\"fn\":\"count\",\"field\":\"id\"}}}}]"
  } else {
    "[{\"from\":\"seed\",\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"},\"present\":{\"fn\":\"count\",\"field\":\"id\"}}}}]"
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(group_text),
    [("seed", @pipeline.ProducedInput(producer))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
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
      max_work: 100000,
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
    ["group_0"],
    100000,
    10000,
  ).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_global_count(
    control,
    generated,
    read,
    if keyed {
      3
    } else {
      1
    },
    input_values,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, execution, source)
}

///|
test "bounded global count reads null fields once at quantum one" {
  let (_, execution, source) = bounded_global_count_fixture(
    "[{\"id\":null},{\"id\":1},{\"id\":1}]",
  )
  let mut complete : CompletedOutput? = None
  let mut polls = 0
  let mut previous_work = 0L
  while complete is None && polls < 100 {
    polls += 1
    match advance_bounded_global_count(execution, 1).unwrap() {
      BoundedGlobalCountContinue(work=next, ..) => {
        assert_true(next - previous_work <= 1L)
        previous_work = next
      }
      BoundedGlobalCountComplete(output, work=next, ..) => {
        assert_true(next - previous_work <= 1L)
        previous_work = next
        complete = Some(output)
      }
      _ => fail("bounded global count did not complete")
    }
  }
  guard complete is Some(output) else { fail("global count did not progress") }
  assert_true(polls > 3)
  assert_eq(completed_row_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(completed_cell(output, 0, 1) is Some(Number(2)))
  assert_true(cleanup_bounded_global_count(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded global count stops after work without publishing" {
  let (control, execution, source) = bounded_global_count_fixture(
    "[{\"id\":null},{\"id\":1},{\"id\":1}]",
  )
  assert_true(
    advance_bounded_global_count(execution, 1).unwrap()
    is BoundedGlobalCountContinue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_global_count(execution, 1).unwrap()
    is BoundedGlobalCountStopped(_, ..),
  )
  assert_true(cleanup_bounded_global_count(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded keyed count sorts and groups at quantum one" {
  let (_, execution, source) = bounded_global_count_fixture(
    "[{\"id\":1},{\"id\":null},{\"id\":1}]",
    keyed=true,
    max_work=1000,
  )
  let mut complete : CompletedOutput? = None
  let mut polls = 0
  let mut previous_work = 0L
  while complete is None && polls < 1000 {
    polls += 1
    match advance_bounded_global_count(execution, 1).unwrap() {
      BoundedGlobalCountContinue(work=next, ..) => {
        assert_true(next - previous_work <= 1L)
        previous_work = next
      }
      BoundedGlobalCountComplete(output, work=next, ..) => {
        assert_true(next - previous_work <= 1L)
        previous_work = next
        complete = Some(output)
      }
      _ => fail("bounded keyed count did not complete")
    }
  }
  guard complete is Some(output) else { fail("keyed count did not progress") }
  assert_eq(previous_work, 70L)
  assert_true(polls > 20)
  assert_eq(completed_row_count(output), 2)
  assert_true(completed_cell(output, 0, 0) is Some(Null))
  assert_true(completed_cell(output, 0, 1) is Some(Number(1)))
  assert_true(completed_cell(output, 0, 2) is Some(Number(0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(1)))
  assert_true(completed_cell(output, 1, 1) is Some(Number(2)))
  assert_true(completed_cell(output, 1, 2) is Some(Number(2)))
  assert_true(cleanup_bounded_global_count(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded keyed count cancels during key ordering" {
  let (control, execution, source) = bounded_global_count_fixture(
    "[{\"id\":1},{\"id\":null},{\"id\":1}]",
    keyed=true,
    max_work=1000,
  )
  for _ in 0..<30 {
    assert_true(
      advance_bounded_global_count(execution, 1).unwrap()
      is BoundedGlobalCountContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_global_count(execution, 1).unwrap()
    is BoundedGlobalCountStopped(_, ..),
  )
  assert_true(cleanup_bounded_global_count(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded keyed count admits exact work and workspace limits" {
  let rows = "[{\"id\":1},{\"id\":null},{\"id\":1}]"
  // One key, two counters and three output fields occupy 12 fixed slots.
  // The three-row sort adds six slots; each output row reuses three slots.
  let (_, exact, source) = bounded_global_count_fixture(
    rows,
    keyed=true,
    max_work=68,
    max_entries=18,
  )
  let mut completed = false
  for _ in 0..<1000 {
    if !completed {
      match advance_bounded_global_count(exact, 1).unwrap() {
        BoundedGlobalCountContinue(..) => ()
        BoundedGlobalCountComplete(output, ..) => {
          assert_eq(completed_row_count(output), 2)
          completed = true
        }
        _ => fail("exact keyed count budget rejected")
      }
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_global_count(exact).unwrap())
  assert_true(completed_output_available(source))

  for (work, entries) in [(67, 18), (70, 17)] {
    let (_, one_short, source) = bounded_global_count_fixture(
      rows,
      keyed=true,
      max_work=work,
      max_entries=entries,
    )
    let mut rejected = false
    for _ in 0..<1000 {
      if !rejected {
        match advance_bounded_global_count(one_short, 1).unwrap() {
          BoundedGlobalCountContinue(..) => ()
          BoundedGlobalCountFailed(Rows(RowLimit), ..) => rejected = true
          _ =>
            fail(
              "one-short keyed count budget accepted for work " +
              work.to_string() +
              " and entries " +
              entries.to_string(),
            )
        }
      }
    }
    assert_true(rejected)
    assert_true(cleanup_bounded_global_count(one_short).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
fn unused_count_payload_rows(count : Int) -> String {
  let mut payload = "["
  for index in 0..<count {
    if index > 0 {
      payload = payload + ","
    }
    payload = payload + "1"
  }
  "[{\"id\":1,\"payload\":" + payload + "]}]"
}

///|
fn unused_count_text_rows(count : Int) -> String {
  let mut payload = ""
  for _ in 0..<count {
    payload = payload + "aaaaaaaaaaaaaaaa"
  }
  "[{\"id\":1,\"payload\":\"" + payload + "\"}]"
}

///|
test "bounded count stops inside an unused nested input value" {
  let (control, execution, source) = bounded_global_count_fixture(
    unused_count_payload_rows(256),
    unused_payload=true,
    max_work=1000,
    max_entries=1000,
  )
  let mut previous_work = 0L
  for _ in 0..<100 {
    match advance_bounded_global_count(execution, 1).unwrap() {
      BoundedGlobalCountContinue(work~, ..) => {
        assert_eq(work - previous_work, 1L)
        previous_work = work
      }
      _ => fail("nested input finished before cancellation")
    }
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_global_count(execution, 1).unwrap()
    is BoundedGlobalCountStopped(_, ..),
  )
  assert_true(cleanup_bounded_global_count(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded count preserves exact nested input value charges" {
  // One row, id and array nodes, and 256 element nodes: 259 nodes.
  // The id and payload names add 2 + 7 UTF-8 bytes, hence 268 work.
  let exact : ValueLimits = {
    ..run_limits().input_values,
    max_nodes: 259,
    max_text_bytes: 9,
    max_work: 268,
  }
  for
    (nodes, work, should_complete) in [
      (259, 268, true),
      (258, 268, false),
      (259, 267, false),
    ] {
    let input_values : ValueLimits = {
      ..exact,
      max_nodes: nodes,
      max_work: work,
    }
    let (_, execution, source) = bounded_global_count_fixture(
      unused_count_payload_rows(256),
      unused_payload=true,
      input_values~,
      max_work=1000,
      max_entries=1000,
    )
    let mut terminal = false
    for _ in 0..<1000 {
      if !terminal {
        match advance_bounded_global_count(execution, 1).unwrap() {
          BoundedGlobalCountContinue(..) => ()
          BoundedGlobalCountComplete(output, ..) => {
            assert_true(should_complete)
            assert_eq(completed_row_count(output), 1)
            terminal = true
          }
          BoundedGlobalCountFailed(InputLimit, ..) => {
            assert_false(should_complete)
            terminal = true
          }
          _ => fail("nested count ended with another result")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_global_count(execution).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
test "bounded count steps a long unused text cell and preserves its budget" {
  let rows = unused_count_text_rows(256)
  let exact : ValueLimits = {
    ..run_limits().input_values,
    max_nodes: 3,
    max_text_bytes: 4105,
    max_work: 4108,
  }
  for
    (bytes, work, should_complete) in [
      (4105, 4108, true),
      (4104, 4108, false),
      (4105, 4107, false),
    ] {
    let input_values : ValueLimits = {
      ..exact,
      max_text_bytes: bytes,
      max_work: work,
    }
    let (_, execution, source) = bounded_global_count_fixture(
      rows,
      unused_text=true,
      input_values~,
      max_work=1000,
      max_entries=100,
    )
    let mut terminal = false
    let mut previous_work = 0L
    for _ in 0..<300 {
      if !terminal {
        match advance_bounded_global_count(execution, 1).unwrap() {
          BoundedGlobalCountContinue(work~, ..) => {
            assert_true(work - previous_work <= 1L)
            previous_work = work
          }
          BoundedGlobalCountComplete(output, work~, ..) => {
            assert_true(should_complete)
            assert_true(work - previous_work <= 1L)
            assert_eq(completed_row_count(output), 1)
            terminal = true
          }
          BoundedGlobalCountFailed(InputLimit, ..) => {
            assert_false(should_complete)
            terminal = true
          }
          _ => fail("long text count ended with another result")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_global_count(execution).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
test "bounded count stops while measuring a long unused text cell" {
  let (control, execution, source) = bounded_global_count_fixture(
    unused_count_text_rows(256),
    unused_text=true,
    max_work=1000,
  )
  let mut previous_work = 0L
  for _ in 0..<35 {
    match advance_bounded_global_count(execution, 1).unwrap() {
      BoundedGlobalCountContinue(work~, ..) => {
        assert_eq(work - previous_work, 1L)
        previous_work = work
      }
      _ => fail("long text input finished before cancellation")
    }
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_global_count(execution, 1).unwrap()
    is BoundedGlobalCountStopped(_, ..),
  )
  assert_true(cleanup_bounded_global_count(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded global count admits exact work and workspace limits" {
  // Input name (3), aggregate names and field (12), output names (8),
  // three input rows (3), three count rows (9), and output cells (2).
  let rows = "[{\"id\":null},{\"id\":1},{\"id\":1}]"
  let (_, exact, _) = bounded_global_count_fixture(
    rows,
    max_work=37,
    max_entries=12,
  )
  let mut completed = false
  for _ in 0..<100 {
    if !completed {
      match advance_bounded_global_count(exact, 1).unwrap() {
        BoundedGlobalCountContinue(..) => ()
        BoundedGlobalCountComplete(output, ..) => {
          assert_eq(completed_row_count(output), 1)
          completed = true
        }
        _ => fail("exact global count budget rejected")
      }
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_global_count(exact).unwrap())

  for (work, entries) in [(36, 12), (37, 11)] {
    let (_, one_short, source) = bounded_global_count_fixture(
      rows,
      max_work=work,
      max_entries=entries,
    )
    let mut rejected = false
    for _ in 0..<100 {
      if !rejected {
        match advance_bounded_global_count(one_short, 1).unwrap() {
          BoundedGlobalCountContinue(..) => ()
          BoundedGlobalCountFailed(Rows(RowLimit), ..) => rejected = true
          _ => fail("one-short global count budget accepted")
        }
      }
    }
    assert_true(rejected)
    assert_true(cleanup_bounded_global_count(one_short).unwrap())
    assert_true(completed_output_available(source))
  }
}
