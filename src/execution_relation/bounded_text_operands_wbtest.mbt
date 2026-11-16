///|
priv struct TextOperandFixture {
  execution : BoundedJoinExecution
  source : BoundedComparisonTextSource
  cursor : BoundedRowComparison
  control : ControlBudget
  workspace : RowWorkspace
  left_calls : Ref[Int]
  right_calls : Ref[Int]
  fallback_calls : Ref[Int]
}

///|
fn text_operand_fixture(
  left : String,
  right : String,
  maximum? : Int = 13,
  work? : Int = 100000,
  growth? : WorkspaceGrowth? = None,
  live? : Ref[Bool]? = None,
  supplied_right? : Bool = false,
) -> TextOperandFixture raise {
  let left_calls = Ref(0)
  let right_calls = Ref(0)
  let (_, execution, _) = bounded_join_fixture(
    left_rows="[{\"id\":\"" + left + "\",\"v\":\"version-a\"}]",
    right_rows="[{\"id\":\"" + right + "\",\"v\":\"version-b\"}]",
    key_type="string",
    value_type="string",
    supplied_right~,
    left_current=Some(() => {
      left_calls.val += 1
      live.map(value => value.val).unwrap_or(true)
    }),
    right_current=Some(() => {
      right_calls.val += 1
      true
    }),
  )
  let workspace = { ..row_workspace(maximum), growth, }
  // One optional source root, then its header and three borrowed fields.
  assert_true(reserve_slots(workspace, 1))
  let source = prepare_bounded_comparison_text_source(
      execution.state.left,
      execution.state.right,
      [(0, 0)],
      workspace,
    )
    .unwrap()
    .unwrap()
  left_calls.val = 0
  right_calls.val = 0
  {
    execution,
    source,
    workspace,
    left_calls,
    right_calls,
    cursor: reference_pair_cursor(),
    control: { remaining: work, max_frames: 10, },
    fallback_calls: Ref(0),
  }
}

///|
fn step_text_operand_fixture(
  fixture : TextOperandFixture,
  fast? : Bool = true,
  descending? : Bool = false,
  terms? : Int = 1,
) -> Result[Int?, OrderingIssue] {
  bounded_row_comparison_step_with(
    fixture.cursor,
    Array::makei(terms, column => { column, descending, nulls_first: false, }),
    fixture.control,
    (row, key) => {
      fixture.fallback_calls.val += 1
      let columns = fixture.source.keys[key]
      if row >= 0 {
        bounded_binding_input_cell(fixture.source.left, row, columns.0)
      } else {
        bounded_binding_input_cell(fixture.source.right, -1 - row, columns.1)
      }
    },
    0,
    -1,
    terms,
    workspace=Some(fixture.workspace),
    text_source=if fast { Some(fixture.source) } else { None },
  )
}

///|
fn finish_text_operand_fixture(
  fixture : TextOperandFixture,
  fast? : Bool = true,
  descending? : Bool = false,
  terms? : Int = 1,
) -> (Result[Int, OrderingIssue], Int) raise {
  for steps in 1..<20000 {
    match step_text_operand_fixture(fixture, fast~, descending~, terms~) {
      Ok(Some(value)) => return (Ok(value), steps)
      Ok(None) => ()
      Err(issue) => return (Err(issue), steps)
    }
  }
  fail("finite Text operand fixture did not finish")
}

///|
fn close_text_operand_fixture(fixture : TextOperandFixture) -> Unit raise {
  reset_bounded_row_comparison(fixture.cursor)
  assert_eq(fixture.workspace.live, 5)
  release_slots(fixture.workspace, 5)
  assert_true(@bounded.request_cancel(fixture.execution.state.pairs.engine))
  assert_true(
    advance_bounded_join(fixture.execution, 1).unwrap()
    is BoundedJoinStopped(_, ..),
  )
  assert_true(cleanup_bounded_join(fixture.execution).unwrap())
  assert_eq(fixture.execution.state.workspace.live, 0)
}

///|
test "Text operands fetch once per term independent of common prefix length" {
  let reads = []
  for length in [1, 64, 1024] {
    let prefix = "x".repeat(length)
    let fast = text_operand_fixture(prefix + "a", prefix + "b")
    let slow = text_operand_fixture(prefix + "a", prefix + "b")
    let (actual, fast_steps) = finish_text_operand_fixture(fast)
    let (expected, slow_steps) = finish_text_operand_fixture(slow, fast=false)
    assert_true(actual is Ok(-1))
    assert_true(expected is Ok(-1))
    assert_eq(fast_steps, slow_steps)
    assert_eq(fast.control.remaining, slow.control.remaining)
    assert_eq(100000 - fast.control.remaining, 1 + 2 * (length + 1))
    assert_eq(fast.fallback_calls.val, 0)
    // Each real getter invokes this exact producer's current predicate once.
    // Subtract the one explicit post-funding fence on each input, rather than
    // conflating that fresh check with another cell fetch.
    reads.push((fast.left_calls.val - 1, fast.right_calls.val - 1))
    assert_eq(slow.left_calls.val, slow_steps)
    assert_eq(slow.right_calls.val, slow_steps)
    assert_eq(slow.fallback_calls.val, 2 * slow_steps)
    assert_eq(fast.workspace.peak, 13)
    assert_true(fast.cursor.tree is NoRowComparison)
    close_text_operand_fixture(fast)
    close_text_operand_fixture(slow)
  }
  assert_eq(reads, [(1, 1), (1, 1), (1, 1)])
}

///|
test "Text operands preserve empty equal Unicode descending and exact UTF8 work" {
  for
    (left, right, expected, bytes) in [
      ("", "", 0, 0),
      ("", "a", -1, 1),
      ("a", "", 1, 1),
      ("same", "same", 0, 8),
      ("é😀a", "é😀b", -1, 14),
      ("😀", "\ue000", -1, 7),
      ("z", "a-long-tail", 1, 12),
    ] {
    for descending in [false, true] {
      let fast = text_operand_fixture(left, right, work=1 + bytes)
      let slow = text_operand_fixture(left, right, work=1 + bytes)
      let (actual, steps) = finish_text_operand_fixture(fast, descending~)
      let (original, original_steps) = finish_text_operand_fixture(
        slow,
        fast=false,
        descending~,
      )
      let expected = if descending { -expected } else { expected }
      assert_true(actual is Ok(value) && value == expected)
      assert_true(original is Ok(value) && value == expected)
      assert_eq(steps, original_steps)
      assert_eq(fast.control.remaining, 0)
      assert_eq(slow.control.remaining, 0)
      assert_eq(fast.left_calls.val, 2)
      assert_eq(fast.right_calls.val, 2)
      close_text_operand_fixture(fast)
      close_text_operand_fixture(slow)
    }
  }
}

///|
test "Text operands release the first composite key before caching the second" {
  let fixture = text_operand_fixture("resource", "resource")
  fixture.source.keys.push((1, 1))
  let (result, _) = finish_text_operand_fixture(fixture, terms=2)
  assert_true(result is Ok(-1))
  assert_eq(fixture.left_calls.val, 4)
  assert_eq(fixture.right_calls.val, 4)
  assert_eq(fixture.workspace.peak, 13)
  assert_eq(fixture.workspace.live, 5)
  assert_true(fixture.cursor.tree is NoRowComparison)
  close_text_operand_fixture(fixture)
}

///|
test "Text operands refuse before allocation and clear on exact work exhaustion" {
  for maximum in [12, 13] {
    let fixture = text_operand_fixture("abc", "abc", maximum~, work=6)
    let (result, _) = finish_text_operand_fixture(fixture)
    assert_true(result is Err(Limit))
    assert_eq(fixture.workspace.live, 5)
    assert_true(fixture.cursor.tree is NoRowComparison)
    assert_eq(fixture.cursor.phase, -1)
    assert_eq(fixture.control.remaining, if maximum == 12 { 6 } else { 0 })
    close_text_operand_fixture(fixture)
  }
  let recovery = text_operand_fixture("a", "a", work=3)
  assert_true(finish_text_operand_fixture(recovery).0 is Ok(0))
  close_text_operand_fixture(recovery)
}

///|
test "Text operands reject changed coordinates projection and foreign source" {
  for change in [0, 1, 2] {
    let fixture = text_operand_fixture("prefix", "prefix", maximum=17)
    assert_true(step_text_operand_fixture(fixture) is Ok(None))
    assert_true(fixture.cursor.tree is TextRowComparison(_))
    let source = if change == 2 {
      prepare_bounded_comparison_text_source(
        fixture.source.left,
        fixture.source.right,
        fixture.source.keys,
        fixture.workspace,
      )
      .unwrap()
      .unwrap()
    } else {
      fixture.source
    }
    if change == 1 {
      source.keys[0] = (1, 1)
    }
    let result = bounded_row_comparison_step_with(
      fixture.cursor,
      [{ column: 0, descending: false, nulls_first: false, }],
      fixture.control,
      (_, _) => None,
      if change == 0 {
        1
      } else {
        0
      },
      -1,
      1,
      workspace=Some(fixture.workspace),
      text_source=Some(source),
    )
    assert_true(result is Err(InvalidInput))
    assert_true(fixture.cursor.tree is NoRowComparison)
    if change == 2 {
      release_slots(fixture.workspace, 4)
    }
    close_text_operand_fixture(fixture)
  }
}

///|
test "arbitrary presence and general cell readers retain the checked path" {
  let fixture = text_operand_fixture("prefix", "prefix")
  let presence = Ref(0)
  let fetched = Ref(0)
  for _ in 0..<4 {
    assert_true(
      bounded_row_comparison_step_with(
        fixture.cursor,
        [{ column: 0, descending: false, nulls_first: false, }],
        fixture.control,
        (_, _) => {
          fetched.val += 1
          Some(Text("prefix"))
        },
        0,
        1,
        1,
        presence=Some((_, _) => {
          presence.val += 1
          Ok(true)
        }),
        workspace=Some(fixture.workspace),
        text_source=Some(fixture.source),
      )
      is Ok(None),
    )
  }
  assert_eq(presence.val, 8)
  assert_eq(fetched.val, 8)
  assert_true(fixture.cursor.tree is NoRowComparison)
  close_text_operand_fixture(fixture)
  let calls = Ref(0)
  let supplied = restrict_supplied_relation_read(supplied_key_test_input(), () => {
    calls.val += 1
    calls.val <= 3
  })
  let workspace = row_workspace(20)
  let source = prepare_bounded_comparison_text_source(
      SuppliedBindingInput(supplied),
      SuppliedBindingInput(supplied),
      [(1, 1)],
      workspace,
    )
    .unwrap()
    .unwrap()
  // Eligibility retains DATA, not a liveness decision. The general caller
  // below supplies no source and keeps its original checked getters.
  assert_true(source.left is SuppliedBindingInput(_))
  release_slots(workspace, 4)
  assert_eq(workspace.live, 0)
  let cursor = reference_pair_cursor()
  let control : ControlBudget = { remaining: 100, max_frames: 10, }
  for _ in 0..<1 {
    assert_true(
      bounded_row_comparison_step_with(
        cursor,
        [{ column: 1, descending: false, nulls_first: false, }],
        control,
        (row, column) => {
          supplied_relation_read_cell(supplied, row, column).map(capture)
        },
        0,
        0,
        1,
      )
      is Ok(None),
    )
  }
  assert_true(
    bounded_row_comparison_step_with(
      cursor,
      [{ column: 1, descending: false, nulls_first: false, }],
      control,
      (row, column) => {
        supplied_relation_read_cell(supplied, row, column).map(capture)
      },
      0,
      0,
      1,
    )
    is Err(InvalidInput),
  )
  assert_eq(calls.val, 4)
  assert_true(cursor.tree is NoRowComparison)
}

///|
test "supplied Text operands fetch once while retaining fresh checks on every poll" {
  for length in [1, 64, 512] {
    let text = "x".repeat(length)
    let fixture = text_operand_fixture(text, text, supplied_right=true)
    let mut polls = 0
    let mut left_boundary_calls = 0
    let mut right_boundary_calls = 0
    let mut finished = false
    for _ in 0..<20000 {
      // This is the owning pair poll's currentness boundary. No availability
      // decision is stored in either the source or the operand cursor.
      let left_before = fixture.left_calls.val
      let right_before = fixture.right_calls.val
      assert_true(bounded_binding_input_available(fixture.source.left))
      assert_true(bounded_binding_input_available(fixture.source.right))
      left_boundary_calls += fixture.left_calls.val - left_before
      right_boundary_calls += fixture.right_calls.val - right_before
      polls += 1
      match step_text_operand_fixture(fixture) {
        Ok(None) => ()
        Ok(Some(value)) => {
          assert_eq(value, 0)
          finished = true
          break
        }
        Err(_) => fail("live supplied Text comparison failed")
      }
    }
    assert_true(finished)
    // One cell acquisition and one post-funding fence beyond the poll checks,
    // independent of the immutable Text's charging/comparison length.
    assert_true(polls > 0)
    assert_eq(fixture.left_calls.val - left_boundary_calls, 2)
    assert_eq(fixture.right_calls.val - right_boundary_calls, 2)
    close_text_operand_fixture(fixture)
  }
}

///|
test "mixed supplied JOIN Text operands preserve full row values" {
  let text = "x".repeat(128)
  let (_, execution, _) = bounded_join_fixture(
    left_rows="[{\"id\":\"" + text + "\",\"v\":10}]",
    right_rows="[{\"id\":\"" + text + "\",\"v\":20}]",
    key_type="string",
    supplied_right=true,
  )
  assert_true(execution.state.pairs.text_source is Some(_))
  let output = finish_bounded_join_test(execution).unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_eq(
    completed_output_row_wire(output, 0, 4096, 100, 10).unwrap(),
    "{\"k\":\"" + text + "\",\"l\":10,\"r\":20}",
  )
}

///|
fn reach_join_text_operands(execution : BoundedJoinExecution) -> Unit raise {
  for _ in 0..<30000 {
    assert_true(
      advance_bounded_join(execution, 1).unwrap() is BoundedJoinContinue(..),
    )
    if execution.state.pairs.comparison.tree is TextRowComparison(_) {
      return
    }
  }
  fail("JOIN comparison did not reach cached Text operands")
}

///|
test "JOIN Text operands recheck currentness after yield and clear on cancel" {
  for cancel in [false, true] {
    let live = Ref(true)
    let (engine, execution, reads) = bounded_join_fixture(
      left_rows="[{\"id\":\"" + "x".repeat(128) + "\",\"v\":10}]",
      right_rows="[{\"id\":\"" + "x".repeat(128) + "\",\"v\":20}]",
      key_type="string",
      left_current=Some(() => live.val),
    )
    reach_join_text_operands(execution)
    let before = execution.state.control.remaining
    if cancel {
      assert_true(@bounded.request_cancel(engine))
    } else {
      live.val = false
    }
    let poll = advance_bounded_join(execution, 2).unwrap()
    assert_true(
      if cancel {
        poll is BoundedJoinStopped(_, ..)
      } else {
        poll is BoundedJoinFailed(InvalidExecution, ..)
      },
    )
    assert_eq(execution.state.control.remaining, before)
    assert_true(execution.state.pairs.comparison.tree is NoRowComparison)
    assert_true(execution.state.rows.val is None)
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true(producer_read_available(reads[1]))
  }
}

///|
test "supplied JOIN Text operands preserve callback revocation and cancel cleanup after yield" {
  for cancel in [false, true] {
    let live = Ref(true)
    let calls = Ref(0)
    let text = "x".repeat(128)
    let (engine, execution, _) = bounded_join_fixture(
      left_rows="[{\"id\":\"" + text + "\",\"v\":10}]",
      right_rows="[{\"id\":\"" + text + "\",\"v\":20}]",
      key_type="string",
      supplied_right=true,
      right_current=Some(() => {
        calls.val += 1
        live.val
      }),
    )
    reach_join_text_operands(execution)
    let checked = calls.val
    assert_true(
      advance_bounded_join(execution, 1).unwrap() is BoundedJoinContinue(..),
    )
    assert_true(calls.val > checked)
    let before = execution.state.control.remaining
    if cancel {
      assert_true(@bounded.request_cancel(engine))
    } else {
      live.val = false
    }
    let poll = advance_bounded_join(execution, 1).unwrap()
    assert_true(
      if cancel {
        poll is BoundedJoinStopped(_, ..)
      } else {
        poll is BoundedJoinFailed(InvalidExecution, ..)
      },
    )
    assert_eq(execution.state.control.remaining, before)
    assert_true(execution.state.pairs.comparison.tree is NoRowComparison)
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
  }
}

///|
test "Text operands keep the original malformed UTF16 refusal and release their record" {
  let owner = row_owner(",{\"derive\":{\"label\":{\"literal\":\"a\"}}}")
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["derive_1"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let receiver = producer_consumer(owner, Step(1))
  let output = completed_output(completion, Step(1)).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, output).unwrap(),
    100,
    100,
  ).unwrap()
  let mut column = -1
  for index in 0..<@schema.field_count(read.schema) {
    if @schema.field_at(read.schema, index).unwrap().name ==
      @schema.Unqualified("label") {
      column = index
    }
  }
  assert_true(column >= 0)
  guard output.table is Some(RowTable(table)) else {
    fail("derived Text must use a raw table")
  }
  for unit in [0xd800, 0xdc00] {
    // This package-private corruption cannot be made through a producer read.
    // The optimized path must still apply the original UTF8 decoder to raw Text.
    table.rows[0][read.columns[column]] = Text(
      String::from_array([unit.unsafe_to_char()]),
    )
    for fast in [true, false] {
      let workspace = row_workspace(13)
      assert_true(reserve_slots(workspace, 1))
      let source = prepare_bounded_comparison_text_source(
          CompletedBindingInput(read),
          CompletedBindingInput(read),
          [(column, column)],
          workspace,
        )
        .unwrap()
        .unwrap()
      let cursor = reference_pair_cursor()
      let control : ControlBudget = { remaining: 100, max_frames: 10, }
      let mut rejected = false
      for _ in 0..<5 {
        match
          bounded_row_comparison_step_with(
            cursor,
            [{ column: 0, descending: false, nulls_first: false, }],
            control,
            (_, _) => producer_read_cell(read, 0, column),
            0,
            -1,
            1,
            workspace=Some(workspace),
            text_source=if fast { Some(source) } else { None },
          ) {
          Err(Limit) => {
            rejected = true
            break
          }
          Ok(None) => ()
          _ => fail("malformed UTF16 must retain its typed refusal")
        }
      }
      assert_true(rejected)
      assert_eq(control.remaining, 99)
      assert_eq(workspace.live, 5)
      assert_true(cursor.tree is NoRowComparison)
      release_slots(workspace, 5)
    }
  }
}

///|
test "Text operands fence the original input after a funding callback changes currentness" {
  let live = Ref(true)
  let armed = Ref(false)
  let calls = Ref(0)
  let growth = working_growth_fixture(_ => {
    calls.val += 1
    if armed.val {
      live.val = false
    }
    Ok(())
  })
  let fixture = text_operand_fixture(
    "prefix",
    "prefix",
    growth=Some(growth),
    live=Some(live),
  )
  armed.val = true
  calls.val = 0
  assert_true(step_text_operand_fixture(fixture) is Err(InvalidInput))
  assert_eq(calls.val, 1)
  assert_eq(fixture.control.remaining, 100000)
  assert_eq(fixture.workspace.live, 5)
  assert_eq(growth.slots, 5)
  assert_eq(growth.slot_peak, 13)
  assert_true(fixture.cursor.tree is NoRowComparison)
  close_text_operand_fixture(fixture)
  assert_eq(growth.slots, 0)
}

///|
test "Text operands cannot resume under an equal-valued foreign producer source" {
  let original = text_operand_fixture("same", "same")
  let foreign = text_operand_fixture("same", "same")
  assert_true(step_text_operand_fixture(original) is Ok(None))
  assert_true(
    bounded_row_comparison_step_with(
      original.cursor,
      [{ column: 0, descending: false, nulls_first: false, }],
      original.control,
      (_, _) => None,
      0,
      -1,
      1,
      workspace=Some(original.workspace),
      text_source=Some(foreign.source),
    )
    is Err(InvalidInput),
  )
  assert_true(original.cursor.tree is NoRowComparison)
  assert_eq(original.workspace.live, 5)
  close_text_operand_fixture(original)
  close_text_operand_fixture(foreign)
}

///|
test "bounded JOIN Text composite keys preserve exact tuples and work at every quantum" {
  let totals = []
  for quantum in [1, 2, 64] {
    let (_, execution, inputs) = bounded_join_fixture(
      left_rows="[{\"id\":\"resource-a\",\"v\":\"version-1\"},{\"id\":\"resource-a\",\"v\":\"version-2\"},{\"id\":\"resource-b\",\"v\":\"version-1\"}]",
      right_rows="[{\"id\":\"resource-a\",\"v\":\"version-2\"},{\"id\":\"resource-b\",\"v\":\"version-1\"}]",
      key_type="string",
      value_type="string",
      join_keys="[{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"v\",\"right\":\"v\"}]",
    )
    let output = finish_bounded_join_test(execution, quantum~).unwrap()
    assert_eq(completed_row_count(output), 2)
    for
      (row, resource, version) in [
        (0, "resource-a", "version-2"),
        (1, "resource-b", "version-1"),
      ] {
      assert_true(
        completed_cell(output, row, 0) is Some(Text(value)) && value == resource,
      )
      assert_true(
        completed_cell(output, row, 1) is Some(Text(value)) && value == version,
      )
      assert_true(
        completed_cell(output, row, 2) is Some(Text(value)) && value == version,
      )
    }
    totals.push(execution.state.control.remaining)
    assert_true(execution.state.pairs.comparison.tree is NoRowComparison)
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true(inputs.all(producer_read_available))
  }
  assert_eq(totals[0], totals[1])
  assert_eq(totals[1], totals[2])
}

///|
test "JOIN Text cleanup stops an active index sorter before releasing the source" {
  let prefix = "x".repeat(128)
  let (engine, execution, inputs) = bounded_join_fixture(
    left_rows="[{\"id\":\"" + prefix + "a\",\"v\":10}]",
    right_rows="[{\"id\":\"" +
      prefix +
      "a\",\"v\":20},{\"id\":\"" +
      prefix +
      "b\",\"v\":21}]",
    key_type="string",
  )
  reach_join_text_operands(execution)
  assert_true(execution.state.pairs.phase is BuildIndex)
  guard execution.state.pairs.sorter is Some(sorter) else {
    fail("comparison must belong to the live index sort")
  }
  let before = execution.state.control.remaining
  assert_true(@bounded.request_cancel(engine))
  assert_true(
    advance_bounded_join(execution, 1).unwrap() is BoundedJoinStopped(_, ..),
  )
  assert_eq(execution.state.control.remaining, before)
  assert_true(execution.state.pairs.comparison.tree is NoRowComparison)
  // Dropping borrowed Text DATA does not acknowledge physical ownership: the
  // exact source stays anchored until cleanup revokes and stops the child.
  assert_true(execution.state.pairs.text_source is Some(_))
  assert_true(cleanup_bounded_join(execution).unwrap())
  assert_true(bounded_index_sort_stopped(sorter))
  assert_true(execution.state.pairs.text_source is None)
  assert_eq(execution.state.workspace.live, 0)
  assert_true(inputs.all(producer_read_available))
}
