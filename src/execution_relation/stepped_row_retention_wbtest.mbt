///|
test "stepped row retention preserves literal nested value charges" {
  let text = String::make(130, 'a') + "😀"
  let expr = lowered("{\"literal\":{\"k\":[1,null],\"s\":\"" + text + "\"}}")
  guard @lower.expression_body(expr) is @lower.Literal(checked) else {
    fail("expected checked literal")
  }
  // Row, object, array, two array members, Text: six nodes. The field
  // names p/k/s use three bytes; 130 ASCII bytes plus one scalar use 134.
  let exact = {
    max_nodes: 6,
    max_text_bytes: 137,
    max_depth: 4,
    max_work: 143,
  }
  for
    limits in [
      exact,
      { ..exact, max_nodes: 5, },
      { ..exact, max_text_bytes: 136, },
      { ..exact, max_depth: 3, },
      { ..exact, max_work: 142, },
    ] {
    let output = value_budget(limits).unwrap()
    let workspace = row_workspace(4)
    let cursor = start_stepped_row_retention(
      [Captured(checked.value)],
      ["p"],
      output,
      workspace,
    ).unwrap()
    let mut terminal = false
    let mut succeeded = false
    for _ in 0..<100 {
      if !terminal {
        match advance_stepped_row_retention(cursor) {
          Ok(false) => ()
          Ok(true) => {
            terminal = true
            succeeded = true
          }
          Err(RowLimit) => terminal = true
          Err(_) => fail("unexpected row issue")
        }
      }
    }
    assert_true(terminal)
    assert_eq(succeeded, limits == exact)
    if succeeded {
      assert_eq((output.nodes, output.text, output.work), (6, 137, 143))
    }
    close_stepped_row_retention(cursor)
    close_stepped_row_retention(cursor)
    assert_eq(workspace.live, 0)
  }
}

///|
test "stepped row retention yields within long names and retains failure frames" {
  let name = String::make(4096, 'n')
  let output = value_budget({
    max_nodes: 2,
    max_text_bytes: 4096,
    max_depth: 2,
    max_work: 4098,
  }).unwrap()
  let workspace = row_workspace(2)
  let cursor = start_stepped_row_retention(
    [Number(1)],
    [name],
    output,
    workspace,
  ).unwrap()
  assert_eq(advance_stepped_row_retention(cursor).unwrap(), false)
  assert_eq(advance_stepped_row_retention(cursor).unwrap(), false)
  assert_eq(output.text, 64)
  assert_eq(workspace.live, 2)
  close_stepped_row_retention(cursor)
  assert_eq(workspace.live, 0)
  assert_eq(output.work, 65)
  assert_true(advance_stepped_row_retention(cursor) is Err(InvalidRows))
  // A handle and two overlapping nested frames are necessary. Reject the
  // second frame, retain the first one, and close without rolling work back.
  let expr = lowered("{\"literal\":[1,2]}")
  guard @lower.expression_body(expr) is @lower.Literal(checked) else {
    fail("expected checked literal")
  }
  for (slots, succeeds) in [(3, true), (2, false)] {
    let workspace = row_workspace(slots)
    let output = value_budget({
      max_nodes: 4,
      max_text_bytes: 1,
      max_depth: 3,
      max_work: 5,
    }).unwrap()
    let cursor = start_stepped_row_retention(
      [Captured(checked.value)],
      ["p"],
      output,
      workspace,
    ).unwrap()
    let mut terminal = false
    for _ in 0..<40 {
      if !terminal {
        match advance_stepped_row_retention(cursor) {
          Ok(false) => ()
          Ok(true) => {
            assert_true(succeeds)
            terminal = true
          }
          Err(RowLimit) => {
            assert_false(succeeds)
            terminal = true
          }
          Err(_) => fail("unexpected row issue")
        }
      }
    }
    assert_true(terminal)
    let spent = output.work
    close_stepped_row_retention(cursor)
    assert_eq(output.work, spent)
    assert_eq(workspace.live, 0)
  }
}

///|
fn aggregate_output_text_owner(body : String) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("group"),
        @contract.primitive(StringType, nullable=true),
      ),
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("amount"),
        @contract.primitive(NumberType, nullable=true),
      ),
      (
        @schema.Unqualified("status"),
        @contract.primitive(StringType, nullable=true),
      ),
    ],
    max_fields=4,
    max_name_bytes=19,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  sort_input_owner(@pipeline.KeyedInput(key), "[" + body + "]")
}

///|
fn aggregate_output_text_input(owner : @lower.BoundPrepared) -> Table {
  table_from_capture(
    capture_input(
      owner,
      0,
      [
        input_cursor(
          "{\"amount\":7,\"group\":\"" +
          String::make(4096, 'g') +
          "\",\"id\":1,\"status\":\"open\"}",
        ),
      ],
      max_rows=1,
      run_limits().input_values,
    ).unwrap(),
  )
}

///|
test "analytic and pivot keep independent exact long output limits" {
  let bodies = [
    "{\"analytic\":{\"partition_by\":[\"group\"],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
    "{\"pivot\":{\"index\":[\"group\"],\"column\":\"status\",\"values\":[\"open\"],\"value\":\"amount\",\"aggregate\":\"count\"}}",
  ]
  for kind, body in bodies {
    let owner = aggregate_output_text_owner(body)
    let input = aggregate_output_text_input(owner)
    // Analytic: row plus five cells, 27 name bytes, 4,096 group bytes,
    // and four status bytes. Pivot: row plus two cells and nine name bytes.
    let exact = if kind == 0 {
      { max_nodes: 6, max_text_bytes: 4127, max_depth: 2, max_work: 4133, }
    } else {
      { max_nodes: 3, max_text_bytes: 4105, max_depth: 2, max_work: 4108, }
    }
    for
      limits in [
        exact,
        { ..exact, max_nodes: exact.max_nodes - 1, },
        { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_depth: 1, },
      ] {
      let output = value_budget(limits).unwrap()
      let result = evaluate_rows(
        row_kernel(owner, 0),
        input,
        1,
        { remaining: 100000, max_frames: 100, },
        output,
      )
      if limits == exact {
        let table = result.unwrap()
        assert_eq(table.rows.length(), 1)
        if kind == 0 {
          assert_eq(table.names, ["amount", "group", "id", "position", "status"])
          assert_true(table.rows[0][0] is Number(7))
          assert_true(table.rows[0][2] is Number(1))
          assert_true(table.rows[0][3] is Number(1))
          assert_true(table.rows[0][4] is Text("open"))
        } else {
          assert_eq(table.names, ["group", "open"])
          assert_true(table.rows[0][1] is Number(1))
        }
        assert_eq(
          (output.nodes, output.text, output.work),
          (exact.max_nodes, exact.max_text_bytes, exact.max_work),
        )
      } else {
        assert_true(result is Err(RowLimit))
      }
    }
  }
}

///|
test "group analytic and pivot yield before accepting long copied output" {
  let bodies = [
    "{\"group\":{\"by\":[\"group\"],\"aggregates\":{\"hits\":{\"fn\":\"max\",\"field\":\"amount\"}}}}",
    "{\"analytic\":{\"partition_by\":[\"group\"],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
    "{\"pivot\":{\"index\":[\"group\"],\"column\":\"status\",\"values\":[\"open\"],\"value\":\"amount\",\"aggregate\":\"count\"}}",
  ]
  for kind, body in bodies {
    let owner = aggregate_output_text_owner(body)
    let input = aggregate_output_text_input(owner)
    let kernel = row_kernel(owner, 0)
    let workspace = row_workspace(10000)
    let output = row_output()
    let control = { remaining: 100000, max_frames: 100, }
    let rows : Array[Array[Value]] = []
    let group = if kind == 0 {
      Some(
        start_bounded_group(
          @lower.kernel_group(kernel).unwrap(),
          input,
          1,
          control,
          output,
          workspace,
          None,
          (row, _, _, _) => {
            rows.push(row)
            Ok(())
          },
          [],
          run_limits().input_values,
          None,
          step=0,
        ),
      )
    } else {
      None
    }
    let analytic = if kind == 1 {
      Some(
        start_analytic_evaluation(
          @lower.kernel_analytic(kernel).unwrap(),
          input,
          1,
          control,
          output,
          workspace,
          None,
          [],
          None,
          run_limits().input_values,
          None,
          0,
          (row, _) => {
            rows.push(row)
            Ok(())
          },
        ),
      )
    } else {
      None
    }
    let pivot = if kind == 2 {
      Some(
        start_pivot_evaluation(
          kernel,
          input,
          1,
          control,
          output,
          workspace,
          None,
          0,
          (row, _) => {
            rows.push(row)
            Ok(())
          },
        ).unwrap(),
      )
    } else {
      None
    }
    let mut found = false
    for _ in 0..<20000 {
      if !found {
        let result = if group is Some(state) {
          advance_bounded_group(state)
        } else if analytic is Some(state) {
          advance_analytic_evaluation(state)
        } else {
          advance_pivot_evaluation(pivot.unwrap())
        }
        assert_true(result is Ok(None))
        found = if group is Some(state) {
          state.row_retention is Some(_)
        } else if analytic is Some(state) {
          state.row_retention is Some(_)
        } else {
          pivot.unwrap().row_retention is Some(_)
        }
      }
    }
    assert_true(found)
    assert_eq(rows.length(), 0)
    assert_eq(output.nodes, 1)
    let before = workspace.live
    // Resume the enclosing owner, not its cursor directly. Stop after the
    // first Text chunk, while the copied 4,096-byte value is still private.
    for _ in 0..<100 {
      if output.text < 64 {
        let result = if group is Some(state) {
          advance_bounded_group(state)
        } else if analytic is Some(state) {
          advance_analytic_evaluation(state)
        } else {
          advance_pivot_evaluation(pivot.unwrap())
        }
        assert_true(result is Ok(None))
      }
    }
    assert_true(output.text >= 64 && output.text < 4096)
    assert_eq(rows.length(), 0)
    assert_eq(workspace.live, before + 1)
    let spent = output.work
    if group is Some(state) {
      close_bounded_group(state)
      assert_true(state.row_retention is None)
    }
    if analytic is Some(state) {
      close_analytic_evaluation(state)
      assert_true(state.row_retention is None)
    }
    if pivot is Some(state) {
      close_pivot_evaluation(state)
      assert_true(state.row_retention is None)
    }
    assert_eq(workspace.live, before - 1)
    assert_eq(output.work, spent)
    assert_eq(rows.length(), 0)
    assert_true(input.rows[0][1] is Text(text) && text.length() == 4096)
  }
}

///|
test "wide group output is constructed one cell at a time with exact charges" {
  let owner = aggregate_output_text_owner(
    "{\"group\":{\"by\":[\"group\"],\"aggregates\":{" +
    "\"a0\":{\"fn\":\"max\",\"field\":\"amount\"}," +
    "\"a1\":{\"fn\":\"max\",\"field\":\"amount\"}," +
    "\"a2\":{\"fn\":\"max\",\"field\":\"amount\"}," +
    "\"a3\":{\"fn\":\"max\",\"field\":\"amount\"}," +
    "\"a4\":{\"fn\":\"max\",\"field\":\"amount\"}," +
    "\"a5\":{\"fn\":\"max\",\"field\":\"amount\"}," +
    "\"a6\":{\"fn\":\"max\",\"field\":\"amount\"}," +
    "\"a7\":{\"fn\":\"max\",\"field\":\"amount\"}," +
    "\"a8\":{\"fn\":\"max\",\"field\":\"amount\"}}}}",
  )
  let input = aggregate_output_text_input(owner)
  let group = @lower.kernel_group(row_kernel(owner, 0)).unwrap()
  // One row plus ten cells, 18 bytes of aggregate names, five of the group
  // name, and 4,096 of its value. No expected limit comes from a success run.
  let exact = {
    max_nodes: 11,
    max_text_bytes: 4119,
    max_depth: 2,
    max_work: 4130,
  }
  for
    limits in [
      exact,
      { ..exact, max_nodes: 10, },
      { ..exact, max_text_bytes: 4118, },
      { ..exact, max_work: 4129, },
      { ..exact, max_depth: 1, },
    ] {
    let output = value_budget(limits).unwrap()
    let workspace = row_workspace(10000)
    let rows : Array[Array[Value]] = []
    let state = start_bounded_group(
      group,
      input,
      1,
      { remaining: 100000, max_frames: 100, },
      output,
      workspace,
      None,
      (row, _, _, _) => {
        rows.push(row)
        Ok(())
      },
      [],
      run_limits().input_values,
      None,
      step=0,
    )
    let mut terminal = false
    let mut success = false
    let mut construction_steps = 0
    for _ in 0..<20000 {
      if !terminal {
        let before = state.output_column
        let phase = state.phase
        match advance_bounded_group(state) {
          Ok(None) => ()
          Ok(Some(names)) => {
            assert_eq(names, [
              "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "group",
            ])
            terminal = true
            success = true
          }
          Err(RowLimit) => terminal = true
          Err(_) => fail("unexpected group failure")
        }
        if phase == 11 && before < 10 {
          assert_eq(state.output_column, before + 1)
          construction_steps += 1
        }
      }
    }
    assert_true(terminal)
    assert_eq(success, limits == exact)
    assert_eq(construction_steps, 10)
    if success {
      assert_eq(rows.length(), 1)
      for index in 0..<9 {
        assert_true(rows[0][index] is Number(7))
      }
      assert_true(rows[0][9] is Text(text) && text == String::make(4096, 'g'))
      assert_eq((output.nodes, output.text, output.work), (11, 4119, 4130))
    } else {
      assert_eq(rows.length(), 0)
      assert_true(state.row_retention is None)
      assert_eq(state.output_row.length(), 0)
    }
  }
}
