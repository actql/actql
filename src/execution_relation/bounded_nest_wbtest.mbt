///|
fn bounded_nest_fixture(
  nest? : String = "\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}],\"max_items\":3",
  grouped_bytes? : Int64 = 10000L,
  attached_bytes? : Int64 = 10000L,
  max_work? : Int = 1000,
  max_entries? : Int = 100,
  left_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":true}}",
  right_schema? : String = "{\"key\":{\"type\":\"number\",\"nullable\":true},\"value\":{\"type\":\"number\",\"nullable\":true}}",
  left_rows? : String = "[{\"id\":1,\"key\":1},{\"id\":2,\"key\":1},{\"id\":3,\"key\":null},{\"id\":4,\"key\":2}]",
  right_rows? : String = "[{\"key\":1,\"value\":null},{\"key\":1,\"value\":10},{\"key\":null,\"value\":30}]",
  output_values? : ValueLimits = run_limits().output_values,
  input_nodes? : Int = 1000,
  max_rows? : Int = 10,
) -> (
  @bounded.Control,
  Result[BoundedNestExecution, BoundedNestIssue],
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
    input_cursor("[{\"from\":\"l\",\"nest\":{\"with\":\"r\"," + nest + "}}]"),
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
    ["nest_0"],
    10000,
    1000,
  ).unwrap()
  let generated = constrain_generated_aggregate_output(
    generated,
    0,
    "items",
    NestGroupedBytes,
    grouped_bytes,
  ).unwrap()
  let generated = constrain_generated_aggregate_output(
    generated,
    0,
    "items",
    NestAttachedBytes,
    attached_bytes,
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
  let execution = start_bounded_nest(
    control,
    generated,
    left,
    right,
    max_rows,
    {
      max_nodes: input_nodes,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 10000,
    },
    output_values,
    max_work,
    100,
    max_entries,
    1000,
  )
  (control, execution, [left, right])
}

///|
fn drive_bounded_nest(execution : BoundedNestExecution) -> BoundedNestPoll {
  for _ in 0..<100000 {
    match advance_bounded_nest(execution, 1) {
      Ok(BoundedNestContinue(..)) => ()
      Ok(poll) => return poll
      Err(_) => return BoundedNestFailed(InvalidExecution, progress=0L, work=0L)
    }
  }
  BoundedNestFailed(InvalidExecution, progress=0L, work=0L)
}

///|
fn bounded_nest_item_counts(output : CompletedOutput) -> Array[Int] {
  let column = Array::makei(completed_column_count(output), index => {
      completed_column_name(output, index).unwrap()
    })
    .search("items")
    .unwrap()
  Array::makei(completed_row_count(output), row => {
    match completed_cell(output, row, column) {
      Some(Captured(@admitted.Array(items))) => @admitted.element_count(items)
      _ => -1
    }
  })
}

///|
test "bounded nest groups parents in order and never matches NULL keys" {
  let (_, started, reads) = bounded_nest_fixture(
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  match drive_bounded_nest(execution) {
    BoundedNestComplete(output, ..) =>
      assert_eq(bounded_nest_item_counts(output), [2, 2, 0, 0])
    _ => fail("bounded nest did not complete")
  }
  assert_true(cleanup_bounded_nest(execution).unwrap())
  assert_true(reads.all(read => producer_read_available(read)))
}

///|
test "bounded nest enforces the per-parent item limit" {
  let (_, started, _) = bounded_nest_fixture(
    nest="\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}],\"max_items\":1",
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  assert_true(
    drive_bounded_nest(execution)
    is BoundedNestFailed(Rows(NestItemLimit(0)), ..),
  )
  assert_true(cleanup_bounded_nest(execution).unwrap())
}

///|
test "bounded nest enforces the grouped byte envelope" {
  let (_, started, _) = bounded_nest_fixture(
    grouped_bytes=1L,
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  assert_true(
    drive_bounded_nest(execution)
    is BoundedNestFailed(Rows(NestEnvelope(GroupedBytes)), ..),
  )
  assert_true(cleanup_bounded_nest(execution).unwrap())
}

///|
test "bounded nest stops after positive work without publishing" {
  let (control, started, reads) = bounded_nest_fixture()
  let execution = started.unwrap()
  for _ in 0..<40 {
    assert_true(
      advance_bounded_nest(execution, 1).unwrap() is BoundedNestContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_nest(execution, 1).unwrap() is BoundedNestStopped(_, ..),
  )
  assert_true(cleanup_bounded_nest(execution).unwrap())
  assert_true(reads.all(read => producer_read_available(read)))
}

///|
test "bounded nest admits exact work and rejects one unit short" {
  // Input admission, per row 1 and per field 1 + name bytes + 1 value
  // (10 parent, 13 child); key `key`: entry 1 and name scans over parent
  // `id` (6) and `key` (7) and child `key` (7): 21; field `value`: entry 1
  // and scans over `key` (9) and `value` (11): 21; output names and parent
  // resolution: `id` 2 + 5, `key` 3 + 13, `items` 5: 28; child seed 1 and
  // sort 3; parent entry 1; one search and one match comparison 2; row
  // charge for one item, three names and the row 5; item entry 1; nested
  // measurement: array 1, object 1, key `amount` 6, number 1: 9. Total 115.
  let exact_work = 115
  let left = "[{\"id\":1,\"key\":1}]"
  let right = "[{\"key\":1,\"value\":5}]"
  let (_, exact, _) = bounded_nest_fixture(
    left_rows=left,
    right_rows=right,
    max_work=exact_work,
  )
  let exact = exact.unwrap()
  match drive_bounded_nest(exact) {
    BoundedNestComplete(output, ..) =>
      assert_eq(bounded_nest_item_counts(output), [1])
    _ => fail("exact nest work rejected")
  }
  assert_true(cleanup_bounded_nest(exact).unwrap())
  let (_, short, _) = bounded_nest_fixture(
    left_rows=left,
    right_rows=right,
    max_work=exact_work - 1,
  )
  let short = short.unwrap()
  match drive_bounded_nest(short) {
    BoundedNestFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short nest work accepted")
  }
  assert_true(cleanup_bounded_nest(short).unwrap())
}

///|
fn bounded_nest_released(execution : BoundedNestExecution) -> Bool {
  let state = execution.state
  state.nested is Null &&
  state.builder is None &&
  state.measure is None &&
  state.recheck is None &&
  state.entries.length() == 0 &&
  state.matches.length() == 0 &&
  state.output_row.length() == 0 &&
  state.output_pending is None &&
  state.output_measure is None &&
  !state.output_row_open &&
  state.workspace.live == 0
}

///|
/// Advance with quantum 1 until the state enters `phase`, then cancel.
fn bounded_nest_cancel_in(
  execution : BoundedNestExecution,
  control : @bounded.Control,
  phase : BoundedNestPhase,
  skip? : Int = 0,
) -> Bool {
  let mut seen = 0
  for _ in 0..<100000 {
    if nest_phase_id(execution.state.phase) == nest_phase_id(phase) {
      if seen == skip {
        break
      }
      seen += 1
    }
    match advance_bounded_nest(execution, 1) {
      Ok(BoundedNestContinue(..)) => ()
      _ => return false
    }
  }
  @bounded.request_cancel(control) |> ignore
  advance_bounded_nest(execution, 1) is Ok(BoundedNestStopped(_, ..))
}

///|
test "bounded nest cleanup releases the nested value at every phase" {
  for phase in [BuildItem, MeasureNested, CheckAttached, BuildCell] {
    let (control, started, reads) = bounded_nest_fixture(
      max_work=100000,
      max_entries=1000,
    )
    let execution = started.unwrap()
    if !bounded_nest_cancel_in(execution, control, phase, skip=1) {
      fail("phase " + nest_phase_id(phase).to_string())
    }
    assert_true(cleanup_bounded_nest(execution).unwrap())
    assert_true(bounded_nest_released(execution))
    assert_true(reads.all(read => producer_read_available(read)))
  }
}

///|
test "bounded nest cleanup releases the nested value after failures" {
  // Grouped and attached envelope failures stop after the nested value exists.
  for limits in [(1L, 10000L), (10000L, 1L)] {
    let (_, started, _) = bounded_nest_fixture(
      grouped_bytes=limits.0,
      attached_bytes=limits.1,
      max_work=100000,
      max_entries=1000,
    )
    let execution = started.unwrap()
    assert_true(drive_bounded_nest(execution) is BoundedNestFailed(_, ..))
    assert_true(cleanup_bounded_nest(execution).unwrap())
    assert_true(bounded_nest_released(execution))
  }
  // The item limit fails after the first parent's nested value was built.
  let (_, started, _) = bounded_nest_fixture(
    nest="\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}],\"max_items\":1",
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  assert_true(drive_bounded_nest(execution) is BoundedNestFailed(_, ..))
  assert_true(cleanup_bounded_nest(execution).unwrap())
  assert_true(bounded_nest_released(execution))
}

///|
test "bounded nest nested phases visit one element per advance" {
  // Ten children under one parent with long text values: building, measuring
  // and rechecking the nested array must not run in one advance.
  let text = "x".repeat(200)
  let right = Array::makei(10, i => {
    "{\"key\":1,\"value\":\"" + text + i.to_string() + "\"}"
  })
  let (_, started, _) = bounded_nest_fixture(
    nest="\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}],\"max_items\":10",
    right_schema="{\"key\":{\"type\":\"number\",\"nullable\":true},\"value\":{\"type\":\"string\",\"nullable\":true}}",
    left_rows="[{\"id\":1,\"key\":1}]",
    right_rows="[" + right.join(",") + "]",
    max_work=100000,
    max_entries=1000,
    input_nodes=10000,
  )
  let execution = started.unwrap()
  let advances : Map[Int, Int] = Map([])
  let mut last = 0L
  let mut max_nested = 0L
  for _ in 0..<100000 {
    let phase = nest_phase_id(execution.state.phase)
    match advance_bounded_nest(execution, 1) {
      Ok(BoundedNestContinue(work~, ..)) => {
        let delta = work - last
        last = work
        advances.set(phase, advances.get_or_default(phase, 0) + 1)
        if phase == nest_phase_id(MeasureNested) ||
          phase == nest_phase_id(BuildCell) {
          max_nested = Int64::max(max_nested, delta)
        }
      }
      Ok(BoundedNestComplete(output, ..)) => {
        assert_eq(bounded_nest_item_counts(output), [10])
        break
      }
      _ => fail("nest did not complete")
    }
  }
  // One text value (about 200 bytes) at most per measuring advance.
  assert_true(max_nested <= 220L)
  assert_true(advances.get_or_default(nest_phase_id(BuildItem), 0) >= 10)
  assert_true(advances.get_or_default(nest_phase_id(MeasureNested), 0) >= 30)
  assert_true(advances.get_or_default(nest_phase_id(BuildCell), 0) >= 30)
  assert_true(cleanup_bounded_nest(execution).unwrap())
  assert_true(bounded_nest_released(execution))
}

///|
test "bounded nest charges a copied raw text through recheck and output" {
  let label = "x".repeat(4096)
  let left_schema = "{\"id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":true},\"label\":{\"type\":\"string\",\"nullable\":false}}"
  let left_rows = "[{\"id\":1,\"key\":1,\"label\":\"" + label + "\"}]"
  let right_rows = "[{\"key\":1,\"value\":10}]"
  let output_values : ValueLimits = {
    max_nodes: 7,
    max_text_bytes: 4117,
    max_depth: 4,
    max_work: 4124,
  }
  for (cancel_recheck, cancel_measure) in [(true, false), (false, true)] {
    let (control, started, reads) = bounded_nest_fixture(
      left_schema~,
      left_rows~,
      right_rows~,
      output_values~,
      max_work=100000,
      max_entries=1000,
    )
    let execution = started.unwrap()
    let mut reached = false
    for _ in 0..<20000 {
      if !reached {
        match advance_bounded_nest(execution, 1).unwrap() {
          BoundedNestContinue(..) => {
            let label_cell = @schema.field_at(
                execution.state.output_schema,
                execution.state.column,
              )
              is Some(field) &&
              @schema.reference_name(field.name) == "label"
            reached = label_cell &&
              (
                (cancel_recheck && execution.state.recheck is Some(_)) ||
                (cancel_measure && execution.state.output_measure is Some(_))
              )
            if reached {
              break
            }
          }
          _ => fail("nest output completed before the requested stop point")
        }
      }
    }
    assert_true(reached)
    // Advance the node check and a Text chunk before either cancellation.
    for _ in 0..<2 {
      assert_true(
        advance_bounded_nest(execution, 1) is Ok(BoundedNestContinue(..)),
      )
    }
    assert_false(execution.state.accepted.val)
    assert_true(execution.state.rows.val is None)
    assert_true(
      execution.state.output is Some(output) && output.buffer.rows.is_empty(),
    )
    assert_true(
      (cancel_recheck && execution.state.recheck is Some(_)) ||
      (cancel_measure && execution.state.output_measure is Some(_)),
    )
    if cancel_measure {
      assert_true(
        execution.state.output_measure is Some(cursor) &&
        cursor.frames is [SteppedTextNext(_, 64)],
      )
    }
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_nest(execution, 1) is Ok(BoundedNestStopped(_, ..)),
    )
    assert_true(cleanup_bounded_nest(execution).unwrap())
    assert_true(bounded_nest_released(execution))
    assert_false(execution.state.accepted.val)
    assert_true(execution.state.rows.val is None)
    assert_true(execution.state.output is None)
    assert_eq(execution.state.workspace.live, 0)
    assert_true(reads.all(read => producer_read_available(read)))
  }
  for
    (nodes, bytes, work, should_complete) in [
      (7, 4117, 4124, true),
      (6, 4117, 4124, false),
      (7, 4116, 4124, false),
      (7, 4117, 4123, false),
    ] {
    let (_, started, _) = bounded_nest_fixture(
      left_schema~,
      left_rows~,
      right_rows~,
      output_values={
        ..output_values,
        max_nodes: nodes,
        max_text_bytes: bytes,
        max_work: work,
      },
      max_work=100000,
      max_entries=1000,
    )
    let execution = started.unwrap()
    match drive_bounded_nest(execution) {
      BoundedNestComplete(output, ..) => {
        assert_true(should_complete)
        let column = Array::makei(completed_column_count(output), index => {
            completed_column_name(output, index).unwrap()
          })
          .search("label")
          .unwrap()
        guard completed_cell(output, 0, column) is Some(Text(actual)) else {
          fail("nest raw text was not retained")
        }
        assert_eq(actual, label)
        assert_eq(bounded_nest_item_counts(output), [1])
      }
      BoundedNestFailed(Capture(CaptureLimit), ..) =>
        assert_false(should_complete)
      _ => fail("nest output budget ended unexpectedly")
    }
    assert_true(cleanup_bounded_nest(execution).unwrap())
    assert_true(bounded_nest_released(execution))
  }
  // Key and field metadata (2 + 2), four output triples (12), one child
  // index triple (3), one match, the retained row and builder (4 + 1),
  // one projected item, and one measurement frame peak at 27 slots.
  for (entries, should_complete) in [(27, true), (26, false)] {
    let (_, started, _) = bounded_nest_fixture(
      left_schema~,
      left_rows~,
      right_rows~,
      output_values~,
      max_work=100000,
      max_entries=entries,
    )
    let execution = started.unwrap()
    match drive_bounded_nest(execution) {
      BoundedNestComplete(_, ..) => assert_true(should_complete)
      BoundedNestFailed(Rows(RowLimit), ..) => assert_false(should_complete)
      _ => fail("nest output workspace ended unexpectedly")
    }
    assert_true(cleanup_bounded_nest(execution).unwrap())
    assert_true(bounded_nest_released(execution))
  }
}

///|
fn nest_phase_id(phase : BoundedNestPhase) -> Int {
  match phase {
    ChargeInput => 0
    ResolveKey => 1
    ResolveOrder => 2
    ResolveField => 3
    ResolveOutput => 4
    SeedChild => 5
    SortChild => 6
    InitGrouped => 7
    BeginParent => 8
    CheckNull => 9
    SearchChild => 10
    MatchChild => 11
    ChargeRow => 12
    BuildItem => 13
    MeasureNested => 14
    CheckAttached => 15
    BuildCell => 16
    CommitRow => 17
    FinishOutput => 18
    Terminal => 19
  }
}
