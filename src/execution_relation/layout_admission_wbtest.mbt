///|
test "layout imports cannot bypass key or owner admission before physical conversion" {
  let owner = take_key_owner("[{\"take\":3},{\"select\":[\"s\"]},{\"take\":1}]")
  let sequence = prepared_sequence(owner)
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    for duplicate in [true, false] {
      let raw = if duplicate {
        [
          input_cursor("{\"n\":1,\"s\":\"one\"}"),
          input_cursor("{\"n\":1,\"s\":\"duplicate\"}"),
        ]
      } else {
        [
          input_cursor("{\"n\":3,\"s\":\"three\"}"),
          input_cursor("{\"n\":1,\"s\":\"one\"}"),
          input_cursor("{\"n\":2,\"s\":\"two\"}"),
        ]
      }
      let input = capture_input(
        owner,
        0,
        raw,
        max_rows=3,
        run_limits().input_values,
      ).unwrap()
      let control = { remaining: 100000, max_frames: 100, }
      let calls : Array[Int] = []
      let invocation = prepare_sequence_with_importers(
        registered_relation_contracts(),
        sequence,
        [input],
        ["limit_2"],
        run_limits(),
        control,
        fn(captured) {
          calls.push(0)
          Ok(layout_relation(captured, candidate))
        },
        fn(_bound, _id, _output) {
          calls.push(1)
          Err(InvalidRows)
        },
        produced=[],
        fragments=None,
        ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
      )
      if duplicate {
        assert_true(invocation is Err(InputKey(0, _)))
        assert_eq(calls, [])
      } else {
        let invocation = invocation.unwrap()
        assert_eq(calls, [0])
        assert_eq(invocation.input_rows, 3)
        let physical = layout_allocation(100000, 100000, 100000)
        run_sequence_steps(
          sequence,
          invocation.store,
          control,
          fn(_i) { Err(InputSet) },
          fn(i, kernel, input) {
            match
              evaluate_layout_kernel(
                kernel,
                input,
                3,
                control,
                invocation.output_budget,
                { limit: 100000, live: 0, peak: 0, },
                physical,
                None,
              ) {
              Ok(v) => Ok(v)
              Err(e) => Err(Rows(i, e))
            }
          },
        ).unwrap()
        let output = invocation.store.tables[3].unwrap().table
        assert_eq(output.names, ["s"])
        assert_eq(output.storage.count, 1)
        assert_true(layout_cell(output.storage, 0, 0) is Some(Text("one")))
      }
      let foreign = take_key_owner("[{\"take\":1}]")
      calls.clear()
      let rejected = prepare_sequence_with_importers(
        registered_relation_contracts(),
        prepared_sequence(foreign),
        [input],
        ["limit_0"],
        run_limits(),
        { remaining: 100000, max_frames: 100, },
        fn(captured) {
          calls.push(0)
          Ok(layout_relation(captured, candidate))
        },
        fn(_bound, _id, _output) {
          calls.push(1)
          Err(InvalidRows)
        },
        produced=[],
        fragments=None,
        ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
      )
      assert_true(rejected is Err(InputOwnership))
      assert_eq(calls, [])
    }
  }
}

///|
test "later values cannot reset the invocation row allowance" {
  let owner = row_owner(
    ",{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":2},{\"a\":3}]},\"as\":\"later\"}",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_1"],
    100000,
    10000,
  ).unwrap()
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let conversions : Array[Int] = []
    let invocation = prepare_sequence_with_importers(
      generated.contracts,
      generated.sequence,
      [],
      generated.retained_ids,
      { ..run_limits(), max_rows: 3, },
      { remaining: 100000, max_frames: 100, },
      fn(captured) { Ok(layout_relation(captured, candidate)) },
      fn(_bound, _id, _output) { Err(InvalidRows) },
      produced=[],
      fragments=Some(generated.contexts),
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    ).unwrap()
    let result = run_sequence_with_backend(
      invocation,
      fn(captured) {
        conversions.push(captured.rows.length())
        Ok(layout_relation(captured, candidate))
      },
      fn(_kernel, _input, _logical) { Err(InvalidRows) },
    )
    assert_true(result is Err(Capture(1, _)))
    assert_eq(conversions, [2])
    assert_eq(invocation.store.next, 1)
    assert_true(invocation.store.tables[1] is None)
  }
}

///|
test "generated layout execution shares values capture and cumulative limits" {
  let owner = row_owner(
    ",{\"sort\":[{\"a\":\"asc\"}]},{\"select\":[\"a\"]},{\"take\":1}",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["limit_3"],
    100000,
    10000,
  ).unwrap()
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    for cap in [1, 2] {
      let limits = { ..run_limits(), max_rows: cap, }
      let control = { remaining: 100000, max_frames: 100, }
      let conversions : Array[Int] = []
      let invocation = prepare_sequence_with_importers(
        generated.contracts,
        generated.sequence,
        [],
        generated.retained_ids,
        limits,
        control,
        fn(captured) {
          conversions.push(-1)
          Ok(layout_relation(captured, candidate))
        },
        fn(_bound, _id, _output) { Err(InvalidRows) },
        produced=[],
        fragments=Some(generated.contexts),
        ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
      ).unwrap()
      assert_eq(conversions, [])
      assert_eq(invocation.input_rows, 0)
      let physical = layout_allocation(100000, 100000, 100000)
      let result = run_sequence_with_backend(
        invocation,
        fn(captured) {
          conversions.push(0)
          Ok(layout_relation(captured, candidate))
        },
        fn(kernel, input, logical) {
          evaluate_layout_kernel(
            kernel,
            input,
            limits.max_rows,
            control,
            invocation.output_budget,
            { limit: limits.operation_entries, live: 0, peak: 0, },
            physical,
            logical,
          )
        },
      )
      if cap == 1 {
        assert_true(result is Err(Capture(0, _)))
        assert_eq(conversions, [])
        assert_eq(invocation.store.next, 0)
      } else {
        result.unwrap()
        assert_eq(conversions, [0])
        let output = invocation.store.tables[3].unwrap().table
        assert_eq(output.storage.count, 1)
        assert_true(layout_cell(output.storage, 0, 0) is Some(Number(0)))
        assert_true(invocation.input_budget.nodes > 0)
        assert_true(invocation.output_budget.nodes > 0)
        assert_eq(invocation.store.next, 4)
      }
    }
  }
}
