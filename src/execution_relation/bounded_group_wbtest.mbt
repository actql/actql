///|
fn bounded_group_fixture(
  rows : String,
  max_work? : Int = 1000,
  max_entries? : Int = 1000,
) -> (@bounded.Control, BoundedGroupExecution, CompletedOutput) raise {
  let (control, execution, source) = bounded_group_start(
    rows,
    "{\"m\":{\"fn\":\"max\",\"field\":\"k\"}}",
    false,
    max_work~,
    max_entries~,
  )
  (control, execution.unwrap(), source)
}

///|
fn bounded_group_start(
  rows : String,
  aggregates : String,
  fragment : Bool,
  max_work? : Int = 1000,
  max_entries? : Int = 1000,
) -> (
  @bounded.Control,
  Result[BoundedGroupExecution, BoundedGroupIssue],
  CompletedOutput,
) raise {
  bounded_relation_start(
    "{\"k\":{\"type\":\"number\",\"nullable\":false}}",
    rows,
    "\"group\":{\"by\":[\"k\"],\"aggregates\":" + aggregates + "}",
    "group_0",
    fragment,
    max_work~,
    max_entries~,
  )
}

///|
fn bounded_relation_start(
  schema : String,
  rows : String,
  operation : String,
  retained : String,
  fragment : Bool,
  max_work? : Int = 1000,
  max_entries? : Int = 1000,
  constrain? : (GeneratedSequence) -> GeneratedSequence = generated => generated,
) -> (
  @bounded.Control,
  Result[BoundedGroupExecution, BoundedGroupIssue],
  CompletedOutput,
) raise {
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    rows +
    "},\"as\":\"seed\"}]",
  )
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
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"seed\"," + operation + "}]"),
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
  let sequence = prepared_sequence(receiver)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    if fragment {
      [sequence_fragment_context(sequence, 0, 10L)]
    } else {
      []
    },
    [retained],
    100000,
    10000,
  ).unwrap()
  let generated = constrain(generated)
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_group_execution(
    control,
    generated,
    read,
    10,
    run_limits().input_values,
    run_limits().output_values,
    run_limits().input_values,
    max_work,
    100,
    max_entries,
    10000,
  )
  (control, execution, source)
}

///|
fn drive_bounded_group(execution : BoundedGroupExecution) -> BoundedGroupPoll {
  for _ in 0..<10000 {
    match advance_bounded_group_execution(execution, 1) {
      Ok(BoundedGroupContinue(..)) => ()
      Ok(poll) => return poll
      Err(_) =>
        return BoundedGroupFailed(InvalidExecution, progress=0L, work=0L)
    }
  }
  BoundedGroupFailed(InvalidExecution, progress=0L, work=0L)
}

///|
test "bounded group admits exact work and rejects one unit short" {
  // One input row charge (1); names: input k (2), key k (2), aggregate m
  // (2) and its field k (2), output k and m (4); stable order: one term,
  // one row check and one index (3); one group boundary (1); one group (1);
  // one max contributor (1); no comparison; two output cells (2).
  let exact_work = 21
  let (_, exact, source) = bounded_group_fixture(
    "[{\"k\":1}]",
    max_work=exact_work,
  )
  match drive_bounded_group(exact) {
    BoundedGroupComplete(output, ..) =>
      assert_eq(completed_row_count(output), 1)
    _ => fail("exact group work rejected")
  }
  assert_true(cleanup_bounded_group_execution(exact).unwrap())
  let (_, short, _) = bounded_group_fixture(
    "[{\"k\":1}]",
    max_work=exact_work - 1,
  )
  match drive_bounded_group(short) {
    BoundedGroupFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short group work accepted")
  }
  assert_true(cleanup_bounded_group_execution(short).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded group stops after positive work without publishing" {
  let (control, execution, source) = bounded_group_fixture(
    "[{\"k\":3},{\"k\":1},{\"k\":3},{\"k\":2}]",
  )
  for _ in 0..<5 {
    assert_true(
      advance_bounded_group_execution(execution, 1)
      is Ok(BoundedGroupContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_group_execution(execution, 1)
    is Ok(BoundedGroupStopped(_, ..)),
  )
  assert_true(cleanup_bounded_group_execution(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
/// Total work across quantum-one advances, or None on any non-completion or
/// any advance that pays more than its quantum. Poll work is cumulative.
fn bounded_group_total_work(execution : BoundedGroupExecution) -> Int64? {
  let mut previous = 0L
  for _ in 0..<10000 {
    match advance_bounded_group_execution(execution, 1) {
      Ok(BoundedGroupContinue(work~, ..)) => {
        if work - previous > 1L {
          return None
        }
        previous = work
      }
      Ok(BoundedGroupComplete(_, work~, ..)) =>
        return if work - previous > 1L { None } else { Some(work) }
      _ => return None
    }
  }
  None
}

///|
let bounded_group_filtered : String = "{\"m\":{\"fn\":\"max\",\"expr\":\"10 / k\",\"filter\":\"k > 0\"}}"

///|
test "bounded group evaluates filtered expression aggregates within exact work" {
  // Shared parts (21): one input row charge (1); names: input k, key k,
  // aggregate m, output k and m (10); stable order (3); one group boundary
  // and one group (2); contributor row entry (1); filter snapshot entry and
  // name byte (2); two output cells (2). Each `field op literal` frame costs
  // 7. A filtered-out row adds only its filter frame (28). An accepted row
  // adds both frames, its argument snapshot (2), one ordered index, one
  // permutation copy and one max contributor (3): 21 + 14 + 5 = 40.
  for case in [("[{\"k\":0}]", 28), ("[{\"k\":2}]", 40)] {
    let (rows, exact_work) = case
    let (_, measured, source) = bounded_group_start(
      rows, bounded_group_filtered, true,
    )
    let measured = measured.unwrap()
    // Every quantum-one advance pays at most one kernel step.
    assert_true(bounded_group_total_work(measured) is Some(_))
    assert_true(cleanup_bounded_group_execution(measured).unwrap())
    let (_, exact, _) = bounded_group_start(
      rows,
      bounded_group_filtered,
      true,
      max_work=exact_work,
    )
    let exact = exact.unwrap()
    match drive_bounded_group(exact) {
      BoundedGroupComplete(output, ..) =>
        assert_eq(completed_row_count(output), 1)
      _ => fail("exact filtered group work rejected")
    }
    assert_true(cleanup_bounded_group_execution(exact).unwrap())
    let (_, short, _) = bounded_group_start(
      rows,
      bounded_group_filtered,
      true,
      max_work=exact_work - 1,
    )
    let short = short.unwrap()
    match drive_bounded_group(short) {
      BoundedGroupFailed(Rows(RowLimit), ..) => ()
      _ => fail("one-short filtered group work accepted")
    }
    assert_true(cleanup_bounded_group_execution(short).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
test "bounded group stops a filtered aggregate after positive work" {
  let (control, execution, source) = bounded_group_start(
    "[{\"k\":3},{\"k\":1},{\"k\":3},{\"k\":2}]", bounded_group_filtered, true,
  )
  let execution = execution.unwrap()
  for _ in 0..<30 {
    assert_true(
      advance_bounded_group_execution(execution, 1)
      is Ok(BoundedGroupContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_group_execution(execution, 1)
    is Ok(BoundedGroupStopped(_, ..)),
  )
  assert_true(cleanup_bounded_group_execution(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
let bounded_pivot_schema : String = "{\"id\":{\"type\":\"number\",\"nullable\":false},\"status\":{\"type\":\"string\",\"nullable\":true},\"amount\":{\"type\":\"number\",\"nullable\":true}}"

///|
let bounded_pivot_max : String = "\"pivot\":{\"index\":[\"id\"],\"column\":\"status\",\"values\":[\"open\"],\"value\":\"amount\",\"aggregate\":\"max\"}"

///|
test "bounded pivot admits exact work and rejects one unit short" {
  // One input row charge (1); input names id, status and amount (17);
  // index and axis metadata (2); index id, pivot column status and value
  // amount (17); axis open (4); output id and open (8); stable order (3);
  // one group boundary (1); identity group order (1); one group row (1);
  // one max member without comparison (1); two output cells (2).
  let exact_work = 58
  let rows = "[{\"id\":1,\"status\":\"open\",\"amount\":5}]"
  let (_, measured, source) = bounded_relation_start(
    bounded_pivot_schema, rows, bounded_pivot_max, "pivot_0", false,
  )
  let measured = measured.unwrap()
  assert_true(bounded_group_total_work(measured) is Some(_))
  assert_true(cleanup_bounded_group_execution(measured).unwrap())
  let (_, exact, _) = bounded_relation_start(
    bounded_pivot_schema,
    rows,
    bounded_pivot_max,
    "pivot_0",
    false,
    max_work=exact_work,
  )
  let exact = exact.unwrap()
  match drive_bounded_group(exact) {
    BoundedGroupComplete(output, ..) =>
      assert_eq(completed_row_count(output), 1)
    _ => fail("exact pivot work rejected")
  }
  assert_true(cleanup_bounded_group_execution(exact).unwrap())
  let (_, short, _) = bounded_relation_start(
    bounded_pivot_schema,
    rows,
    bounded_pivot_max,
    "pivot_0",
    false,
    max_work=exact_work - 1,
  )
  let short = short.unwrap()
  match drive_bounded_group(short) {
    BoundedGroupFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short pivot work accepted")
  }
  assert_true(cleanup_bounded_group_execution(short).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded pivot stops after positive work without publishing" {
  let (control, execution, source) = bounded_relation_start(
    bounded_pivot_schema, "[{\"id\":2,\"status\":\"open\",\"amount\":5},{\"id\":1,\"status\":\"open\",\"amount\":7},{\"id\":2,\"status\":\"open\",\"amount\":9}]",
    bounded_pivot_max, "pivot_0", false,
  )
  let execution = execution.unwrap()
  for _ in 0..<30 {
    assert_true(
      advance_bounded_group_execution(execution, 1)
      is Ok(BoundedGroupContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_group_execution(execution, 1)
    is Ok(BoundedGroupStopped(_, ..)),
  )
  assert_true(cleanup_bounded_group_execution(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded group enforces the selected array item ceiling" {
  let aggregate = "{\"items\":{\"fn\":\"array_agg\",\"field\":\"k\",\"max_items\":5,\"order_by\":[{\"k\":\"asc\"}]}}"
  let rows = "[{\"k\":1},{\"k\":1}]"
  let limited = (maximum : Int64) => {
    (generated : GeneratedSequence) => {
      constrain_generated_aggregate_output(
        generated,
        0,
        "items",
        ArrayItems,
        maximum,
      ).unwrap()
    }
  }
  let (_, unconstrained, _) = bounded_group_start(rows, aggregate, false)
  let unconstrained = unconstrained.unwrap()
  // The authored max_items applies without a selected ceiling.
  assert_true(drive_bounded_group(unconstrained) is BoundedGroupComplete(_, ..))
  assert_true(cleanup_bounded_group_execution(unconstrained).unwrap())
  let (_, fits, _) = bounded_relation_start(
    "{\"k\":{\"type\":\"number\",\"nullable\":false}}",
    rows,
    "\"group\":{\"by\":[\"k\"],\"aggregates\":" + aggregate + "}",
    "group_0",
    false,
    constrain=limited(2L),
  )
  let fits = fits.unwrap()
  assert_true(drive_bounded_group(fits) is BoundedGroupComplete(_, ..))
  assert_true(cleanup_bounded_group_execution(fits).unwrap())
  let (_, exceeds, _) = bounded_relation_start(
    "{\"k\":{\"type\":\"number\",\"nullable\":false}}",
    rows,
    "\"group\":{\"by\":[\"k\"],\"aggregates\":" + aggregate + "}",
    "group_0",
    false,
    constrain=limited(1L),
  )
  let exceeds = exceeds.unwrap()
  assert_true(
    drive_bounded_group(exceeds) is BoundedGroupFailed(Rows(RowLimit), ..),
  )
  assert_true(cleanup_bounded_group_execution(exceeds).unwrap())
}
