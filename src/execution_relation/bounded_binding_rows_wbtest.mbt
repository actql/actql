///|
fn bounded_binding_rows_source(
  rows : String,
  id_nullable? : Bool = false,
  distinct? : Bool = false,
  top_k_source? : Bool = false,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let text = "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":" +
    (if id_nullable { "true" } else { "false" }) +
    (if distinct {
      "},\"tag\":{\"type\":\"string\",\"nullable\":true}}"
    } else {
      "},\"left\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false},\"right\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}"
    }) +
    ",\"rows\":" +
    rows +
    "},\"as\":\"seed\"}]"
  let text = if top_k_source {
    text.replace(
      old="\"as\":\"seed\"}]",
      new="\"as\":\"rows\"},{\"from\":\"rows\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"seed\"}]",
    )
  } else {
    text
  }
  let owner = bound_pipeline(text)
  let sequence = prepared_sequence(owner)
  let output_step = if top_k_source { 1 } else { 0 }
  let nodes = Array::makei(output_step + 1, index => {
    @lower.node_id(
      @lower.node_at(@lower.bound_preparation(owner), index).unwrap(),
    )
  })
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    nodes,
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
  ).unwrap()
  (owner, completed_output(completed, @pipeline.Step(output_step)).unwrap())
}

///|
fn bounded_binding_rows_receiver(
  source_owner : @lower.BoundPrepared,
  source_step? : Int = 0,
  following_step? : Bool = false,
  filter? : Bool = false,
  assert_all? : Bool = false,
  assert_unique? : Bool = false,
  select? : Bool = false,
  rename? : Bool = false,
  drop? : Bool = false,
  take? : Bool = false,
  top_k? : Bool = false,
  sort? : Bool = false,
  sort_empty? : Bool = false,
  distinct? : Bool = false,
  distinct_keyed? : Bool = false,
  derive_scalar? : Bool = false,
) -> @lower.BoundPrepared {
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(source_step),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[" +
      (if distinct_keyed {
        "{\"distinct\":[\"id\"],\"from\":\"rows\",\"as\":\"derived\"}"
      } else if distinct {
        "{\"distinct\":true,\"from\":\"rows\",\"as\":\"derived\"}"
      } else if top_k {
        "{\"top_k\":{\"k\":1,\"by\":[{\"id\":\"desc\"}]},\"from\":\"rows\",\"as\":\"derived\"}"
      } else if take {
        "{\"take\":{\"count\":1,\"offset\":1},\"from\":\"rows\",\"as\":\"derived\"}"
      } else if sort || sort_empty {
        "{\"sort\":" +
        (if sort_empty { "[]" } else { "[{\"id\":\"desc\"}]" }) +
        ",\"from\":\"rows\",\"as\":\"derived\"}"
      } else if assert_all {
        "{\"assert_rows\":{\"where\":\"id > 0\"},\"from\":\"rows\",\"as\":\"derived\"}"
      } else if assert_unique {
        "{\"assert_rows\":{\"unique_by\":[\"id\"]},\"from\":\"rows\",\"as\":\"derived\"}"
      } else if select {
        "{\"select\":[\"right\",\"id\"],\"from\":\"rows\",\"as\":\"derived\"}"
      } else if rename {
        "{\"rename\":{\"left\":\"alias\"},\"from\":\"rows\",\"as\":\"derived\"}"
      } else if drop {
        "{\"drop\":[\"left\"],\"from\":\"rows\",\"as\":\"derived\"}"
      } else if filter {
        "{\"filter\":\"id > 1\",\"from\":\"rows\",\"as\":\"derived\"}"
      } else if derive_scalar {
        "{\"derive\":{\"next\":\"id + 1\"},\"from\":\"rows\",\"as\":\"derived\"}"
      } else {
        "{\"derive\":{\"score\":{\"vector_score\":{\"left\":{\"field\":\"left\"},\"right\":{\"field\":\"right\"},\"metric\":\"dot\"}},\"joined\":{\"vector_concat\":[{\"field\":\"right\"},{\"field\":\"left\"}]}},\"from\":\"rows\",\"as\":\"derived\"}"
      }) +
      (if following_step {
        ",{\"select\":[\"score\"],\"from\":\"derived\"}"
      } else {
        ""
      }) +
      "]",
    ),
    [("rows", @pipeline.ProducedInput(producer))],
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
    expression_profiles={ text_time: false, veca: true, },
  ).unwrap()
}

///|
fn bounded_binding_rows_fixture(
  rows : String,
  following_step? : Bool = false,
  filter? : Bool = false,
  assert_all? : Bool = false,
  assert_unique? : Bool = false,
  select? : Bool = false,
  rename? : Bool = false,
  drop? : Bool = false,
  take? : Bool = false,
  top_k? : Bool = false,
  sort? : Bool = false,
  sort_empty? : Bool = false,
  distinct? : Bool = false,
  distinct_keyed? : Bool = false,
  derive_scalar? : Bool = false,
  id_nullable? : Bool = false,
  input_limits? : ValueLimits? = None,
  max_work? : Int = 100000,
  max_entries? : Int = 10000,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  let (source_owner, source) = bounded_binding_rows_source(
    rows,
    id_nullable~,
    distinct=distinct || distinct_keyed,
    top_k_source=top_k,
  )
  let receiver = bounded_binding_rows_receiver(
    source_owner,
    source_step=if top_k { 1 } else { 0 },
    following_step~,
    filter~,
    assert_all~,
    assert_unique~,
    select~,
    rename~,
    drop~,
    take~,
    top_k~,
    sort~,
    sort_empty~,
    distinct~,
    distinct_keyed~,
    derive_scalar~,
  )
  let sequence = prepared_sequence(receiver)
  let first = @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    if select ||
      rename ||
      drop ||
      assert_unique ||
      take ||
      top_k ||
      sort ||
      sort_empty ||
      distinct ||
      distinct_keyed {
      []
    } else {
      [sequence_fragment_context(sequence, 0, 2L)]
    },
    [@lower.node_id(first)],
    100000,
    10000,
  ).unwrap()
  let generated = if following_step {
    select_generated_sequence_step(generated, 0).unwrap()
  } else {
    generated
  }
  let bound = bind_completed_input(receiver, 0, source_owner, source).unwrap()
  let input = prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_binding_rows(
    control,
    generated,
    input,
    100,
    input_limits.unwrap_or_else(() => run_limits().input_values),
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, execution, input)
}

///|
test "bounded distinct preserves first occurrence and null equality" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":2,\"tag\":\"b\"},{\"id\":1,\"tag\":\"a\"},{\"id\":2,\"tag\":\"b\"},{\"id\":null,\"tag\":null},{\"id\":null,\"tag\":null}]",
    distinct=true,
    id_nullable=true,
  )
  let mut advances = 0
  let mut completed : CompletedOutput? = None
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("bounded distinct failed")
      BoundedBindingRowsStopped(_, ..) => fail("bounded distinct stopped")
    }
  }
  guard completed is Some(output) else {
    fail("bounded distinct did not finish")
  }
  assert_true(advances > 5)
  assert_eq(completed_row_count(output), 3)
  assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(1.0)))
  assert_true(completed_cell(output, 2, 0) is Some(Null))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded keyed distinct compares only projected fields" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":2,\"tag\":\"a\"},{\"id\":1,\"tag\":\"b\"},{\"id\":2,\"tag\":\"c\"},{\"id\":null,\"tag\":\"d\"},{\"id\":null,\"tag\":\"e\"}]",
    distinct_keyed=true,
    id_nullable=true,
  )
  let mut completed : CompletedOutput? = None
  for _ in 0..<1000 {
    if completed is Some(_) {
      break
    }
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("bounded keyed distinct failed")
    }
  }
  guard completed is Some(output) else { fail("keyed distinct did not finish") }
  assert_eq(completed_row_count(output), 3)
  assert_eq(completed_column_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(1.0)))
  assert_true(completed_cell(output, 2, 0) is Some(Null))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded distinct cancels during index work without output" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":2,\"tag\":\"b\"},{\"id\":1,\"tag\":\"a\"},{\"id\":2,\"tag\":\"b\"},{\"id\":null,\"tag\":null}]",
    distinct=true,
    id_nullable=true,
  )
  for _ in 0..<12 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded distinct admits exact and one-short structural workspace" {
  let rows = "[{\"id\":2,\"tag\":\"b\"},{\"id\":1,\"tag\":\"a\"}]"
  // Eight metadata slots overlap with two terms and two index arrays.
  // After sorting, the keep bitmap replaces one index array.
  let (_, accepted, accepted_input) = bounded_binding_rows_fixture(
    rows,
    distinct=true,
    max_entries=14,
  )
  let mut completed = false
  for _ in 0..<1000 {
    if completed {
      break
    }
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        completed = true
      }
      _ => fail("exact distinct workspace rejected")
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())
  assert_true(producer_read_available(accepted_input))
  let (_, rejected, rejected_input) = bounded_binding_rows_fixture(
    rows,
    distinct=true,
    max_entries=13,
  )
  let mut failed = false
  for _ in 0..<1000 {
    if failed {
      break
    }
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      _ => fail("one-short distinct workspace had another outcome")
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
  assert_true(producer_read_available(rejected_input))
}

///|
test "bounded distinct admits exact and one-short control work" {
  let rows = "[{\"id\":2,\"tag\":\"b\"},{\"id\":1,\"tag\":\"a\"}]"
  // Two distinct terms and two rows account for 31 control units across
  // input admission, indexed ordering, marking, and output construction.
  for budget in [31, 30] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      rows,
      distinct=true,
      max_work=budget,
      max_entries=14,
    )
    let mut done = false
    for _ in 0..<1000 {
      if done {
        break
      }
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_eq(budget, 31)
          assert_eq(completed_row_count(output), 2)
          assert_eq(completed_column_count(output), 2)
          done = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_eq(budget, 30)
          assert_true(bounded_binding_rows_cleanup_pending(execution))
          done = true
        }
        _ => fail("distinct control-work boundary had another outcome")
      }
    }
    assert_true(done)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(producer_read_available(input))
  }
}

///|
test "bounded keyed distinct admits exact and one-short control work" {
  let rows = "[{\"id\":2,\"tag\":\"b\"},{\"id\":1,\"tag\":\"a\"}]"
  // The keyed projection retains one output field and one sort term;
  // input admission still covers both source fields.
  for budget in [24, 23] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      rows,
      distinct_keyed=true,
      max_work=budget,
    )
    let mut done = false
    for _ in 0..<1000 {
      if done {
        break
      }
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_eq(budget, 24)
          assert_eq(completed_row_count(output), 2)
          assert_eq(completed_column_count(output), 1)
          done = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_eq(budget, 23)
          assert_true(bounded_binding_rows_cleanup_pending(execution))
          done = true
        }
        _ => fail("keyed distinct control-work boundary had another outcome")
      }
    }
    assert_true(done)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(producer_read_available(input))
  }
}

///|
test "bounded keyed distinct admits exact and one-short workspace" {
  let rows = "[{\"id\":2,\"tag\":\"b\"},{\"id\":1,\"tag\":\"a\"}]"
  // Eight metadata slots overlap with one key term and two sort indices;
  // the keep bitmap replaces an index array after ordering.
  for slots in [11, 10] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      rows,
      distinct_keyed=true,
      max_work=24,
      max_entries=slots,
    )
    let mut done = false
    for _ in 0..<1000 {
      if done {
        break
      }
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_eq(slots, 11)
          assert_eq(completed_row_count(output), 2)
          assert_eq(completed_column_count(output), 1)
          done = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_eq(slots, 10)
          assert_true(bounded_binding_rows_cleanup_pending(execution))
          done = true
        }
        _ => fail("keyed distinct workspace boundary had another outcome")
      }
    }
    assert_true(done)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(producer_read_available(input))
  }
}

///|
test "bounded selected sort preserves stable ties with one-work advances" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":3,\"left\":[2,1],\"right\":[4,3]},{\"id\":3,\"left\":[5,6],\"right\":[7,8]},{\"id\":2,\"left\":[9,10],\"right\":[11,12]}]",
    sort=true,
  )
  let mut advances = 0
  let mut completed : CompletedOutput? = None
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("selected sort failed")
      BoundedBindingRowsStopped(_, ..) => fail("selected sort stopped")
    }
  }
  guard completed is Some(output) else { fail("selected sort did not finish") }
  assert_true(advances > 4)
  assert_eq(completed_row_count(output), 4)
  assert_true(completed_cell(output, 0, 0) is Some(Number(3.0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(3.0)))
  assert_true(completed_cell(output, 2, 0) is Some(Number(2.0)))
  assert_true(completed_cell(output, 3, 0) is Some(Number(1.0)))
  guard completed_cell(output, 0, 1) is Some(Captured(@admitted.Vector(first))) &&
    completed_cell(output, 1, 1) is Some(Captured(@admitted.Vector(second))) else {
    fail("stable tie vectors")
  }
  assert_eq(@admitted.elements(first), [2.0, 1.0])
  assert_eq(@admitted.elements(second), [5.0, 6.0])
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected sort cancels after work without publishing rows" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":3,\"left\":[1,2],\"right\":[3,4]},{\"id\":1,\"left\":[2,1],\"right\":[4,3]},{\"id\":2,\"left\":[5,6],\"right\":[7,8]}]",
    sort=true,
  )
  for _ in 0..<20 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected sort admits its exact workspace peak" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // The retained typed view and schema metadata overlap with the two merge
  // indices. Later, one index and both three-cell row arrays are live.
  let (_, execution, input) = bounded_binding_rows_fixture(
    rows,
    sort=true,
    max_entries=21,
  )
  let mut completed = false
  let mut advances = 0
  while !completed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
        assert_true(completed_cell(output, 1, 0) is Some(Number(1.0)))
        completed = true
      }
      _ => fail("exact sort workspace boundary failed")
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected sort rejects a workspace one entry short" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  let (_, execution, input) = bounded_binding_rows_fixture(
    rows,
    sort=true,
    max_entries=20,
  )
  let mut failed = false
  let mut advances = 0
  while !failed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      _ => fail("one-short sort workspace boundary had another outcome")
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected sort has an exact control-work boundary" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Independent control sum: input row open/close 4, schema names 14,
  // sort-row admission 2, key name 3, child-sort polls 7, comparison 1,
  // output row starts 2, and copied fields 6.
  let (_, accepted, input) = bounded_binding_rows_fixture(
    rows,
    sort=true,
    max_work=39,
  )
  let mut completed = false
  while !completed {
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        completed = true
      }
      _ => fail("exact sort work failed")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())

  let (_, rejected, input) = bounded_binding_rows_fixture(
    rows,
    sort=true,
    max_work=38,
  )
  let mut failed = false
  while !failed {
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      BoundedBindingRowsComplete(_, ..) => fail("one-short sort work completed")
      _ => fail("one-short sort work had another outcome")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
}

///|
test "bounded global top-k admits exact work and workspace" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Two input rows, schema names, sort admission, the merge comparison,
  // and one three-field output require 35 control units. Metadata, two
  // merge indices, and the checked output row peak at 21 workspace slots.
  for
    (work, entries, accepted) in [
      (35, 21, true),
      (34, 21, false),
      (35, 20, false),
    ] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      rows,
      top_k=true,
      max_work=work,
      max_entries=entries,
    )
    let mut terminal = false
    let mut polls = 0
    while !terminal && polls < 1000 {
      polls += 1
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(accepted)
          assert_eq(completed_row_count(output), 1)
          assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
          terminal = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_false(accepted)
          terminal = true
        }
        _ => fail("unexpected global top-k resource outcome")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(producer_read_available(input))
  }
}

///|
test "bounded global top-k stops before publishing partial output" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    top_k=true,
  )
  for _ in 0..<20 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected empty sort reuses the input order" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":3,\"left\":[1,2],\"right\":[3,4]},{\"id\":1,\"left\":[2,1],\"right\":[4,3]},{\"id\":2,\"left\":[5,6],\"right\":[7,8]}]",
    sort_empty=true,
  )
  let mut completed : CompletedOutput? = None
  let mut advances = 0
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("empty sort failed")
    }
  }
  guard completed is Some(output) else { fail("empty sort did not finish") }
  assert_eq(completed_row_count(output), 3)
  assert_true(completed_cell(output, 0, 0) is Some(Number(3.0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(1.0)))
  assert_true(completed_cell(output, 2, 0) is Some(Number(2.0)))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected empty sort admits exact work and workspace" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Work: input row open/close 4, schema names 14, sort-row admission 2,
  // identity indices 2, output row starts 2, copied fields 6.
  // Workspace: metadata 12, identity indices 2, two three-cell row arrays 6.
  let (_, accepted, input) = bounded_binding_rows_fixture(
    rows,
    sort_empty=true,
    max_work=30,
    max_entries=20,
  )
  let mut completed = false
  while !completed {
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        completed = true
      }
      _ => fail("exact empty sort resources failed")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())

  for (work, slots) in [(29, 20), (30, 19)] {
    let (_, rejected, input) = bounded_binding_rows_fixture(
      rows,
      sort_empty=true,
      max_work=work,
      max_entries=slots,
    )
    let mut failed = false
    while !failed {
      match advance_bounded_binding_rows(rejected, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
        BoundedBindingRowsComplete(_, ..) =>
          fail("one-short empty sort resources completed")
        _ => fail("one-short empty sort resources had another outcome")
      }
    }
    assert_true(producer_read_available(input))
    assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
  }
}

///|
test "bounded selected empty sort uses linear charged advances" {
  let visits = []
  for count in [8, 32] {
    let rows = "[" +
      Array::makei(count, index => {
        "{\"id\":" + index.to_string() + ",\"left\":[1,2],\"right\":[3,4]}"
      }).join(",") +
      "]"
    let (_, execution, _) = bounded_binding_rows_fixture(rows, sort_empty=true)
    let mut advances = 0
    let mut completed : CompletedOutput? = None
    while completed is None && advances < 1000 {
      advances += 1
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => completed = Some(output)
        _ => fail("empty sort scaling failed")
      }
    }
    guard completed is Some(output) else { fail("empty sort did not finish") }
    assert_eq(completed_row_count(output), count)
    visits.push(advances)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  }
  assert_true(visits[1] < visits[0] * 5)
}

///|
fn bounded_binding_rows_ordered_context(
  sequence : @lower.PreparedSequence,
) -> FragmentRuntimeContext raise {
  guard @lower.sequence_step(sequence, 0) is Some(@lower.RowStep(kernel)) else {
    fail("ordered row kernel")
  }
  let references = @lower.prepare_ordered_references(kernel, {
    max_references: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let contract = admit_ordered_contract(
    registered_relation_contracts(),
    registered_ordered(),
    registry_limits(),
  ).unwrap()
  let params = prepare_ordered_params(contract, references)
  let ordered = prepare_ordered_limits(
    params,
    {
      max_input_rows: 2L,
      max_value_bytes: 1000L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
    10L,
    1000L,
  ).unwrap()
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 0, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(
    pipeline,
    10L,
    1000L,
    row_limits=Some(ordered.limits),
  ).unwrap()
  prepare_runtime_fragment(
    request,
    test_fragment_contract(),
    material_demands(),
    registry_limits(),
    ordered.limits,
    ordered=Some(ordered.params.contract),
  ).unwrap()
}

///|
fn bounded_binding_rows_ordered_fixture() -> (
  BoundedBindingRowsExecution,
  ProducerRead,
) raise {
  let source_owner = row_owner("")
  let source_sequence = prepared_sequence(source_owner)
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    source_sequence,
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
    input_cursor(
      "[{\"derive\":[{\"old\":\"a\"},{\"next\":\"old + b\"}],\"from\":\"rows\"}]",
    ),
    [("rows", @pipeline.ProducedInput(producer))],
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
  let sequence = prepared_sequence(receiver)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [bounded_binding_rows_ordered_context(sequence)],
    ["derive_0"],
    100000,
    10000,
  ).unwrap()
  let bound = bind_completed_input(receiver, 0, source_owner, source).unwrap()
  let input = prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let execution = start_bounded_binding_rows(
    @bounded.control(),
    generated,
    input,
    100,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  (execution, input)
}

///|
fn bounded_binding_rows_keyed_take_fixture(
  max_work : Int,
  max_entries? : Int = 10000,
) -> (BoundedBindingRowsExecution, ProducerRead) raise {
  let source_owner = take_key_owner("[{\"sort\":[]}]")
  let source_sequence = prepared_sequence(source_owner)
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    source_sequence,
    [],
    ["sort_0"],
    100000,
    10000,
  ).unwrap()
  let captured = capture_input(
    source_owner,
    0,
    [
      input_cursor("{\"n\":3,\"s\":\"third\"}"),
      input_cursor("{\"n\":1,\"s\":\"first\"}"),
      input_cursor("{\"n\":2,\"s\":\"second\"}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(
      source_generated,
      [captured],
      compute_test_limits(),
    ).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let receiver = sort_input_owner(
    @pipeline.ProducedInput(producer),
    "[{\"take\":1}]",
  )
  let sequence = prepared_sequence(receiver)
  guard @lower.node_at(@lower.bound_preparation(receiver), 0) is Some(node) &&
    @lower.order_node_id(node) is Some(_) else {
    fail("take requires an inherited key-completion sort")
  }
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["limit_0"],
    100000,
    10000,
  ).unwrap()
  let bound = bind_completed_input(receiver, 0, source_owner, source).unwrap()
  let input = prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let execution = start_bounded_binding_rows(
    @bounded.control(),
    generated,
    input,
    100,
    run_limits().input_values,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (execution, input)
}

///|
test "bounded binding rows resume vector expressions and complete exactly" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
  )
  let mut advances = 0
  let mut completed : CompletedOutput? = None
  while completed is None {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("unexpected failure")
      BoundedBindingRowsStopped(_, ..) => fail("unexpected stop")
    }
  }
  assert_true(advances > 10)
  let output = completed.unwrap()
  assert_eq(completed_row_count(output), 2)
  assert_eq(completed_column_count(output), 5)
  assert_eq(
    Array::makei(5, column => completed_column_name(output, column).unwrap()),
    ["id", "joined", "left", "right", "score"],
  )
  assert_true(completed_cell(output, 0, 4) is Some(Number(11.0)))
  assert_true(completed_cell(output, 1, 4) is Some(Number(11.0)))
  guard completed_cell(output, 0, 1) is Some(Captured(@admitted.Vector(joined))) else {
    fail("expected joined vector")
  }
  assert_eq(@admitted.elements(joined), [3.0, 4.0, 1.0, 2.0])
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
}

///|
test "bounded vector expressions admit exact work and workspace" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // The two-row fixture executes both dot score and concatenation through the
  // selected derive path. Its fixed control boundary is 160 units, including
  // both input occurrences, expression transitions, and output names. The
  // simultaneous metadata, retained roots, and vector scratch peak at 34.
  for
    (limit_work, slots, accepted) in [
      (160, 34, true),
      (159, 34, false),
      (160, 33, false),
    ] {
    let (_, execution, _) = bounded_binding_rows_fixture(
      rows,
      max_work=limit_work,
      max_entries=slots,
    )
    let mut done = false
    let mut polls = 0
    while !done && polls < 1000 {
      polls += 1
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(accepted)
          assert_eq(completed_row_count(output), 2)
          assert_true(completed_cell(output, 0, 4) is Some(Number(11.0)))
          guard completed_cell(output, 0, 1)
            is Some(Captured(@admitted.Vector(joined))) else {
            fail("expected concatenated vector")
          }
          assert_eq(@admitted.elements(joined), [3.0, 4.0, 1.0, 2.0])
          done = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_false(accepted)
          assert_true(bounded_binding_rows_cleanup_pending(execution))
          done = true
        }
        _ => fail("unexpected vector boundary outcome")
      }
    }
    assert_true(done)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_false(bounded_binding_rows_cleanup_pending(execution))
  }
}

///|
test "bounded binding rows cancel without publishing partial output" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
  )
  for i = 0; i < 15; i = i + 1 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(producer_read_available(input))
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
  assert_true(producer_read_available(input))
}

///|
test "bounded selected assertion preserves rows and rejects a later failure" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  let (_, accepted, source) = bounded_binding_rows_fixture(
    rows,
    assert_all=true,
  )
  let mut completed : CompletedOutput? = None
  let mut advances = 0
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("valid assertion failed")
    }
  }
  guard completed is Some(output) else { fail("assertion did not finish") }
  assert_eq(completed_row_count(output), 2)
  assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(2.0)))
  assert_true(producer_read_available(source))
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())

  let (_, rejected, rejected_input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":-1,\"left\":[2,1],\"right\":[4,3]}]",
    assert_all=true,
  )
  let mut failed = false
  let mut failure_advances = 0
  while !failed && failure_advances < 1000 {
    failure_advances += 1
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(AssertionPredicate(1)), ..) => failed = true
      BoundedBindingRowsComplete(_, ..) =>
        fail("failed assertion published rows")
      _ => fail("assertion reported the wrong failure")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(rejected))
  assert_true(producer_read_available(rejected_input))
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
}

///|
test "bounded selected assertion cancels without publishing rows" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    assert_all=true,
  )
  for _ in 0..<20 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected assertion admits its exact input boundary" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    assert_all=true,
    input_limits=Some({
      max_nodes: 16,
      max_text_bytes: 22,
      max_depth: 3,
      max_work: 38,
    }),
  )
  let mut completed = false
  let mut advances = 0
  while !completed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        completed = true
      }
      _ => fail("exact assertion input boundary failed")
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
fn verify_selected_assertion_resources(
  unique : Bool,
  exact_work : Int,
  exact_slots : Int,
) -> Unit raise {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  for
    (work, slots, should_complete) in [
      (exact_work, exact_slots, true),
      (exact_work - 1, exact_slots, false),
      (exact_work, exact_slots - 1, false),
    ] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      rows,
      assert_all=!unique,
      assert_unique=unique,
      max_work=work,
      max_entries=slots,
    )
    let mut terminal = false
    let mut advances = 0
    while !terminal && advances < 1000 {
      advances += 1
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(should_complete)
          assert_eq(completed_row_count(output), 2)
          terminal = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_false(should_complete)
          terminal = true
        }
        _ => fail("assertion resource boundary had another outcome")
      }
    }
    assert_true(terminal)
    assert_true(bounded_binding_rows_cleanup_pending(execution))
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(producer_read_available(input))
  }
}

///|
test "bounded selected where assertion admits exact work and workspace" {
  // Two row starts (2), six snapshot entries with their UTF-8 names (28),
  // two predicate evaluations (18), and six output names (22) cost 70.
  // Nine metadata slots overlap two retained roots and three slots each for
  // snapshot, output row, and checked row, giving a peak of 20.
  verify_selected_assertion_resources(false, 70, 20)
}

///|
test "bounded selected unique assertion admits exact work and workspace" {
  // The two-row key/index/comparison path costs 17 control units. Two row
  // starts and six output field names cost another 24, for 41 total.
  // Ten metadata slots overlap six output and checked-row slots at peak.
  verify_selected_assertion_resources(true, 41, 16)
}

///|
test "bounded selected assertion rejects an input one node short" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    assert_all=true,
    input_limits=Some({
      max_nodes: 15,
      max_text_bytes: 22,
      max_depth: 3,
      max_work: 38,
    }),
  )
  let mut failed = false
  let mut advances = 0
  while !failed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(InputLimit, ..) => failed = true
      _ => fail("one-short assertion input boundary had another outcome")
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "selected binding rows stop within a larger checked sequence" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    following_step=true,
  )
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsContinue(..)),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
}

///|
test "bounded selected filter evaluates demanded rows once" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    filter=true,
  )
  let mut advances = 0
  let mut completed : CompletedOutput? = None
  while completed is None {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("unexpected filter failure")
      BoundedBindingRowsStopped(_, ..) => fail("unexpected filter stop")
    }
  }
  assert_true(advances > 6)
  let output = completed.unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected unique assertion preserves distinct input order" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":2,\"left\":[1,2],\"right\":[3,4]},{\"id\":1,\"left\":[2,1],\"right\":[4,3]}]",
    assert_unique=true,
  )
  let mut completed : CompletedOutput? = None
  let mut advances = 0
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("unexpected unique assertion failure")
    }
  }
  guard completed is Some(output) else { fail("assertion did not complete") }
  assert_true(advances > 10)
  assert_eq(completed_row_count(output), 2)
  assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(1.0)))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected unique assertion rejects duplicates before output" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":1,\"left\":[2,1],\"right\":[4,3]}]",
    assert_unique=true,
  )
  let mut failed = false
  let mut advances = 0
  while !failed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(AssertionDuplicate(0, 1)), ..) =>
        failed = true
      _ => fail("unexpected unique assertion outcome")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected unique assertion rejects a nullable NULL key" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":null,\"left\":[2,1],\"right\":[4,3]}]",
    assert_unique=true,
    id_nullable=true,
  )
  let mut failed = false
  let mut advances = 0
  while !failed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(AssertionNullKey(1, 0)), ..) =>
        failed = true
      _ => fail("unexpected nullable unique assertion outcome")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected unique assertion accepts empty input" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[]",
    assert_unique=true,
  )
  let mut completed : CompletedOutput? = None
  let mut advances = 0
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("unexpected empty unique assertion failure")
    }
  }
  guard completed is Some(output) else {
    fail("empty assertion did not complete")
  }
  assert_eq(completed_row_count(output), 0)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected unique assertion cancels during key validation" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    assert_unique=true,
  )
  for _ in 0..<2 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected unique assertion cancels during index sorting" {
  let rows = "[" +
    Array::makei(32, index => {
      "{\"id\":" + index.to_string() + ",\"left\":[1,2],\"right\":[3,4]}"
    }).join(",") +
    "]"
  let (control, execution, input) = bounded_binding_rows_fixture(
    rows,
    assert_unique=true,
  )
  // One key preparation, 32 NULL checks, sort setup, and six sort steps.
  for _ in 0..<40 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected unique assertion reclaims a failed child sort" {
  let rows = "[" +
    Array::makei(32, index => {
      "{\"id\":" + index.to_string() + ",\"left\":[1,2],\"right\":[3,4]}"
    }).join(",") +
    "]"
  let (_, execution, input) = bounded_binding_rows_fixture(
    rows,
    assert_unique=true,
    max_work=45,
  )
  let mut failed = false
  let mut advances = 0
  while !failed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      _ => fail("unexpected unique sort work outcome")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected unique assertion has exact workspace peak" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Ten retained metadata entries, one key order, four merge-index slots,
  // then six output-row and checked-value slots at the later peak.
  let (_, accepted, accepted_input) = bounded_binding_rows_fixture(
    rows,
    assert_unique=true,
    max_entries=16,
  )
  let mut completed = false
  let mut advances = 0
  while !completed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        completed = true
      }
      _ => fail("exact unique workspace boundary failed")
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())
  assert_true(producer_read_available(accepted_input))
  let (_, rejected, rejected_input) = bounded_binding_rows_fixture(
    rows,
    assert_unique=true,
    max_entries=15,
  )
  let mut failed = false
  advances = 0
  while !failed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      _ => fail("one-short unique workspace boundary had another outcome")
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
  assert_true(producer_read_available(rejected_input))
}

///|
test "bounded selected filter cancels before publication" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    filter=true,
  )
  for _ in 0..<15 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected derive admits exact work and workspace" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Two input and row-opening charges, six snapshot field charges, 22
  // snapshot-name bytes, two eight-unit scalar expression evaluations,
  // and 30 output-name bytes give 78 control units. The structural peak
  // is 12 metadata slots plus 15 overlapping retained/row/expression slots.
  for
    (work, slots, accepted) in [
      (78, 27, true),
      (77, 27, false),
      (78, 26, false),
    ] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      rows,
      derive_scalar=true,
      max_work=work,
      max_entries=slots,
    )
    let mut finished = false
    let mut polls = 0
    while !finished && polls < 1000 {
      polls += 1
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(accepted)
          assert_eq(completed_row_count(output), 2)
          assert_eq(completed_column_name(output, 2), Some("next"))
          assert_true(completed_cell(output, 0, 2) is Some(Number(2.0)))
          assert_true(completed_cell(output, 1, 2) is Some(Number(3.0)))
          finished = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_false(accepted)
          assert_true(bounded_binding_rows_cleanup_pending(execution))
          finished = true
        }
        _ => fail("unexpected derive outcome")
      }
    }
    assert_true(finished)
    assert_true(producer_read_available(input))
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  }
}

///|
test "bounded selected derive admits exact input and rejects one-short" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Each input row owns one object, three field values, and four vector
  // components. Both rows therefore require exactly 16 input value nodes.
  for (nodes, accepted) in [(16, true), (15, false)] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      rows,
      derive_scalar=true,
      input_limits=Some({
        max_nodes: nodes,
        max_text_bytes: 22,
        max_depth: 3,
        max_work: 38,
      }),
    )
    let mut finished = false
    let mut polls = 0
    while !finished && polls < 1000 {
      polls += 1
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(accepted)
          assert_eq(completed_row_count(output), 2)
          finished = true
        }
        BoundedBindingRowsFailed(InputLimit, ..) => {
          assert_false(accepted)
          assert_true(bounded_binding_rows_cleanup_pending(execution))
          finished = true
        }
        _ => fail("derive input boundary had another outcome")
      }
    }
    assert_true(finished)
    assert_true(producer_read_available(input))
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  }
}

///|
test "bounded selected derive stops after work without publication" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    derive_scalar=true,
  )
  for _ in 0..<15 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected filter admits exact work and workspace" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // The fixed two-row comparison fixture has a 59-unit control boundary.
  // Metadata, retained roots, predicate scratch, and row views peak at 20.
  let (_, accepted, input) = bounded_binding_rows_fixture(
    rows,
    filter=true,
    max_work=59,
    max_entries=20,
  )
  let mut completed = false
  let mut advances = 0
  while !completed && advances < 500 {
    advances += 1
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 1)
        assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
        completed = true
      }
      _ => fail("exact selected filter resources failed")
    }
  }
  assert_true(completed)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())

  for (work, slots) in [(58, 20), (59, 19)] {
    let (_, rejected, input) = bounded_binding_rows_fixture(
      rows,
      filter=true,
      max_work=work,
      max_entries=slots,
    )
    let mut failed = false
    let mut polls = 0
    while !failed && polls < 500 {
      polls += 1
      match advance_bounded_binding_rows(rejected, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
        BoundedBindingRowsComplete(_, ..) =>
          fail("one-short selected filter resources completed")
        _ => fail("one-short selected filter had another outcome")
      }
    }
    assert_true(failed)
    assert_true(producer_read_available(input))
    assert_true(bounded_binding_rows_cleanup_pending(rejected))
    assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
  }
}

///|
test "bounded selected filter admits its exact input boundary" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    filter=true,
    input_limits=Some({
      max_nodes: 16,
      max_text_bytes: 22,
      max_depth: 3,
      max_work: 38,
    }),
  )
  let mut completed : CompletedOutput? = None
  let mut advances = 0
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("exact filter input boundary failed")
    }
  }
  guard completed is Some(output) else { fail("filter did not complete") }
  assert_eq(completed_row_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected filter rejects an input one node short" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    filter=true,
    input_limits=Some({
      max_nodes: 15,
      max_text_bytes: 22,
      max_depth: 3,
      max_work: 38,
    }),
  )
  let mut failed = false
  let mut advances = 0
  while !failed && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(InputLimit, ..) => failed = true
      BoundedBindingRowsComplete(_, ..) => fail("short filter input completed")
      _ => fail("short filter input had another outcome")
    }
  }
  assert_true(failed)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected projection preserves schema order and input admission" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    select=true,
  )
  let mut advances = 0
  let mut completed : CompletedOutput? = None
  while completed is None {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("unexpected projection failure")
      BoundedBindingRowsStopped(_, ..) => fail("unexpected projection stop")
    }
  }
  assert_true(advances > 10)
  let output = completed.unwrap()
  assert_eq(completed_row_count(output), 2)
  assert_eq(completed_column_count(output), 2)
  assert_eq(completed_column_name(output, 0), Some("id"))
  assert_eq(completed_column_name(output, 1), Some("right"))
  assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
  guard completed_cell(output, 1, 1) is Some(Captured(@admitted.Vector(right))) else {
    fail("expected selected vector")
  }
  assert_eq(@admitted.elements(right), [4.0, 3.0])
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected projection admits exact work and workspace" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Work: two input-row openings, two output-row openings, and the
  // seven UTF-8 output-name bytes charged for each of two rows.
  // Workspace: two selected-field view entries, three input names, two
  // output names, three input ordinals, two selected ordinals, and four
  // slots for one output row plus its checked copy.
  let (_, accepted, input) = bounded_binding_rows_fixture(
    rows,
    select=true,
    max_work=18,
    max_entries=16,
  )
  let mut completed = false
  let mut polls = 0
  while !completed && polls < 500 {
    polls += 1
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        assert_eq(completed_column_name(output, 0), Some("id"))
        assert_eq(completed_column_name(output, 1), Some("right"))
        completed = true
      }
      _ => fail("exact selected projection resources failed")
    }
  }
  assert_true(completed)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())

  for (work, slots) in [(17, 16), (18, 15)] {
    let (_, rejected, input) = bounded_binding_rows_fixture(
      rows,
      select=true,
      max_work=work,
      max_entries=slots,
    )
    let mut failed = false
    let mut polls = 0
    while !failed && polls < 500 {
      polls += 1
      match advance_bounded_binding_rows(rejected, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
        BoundedBindingRowsComplete(_, ..) =>
          fail("one-short selected projection resources completed")
        _ => fail("one-short selected projection had another outcome")
      }
    }
    assert_true(failed)
    assert_true(producer_read_available(input))
    assert_true(bounded_binding_rows_cleanup_pending(rejected))
    assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
  }
}

///|
fn bounded_projection_source_form_limits(
  rename : Bool,
  work : Int,
  workspace : Int,
  accepted : Bool,
) -> Unit raise {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  let (_, execution, input) = bounded_binding_rows_fixture(
    rows,
    rename~,
    drop=!rename,
    max_work=work,
    max_entries=workspace,
  )
  let mut terminated = false
  let mut polls = 0
  while !terminated && polls < 500 {
    polls += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_true(accepted)
        assert_eq(completed_row_count(output), 2)
        assert_eq(completed_column_count(output), if rename { 3 } else { 2 })
        assert_eq(
          completed_column_name(output, 0),
          Some(if rename { "alias" } else { "id" }),
        )
        terminated = true
      }
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
        assert_false(accepted)
        assert_true(bounded_binding_rows_cleanup_pending(execution))
        terminated = true
      }
      _ => fail("projection source form had another outcome")
    }
  }
  assert_true(terminated)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded rename admits exact and one-short work and workspace" {
  // Two input and two output row openings, plus two copies of the
  // 12 UTF-8 bytes in alias, id, and right, require 28 control units.
  // Three view entries, three input names, three output names, three
  // input ordinals, three projection ordinals, and six live row entries
  // require 21 structural slots at the peak.
  bounded_projection_source_form_limits(true, 28, 21, true)
  bounded_projection_source_form_limits(true, 27, 21, false)
  bounded_projection_source_form_limits(true, 28, 20, false)
}

///|
test "bounded drop admits exact and one-short work and workspace" {
  // Two input and two output row openings, plus two copies of the
  // seven UTF-8 bytes in id and right, require 18 control units.
  // Two view entries, three input names, two output names, three input
  // ordinals, two projection ordinals, and four live row entries peak at 16.
  bounded_projection_source_form_limits(false, 18, 16, true)
  bounded_projection_source_form_limits(false, 17, 16, false)
  bounded_projection_source_form_limits(false, 18, 15, false)
}

///|
fn bounded_projection_source_form_input_and_cancel(rename : Bool) -> Unit raise {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Each of two rows has one object, three field values, and four vector
  // elements: 16 input nodes, independently of the output projection.
  for (nodes, accepted) in [(16, true), (15, false)] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      rows,
      rename~,
      drop=!rename,
      input_limits=Some({
        max_nodes: nodes,
        max_text_bytes: 22,
        max_depth: 3,
        max_work: 38,
      }),
    )
    let mut terminated = false
    let mut polls = 0
    while !terminated && polls < 500 {
      polls += 1
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(accepted)
          assert_eq(completed_row_count(output), 2)
          terminated = true
        }
        BoundedBindingRowsFailed(InputLimit, ..) => {
          assert_false(accepted)
          terminated = true
        }
        _ => fail("projection input boundary had another outcome")
      }
    }
    assert_true(terminated)
    assert_true(producer_read_available(input))
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  }
  let (control, execution, input) = bounded_binding_rows_fixture(
    rows,
    rename~,
    drop=!rename,
  )
  for _ in 0..<12 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded rename validates exact input and cancels before output" {
  bounded_projection_source_form_input_and_cancel(true)
}

///|
test "bounded drop validates exact input and cancels before output" {
  bounded_projection_source_form_input_and_cancel(false)
}

///|
test "bounded selected projection cancels before publication" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    select=true,
  )
  for _ in 0..<12 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected projection rejects an input one node short" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    select=true,
    input_limits=Some({
      max_nodes: 15,
      max_text_bytes: 22,
      max_depth: 3,
      max_work: 38,
    }),
  )
  let mut failed = false
  while !failed {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(InputLimit, ..) => failed = true
      BoundedBindingRowsComplete(_, ..) => fail("short input completed")
      _ => fail("short input had another outcome")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected projection admits its exact input boundary" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    select=true,
    input_limits=Some({
      max_nodes: 16,
      max_text_bytes: 22,
      max_depth: 3,
      max_work: 38,
    }),
  )
  let mut completed : CompletedOutput? = None
  let mut advances = 0
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("exact input boundary failed")
    }
  }
  guard completed is Some(output) else { fail("projection did not complete") }
  assert_eq(completed_row_count(output), 2)
  assert_eq(completed_column_count(output), 2)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected take validates the whole input before offset" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]},{\"id\":3,\"left\":[5,6],\"right\":[7,8]}]",
    take=true,
  )
  let mut advances = 0
  let mut completed : CompletedOutput? = None
  while completed is None {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("unexpected take failure")
      BoundedBindingRowsStopped(_, ..) => fail("unexpected take stop")
    }
  }
  assert_true(advances > 20)
  let output = completed.unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_eq(completed_column_count(output), 3)
  assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected take rejects input beyond its output range" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]},{\"id\":3,\"left\":[5,6],\"right\":[7,8]}]",
    take=true,
    input_limits=Some({
      max_nodes: 16,
      max_text_bytes: 33,
      max_depth: 3,
      max_work: 57,
    }),
  )
  let mut failed = false
  while !failed {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(InputLimit, ..) => failed = true
      BoundedBindingRowsComplete(_, ..) => fail("undemanded output hid input")
      _ => fail("short take input had another outcome")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded selected take cancels before its output is public" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
    take=true,
  )
  for _ in 0..<12 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "bounded selected take has an exact control-work boundary" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Two whole-input passes, three schema names, then one three-field row.
  // The schema names contain 2 + 4 + 5 UTF-8 bytes.
  let (_, accepted, _) = bounded_binding_rows_fixture(
    rows,
    take=true,
    max_work=22,
  )
  let mut complete = false
  while !complete {
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 1)
        complete = true
      }
      _ => fail("exact take work failed")
    }
  }
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())

  let (_, rejected, input) = bounded_binding_rows_fixture(
    rows,
    take=true,
    max_work=21,
  )
  let mut failed = false
  while !failed {
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      BoundedBindingRowsComplete(_, ..) => fail("short take work completed")
      _ => fail("short take work had another outcome")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
}

///|
test "bounded selected take admits exact unkeyed workspace" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Four three-column metadata views persist. One output row and its
  // checked values overlap them, so the workspace peak is 12 + 3 + 3.
  let (_, accepted, input) = bounded_binding_rows_fixture(
    rows,
    take=true,
    max_entries=18,
  )
  let mut completed = false
  while !completed {
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 1)
        completed = true
      }
      _ => fail("exact unkeyed take workspace failed")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())

  let (_, rejected, input) = bounded_binding_rows_fixture(
    rows,
    take=true,
    max_entries=17,
  )
  let mut failed = false
  while !failed {
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      BoundedBindingRowsComplete(_, ..) =>
        fail("one-short unkeyed take workspace completed")
      _ => fail("one-short unkeyed take workspace had another outcome")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
}

///|
test "bounded selected take admits exact key-completion work" {
  // Control: input 6, sort names 4, rows 3, term 2, sort polls 15,
  // comparisons 3, sorted rows 9, output names 4, copied row 3.
  let (execution, input) = bounded_binding_rows_keyed_take_fixture(49)
  let mut completed = false
  while !completed {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, work~, ..) => {
        assert_eq(completed_row_count(output), 1)
        assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
        assert_eq(work, 52L)
        completed = true
      }
      _ => fail("exact key-completion work failed")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())

  let (rejected, input) = bounded_binding_rows_keyed_take_fixture(48)
  let mut failed = false
  while !failed {
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      BoundedBindingRowsComplete(_, ..) =>
        fail("one-short key-completion work completed")
      _ => fail("one-short key-completion work had another outcome")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
}

///|
test "bounded selected take bounds key-completion workspace and output overlap" {
  // Metadata 9 and sort indices 6 overlap. After sorting, retained indices 3
  // overlap both output-row slots and both checked-value slots: peak 16.
  let (execution, input) = bounded_binding_rows_keyed_take_fixture(
    100000,
    max_entries=16,
  )
  let mut completed = false
  while !completed {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 1)
        completed = true
      }
      _ => fail("key-completion workspace failed")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())

  let (rejected, input) = bounded_binding_rows_keyed_take_fixture(
    100000,
    max_entries=15,
  )
  let mut failed = false
  while !failed {
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => failed = true
      BoundedBindingRowsComplete(_, ..) =>
        fail("one-short key-completion workspace completed")
      _ => fail("one-short key-completion workspace had another outcome")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
}

///|
test "bounded selected take with offset beyond input completes empty" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]}]",
    take=true,
  )
  let mut completed : CompletedOutput? = None
  while completed is None {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("empty take failed")
    }
  }
  assert_eq(completed_row_count(completed.unwrap()), 0)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "bounded binding input value admission has an exact boundary" {
  let rows = "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]"
  // Each row contributes one row node, one number node, two vector nodes,
  // and four vector components. Names contribute 2 + 4 + 5 UTF-8 bytes.
  let exact : ValueLimits = {
    max_nodes: 16,
    max_text_bytes: 22,
    max_depth: 3,
    max_work: 38,
  }
  let (_, accepted, _) = bounded_binding_rows_fixture(
    rows,
    input_limits=Some(exact),
  )
  let mut complete = false
  while !complete {
    match advance_bounded_binding_rows(accepted, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        complete = true
      }
      BoundedBindingRowsFailed(_, ..) => fail("exact input limit failed")
      BoundedBindingRowsStopped(_, ..) => fail("exact input limit stopped")
    }
  }
  assert_true(cleanup_bounded_binding_rows(accepted).unwrap())

  let (_, rejected, input) = bounded_binding_rows_fixture(
    rows,
    input_limits=Some({ ..exact, max_nodes: 15, }),
  )
  let mut failed = false
  while !failed {
    match advance_bounded_binding_rows(rejected, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(InputLimit, ..) => failed = true
      BoundedBindingRowsComplete(_, ..) => fail("short input limit completed")
      _ => fail("short input limit had another outcome")
    }
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(rejected).unwrap())
}

///|
test "bounded binding rows preserve authored binding dependencies" {
  let (execution, input) = bounded_binding_rows_ordered_fixture()
  let mut completed : CompletedOutput? = None
  while completed is None {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("unexpected failure")
      BoundedBindingRowsStopped(_, ..) => fail("unexpected stop")
    }
  }
  let output = completed.unwrap()
  assert_eq(completed_row_count(output), 2)
  assert_eq(
    Array::makei(4, column => completed_column_name(output, column).unwrap()),
    ["a", "b", "next", "old"],
  )
  assert_true(completed_cell(output, 0, 2) is Some(Number(1.0)))
  assert_true(completed_cell(output, 1, 2) is Some(Number(1.0)))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}
