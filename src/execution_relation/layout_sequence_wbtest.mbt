///|
test "layout sequences use the common routing and final consumer release loop" {
  let owner = row_owner(
    ",{\"derive\":{\"c\":\"a + 1\"},\"as\":\"augmented\"},{\"filter\":\"a > 10\"},{\"from\":\"augmented\",\"select\":[\"c\"]}",
  )
  let sequence = prepared_sequence(owner)
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let control = { remaining: 100000, max_frames: 100, }
    let wiring = prepare_wiring(owner, ["select_3"], control, {
      limit: 1000,
      live: 0,
      peak: 0,
    }).unwrap()
    // Legacy retained-entry ceiling, not a claim of actual buffer bytes.
    let workspace = { limit: 23, live: 0, peak: 0, }
    let store = table_store(wiring, workspace).unwrap()
    let physical = layout_allocation(100000, 100000, 100000)
    let output = row_output()
    let visited : Array[Int] = []
    let retention : Array[Bool] = []
    run_sequence_steps(
      sequence,
      store,
      control,
      fn(i) {
        visited.push(i)
        Ok(
          layout_relation(
            capture_values(owner, i, max_rows=2, run_limits().input_values).unwrap(),
            candidate,
          ),
        )
      },
      fn(i, kernel, input) {
        visited.push(i)
        if i == 3 {
          retention.push(store.tables[0] is None)
          retention.push(store.tables[1] is Some(_))
          retention.push(store.tables[2] is None)
        }
        match
          evaluate_layout_body(
            kernel,
            input,
            control,
            output,
            { limit: 100000, live: 0, peak: 0, },
            physical,
            None,
          ) {
          Ok(value) => Ok(value)
          Err(issue) => Err(Rows(i, issue))
        }
      },
    ).unwrap()
    assert_eq(visited, [0, 1, 2, 3])
    assert_eq(retention, [true, true, true])
    assert_eq(store.next, 4)
    assert_eq((workspace.live, workspace.peak), (9, 23))
    assert_true(store.tables[1] is None)
    let output = store.tables[3].unwrap().table
    assert_eq(output.names, ["c"])
    assert_true(layout_cell(output.storage, 0, 0) is Some(Number(2)))
    assert_true(layout_cell(output.storage, 1, 0) is Some(Number(1)))
    assert_true(physical_equal(output.owner, owner))
  }
}

///|
test "common layout loop stops at an unused failure and rejects owner substitution" {
  let owner = row_owner(
    ",{\"derive\":{\"unused\":\"1 / a\"}},{\"from\":\"seed\",\"select\":[\"b\"]}",
  )
  let sequence = prepared_sequence(owner)
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let control = { remaining: 100000, max_frames: 100, }
    let wiring = prepare_wiring(owner, ["select_2"], control, {
      limit: 1000,
      live: 0,
      peak: 0,
    }).unwrap()
    let store = table_store(wiring, { limit: 1000, live: 0, peak: 0, }).unwrap()
    let visited : Array[Int] = []
    let result = run_sequence_steps(
      sequence,
      store,
      control,
      fn(i) {
        visited.push(i)
        Ok(
          layout_relation(
            capture_values(owner, i, max_rows=2, run_limits().input_values).unwrap(),
            candidate,
          ),
        )
      },
      fn(i, kernel, input) {
        visited.push(i)
        match
          evaluate_layout_body(
            kernel,
            input,
            control,
            row_output(),
            { limit: 100000, live: 0, peak: 0, },
            layout_allocation(100000, 100000, 100000),
            None,
          ) {
          Ok(value) => Ok(value)
          Err(issue) => Err(Rows(i, issue))
        }
      },
    )
    assert_true(result is Err(Rows(1, Evaluation(1, 0, _))))
    assert_eq(visited, [0, 1])
    assert_eq(store.next, 1)
    assert_true(store.tables[1] is None)
    assert_true(store.tables[2] is None)
    let foreign = prepared_sequence(row_owner(""))
    assert_true(
      run_sequence_steps(
        foreign,
        store,
        control,
        fn(_i) {
          visited.push(-1)
          Err(InputSet)
        },
        fn(_i, _kernel, _input) {
          visited.push(-2)
          Err(InputSet)
        },
      )
      is Err(InputOwnership),
    )
    assert_eq(visited, [0, 1])
  }
}
