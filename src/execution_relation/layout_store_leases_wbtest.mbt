///|
test "failed invocation releases retained and uncommitted column owners even with exhausted work" {
  let owner = row_owner(",{\"select\":[\"a\"]}")
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0", "select_1"],
    100000,
    10000,
  ).unwrap()
  for fail_commit in [false, true] {
    let ledger = layout_ledger(2, 36, 100)
    let physical = {
      ..layout_allocation(100000, 100000, 100000),
      ledger: Some(ledger),
    }
    let control = { remaining: 100000, max_frames: 100, }
    let released : Array[String] = []
    let invocation = prepare_sequence_with_importers(
      generated.contracts,
      generated.sequence,
      [],
      generated.retained_ids,
      run_limits(),
      control,
      fn(_captured) { Err(InvalidRows) },
      fn(_bound, _id, _output) { Err(InvalidRows) },
      produced=[],
      fragments=Some(generated.contexts),
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
      release_table=fn(table : LayoutRelation) {
        released.push(table.id)
        release_layout_columns(table.storage)
      },
    ).unwrap()
    let result = run_sequence_with_backend(
      invocation,
      fn(captured) {
        let builder = match
          layout_column_builder(
            captured.schema,
            ["a", "b"],
            2,
            TypedColumns,
            physical,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        for row in captured.rows {
          match append_layout_row(builder, row.map(capture)) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
        }
        match finish_layout_columns(builder) {
          Ok(storage) =>
            Ok({
              candidate: TypedColumns,
              owner,
              id: "values_0",
              names: ["a", "b"],
              storage,
            })
          Err(issue) => Err(issue)
        }
      },
      fn(kernel, input, logical) {
        if !fail_commit {
          control.remaining = 0
          return Err(InvalidRows)
        }
        let result = evaluate_layout_kernel(
          kernel,
          input,
          2,
          control,
          invocation.output_budget,
          { limit: 100000, live: 0, peak: 0, },
          physical,
          logical,
        )
        // The operation succeeds, but its output cannot be committed.
        control.remaining = 0
        result
      },
    )
    if fail_commit {
      assert_true(result is Err(Store(Limit)))
      assert_eq(released, ["select_1", "values_0"])
    } else {
      assert_true(result is Err(Rows(1, InvalidRows)))
      assert_eq(released, ["values_0"])
    }
    assert_eq(control.remaining, 0)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    assert_eq(ledger.bytes.peak, 36)
    for table in invocation.store.tables {
      assert_true(table is None)
    }
    // Repeated cleanup is harmless and cannot double-release leases.
    let count = released.length()
    clear_table_store(invocation.store)
    assert_eq(released.length(), count)
  }
}

///|
test "store final consumers release owned columns without invalidating retained branches" {
  let owner = row_owner(
    ",{\"select\":[\"a\"]},{\"from\":\"seed\",\"select\":[\"b\"]}",
  )
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  let ledger = layout_ledger(2, 36, 100)
  let physical = {
    ..layout_allocation(100000, 100000, 100000),
    ledger: Some(ledger),
  }
  let builder = layout_column_builder(
    captured.schema,
    ["a", "b"],
    2,
    TypedColumns,
    physical,
  ).unwrap()
  for row in captured.rows {
    append_layout_row(builder, row.map(capture)).unwrap()
  }
  let source : LayoutRelation = {
    candidate: TypedColumns,
    owner,
    id: "values_0",
    names: ["a", "b"],
    storage: finish_layout_columns(builder).unwrap(),
  }
  let control = { remaining: 100000, max_frames: 100, }
  let wiring = prepare_wiring(owner, ["select_1", "select_2"], control, {
    limit: 10000,
    live: 0,
    peak: 0,
  }).unwrap()
  let released : Array[String] = []
  let store = table_store(wiring, { limit: 10000, live: 0, peak: 0, }, release=fn(
    table : LayoutRelation,
  ) {
    released.push(table.id)
    release_layout_columns(table.storage)
  }).unwrap()
  let live_before : Array[Int] = []
  run_sequence_steps(
    prepared_sequence(owner),
    store,
    control,
    fn(_i) { Ok(source) },
    fn(i, kernel, input) {
      live_before.push(ledger.bytes.live)
      match
        evaluate_layout_kernel(
          kernel,
          input,
          2,
          control,
          row_output(),
          { limit: 100000, live: 0, peak: 0, },
          physical,
          None,
        ) {
        Ok(value) => Ok(value)
        Err(issue) => Err(Rows(i, issue))
      }
    },
  ).unwrap()
  assert_eq(live_before, [36, 36])
  assert_eq(released, ["values_0"])
  assert_true(layout_cell(source.storage, 0, 0) is None)
  assert_eq(ledger.bytes.live, 36)
  let a = store.tables[1].unwrap().table
  let b = store.tables[2].unwrap().table
  assert_true(layout_cell(a.storage, 0, 0) is Some(Number(1)))
  assert_true(layout_cell(b.storage, 0, 0) is Some(Number(0)))
  drop_table(store, 1)
  assert_eq(ledger.bytes.live, 18)
  assert_true(layout_cell(a.storage, 0, 0) is None)
  assert_true(layout_cell(b.storage, 0, 0) is Some(Number(0)))
  drop_table(store, 1)
  assert_eq(released, ["values_0", "select_1"])
  drop_table(store, 2)
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  assert_eq(ledger.bytes.peak, 36)
}

///|
test "take completion temporary releases its buffer ownership after selection" {
  let owner = take_key_owner("[{\"take\":3},{\"select\":[\"s\"]},{\"take\":1}]")
  let captured = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":3,\"s\":\"three\"}"),
      input_cursor("{\"n\":1,\"s\":\"one\"}"),
      input_cursor("{\"n\":2,\"s\":\"two\"}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let ledger = layout_ledger(10, 27, 100)
  let physical = {
    ..layout_allocation(100000, 100000, 100000),
    ledger: Some(ledger),
  }
  let builder = layout_column_builder(
    captured.schema,
    ["n", "s"],
    3,
    TypedColumns,
    physical,
  ).unwrap()
  for row in captured.rows {
    append_layout_row(builder, row.map(capture)).unwrap()
  }
  let source : LayoutRelation = {
    candidate: TypedColumns,
    owner,
    id: "input_0",
    names: ["n", "s"],
    storage: finish_layout_columns(builder).unwrap(),
  }
  let control = { remaining: 100000, max_frames: 100, }
  let wiring = prepare_wiring(owner, ["limit_2"], control, {
    limit: 10000,
    live: 0,
    peak: 0,
  }).unwrap()
  let store = table_store(wiring, { limit: 10000, live: 0, peak: 0, }, release=fn(
    table : LayoutRelation,
  ) {
    release_layout_columns(table.storage)
  }).unwrap()
  install_table_input(store, 0, source, control).unwrap()
  run_sequence_steps(
    prepared_sequence(owner),
    store,
    control,
    fn(_i) { Err(InputSet) },
    fn(i, kernel, input) {
      match
        evaluate_layout_kernel(
          kernel,
          input,
          3,
          control,
          row_output(),
          { limit: 100000, live: 0, peak: 0, },
          physical,
          None,
        ) {
        Ok(value) => Ok(value)
        Err(issue) => Err(Rows(i, issue))
      }
    },
  ).unwrap()
  let output = store.tables[3].unwrap().table
  assert_true(layout_cell(output.storage, 0, 0) is Some(Text("one")))
  // Dropped numeric column has no remaining temporary owner.
  assert_eq(ledger.bytes.live, 0)
  // One selected row still holds the complete three-value text column.
  assert_eq(ledger.slots.live, 3)
  drop_table(store, 3)
  assert_eq(ledger.slots.live, 0)
}
