///|
fn bounded_binding_rows_source(
  rows : String,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"left\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false},\"right\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}},\"rows\":" +
    rows +
    "},\"as\":\"seed\"}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
  ).unwrap()
  (owner, completed_output(completed, @pipeline.Step(0)).unwrap())
}

///|
fn bounded_binding_rows_receiver(
  source_owner : @lower.BoundPrepared,
  following_step? : Bool = false,
  filter? : Bool = false,
  select? : Bool = false,
  take? : Bool = false,
  sort? : Bool = false,
  sort_empty? : Bool = false,
) -> @lower.BoundPrepared {
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[" +
      (if take {
        "{\"take\":{\"count\":1,\"offset\":1},\"from\":\"rows\",\"as\":\"derived\"}"
      } else if sort || sort_empty {
        "{\"sort\":" +
        (if sort_empty { "[]" } else { "[{\"id\":\"desc\"}]" }) +
        ",\"from\":\"rows\",\"as\":\"derived\"}"
      } else if select {
        "{\"select\":[\"right\",\"id\"],\"from\":\"rows\",\"as\":\"derived\"}"
      } else if filter {
        "{\"filter\":\"id > 1\",\"from\":\"rows\",\"as\":\"derived\"}"
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
  select? : Bool = false,
  take? : Bool = false,
  sort? : Bool = false,
  sort_empty? : Bool = false,
  input_limits? : ValueLimits? = None,
  max_work? : Int = 100000,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  let (source_owner, source) = bounded_binding_rows_source(rows)
  let receiver = bounded_binding_rows_receiver(
    source_owner,
    following_step~,
    filter~,
    select~,
    take~,
    sort~,
    sort_empty~,
  )
  let sequence = prepared_sequence(receiver)
  let first = @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    if select || take || sort || sort_empty {
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
    10000,
    10000,
  ).unwrap()
  (control, execution, input)
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
