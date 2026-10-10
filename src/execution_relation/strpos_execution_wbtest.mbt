///|
// Independent STRING/default-comparison expectations from the STRPOS contract.
// These cases are not observations from a live BigQuery service.
test "strpos returns the first scalar position without normalizing retained text" {
  for
    (source, expected) in [
      ("strpos('banana', 'ana')", 2.0),
      ("strpos('aaaaa', 'aaa')", 1.0),
      ("strpos('aaab', 'aab')", 2.0),
      ("strpos('abc', 'c')", 3.0),
      ("strpos('abc', 'A')", 0.0),
      ("strpos('abc', 'x')", 0.0),
      ("strpos('abc', 'abcd')", 0.0),
      ("strpos('abc', '')", 1.0),
      ("strpos('', '')", 1.0),
      ("strpos('', 'a')", 0.0),
      ("strpos('猫abc', 'a')", 2.0),
      ("strpos('😀x😀', 'x')", 2.0),
      ("strpos('😀x😀', '😀')", 1.0),
      ("strpos('😀😀a', '😀a')", 2.0),
      ("strpos('😀😁', '😁')", 2.0),
      ("strpos('é', 'é')", 0.0),
      ("strpos('é', 'é')", 0.0),
      ("strpos('éx', '́')", 2.0),
      ("strpos('😀éx', 'x')", 4.0),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Number(actual)) && actual == expected,
      msg=source,
    )
  }
  for
    (part, expected) in [
      ("\r\n", 1.0),
      ("\n", 2.0),
      ("猫", 3.0),
      ("猫\r\n", 3.0),
      ("\n\r", 0.0),
    ] {
    assert_true(
      evaluate_expression(
        borrowed_text_comparison("strpos"),
        Map([("left", Text("\r\n猫\r\n")), ("right", Text(part))]),
        [],
        { remaining: 1000, max_frames: 10, },
      )
      is Ok(Number(actual)) &&
      actual == expected,
    )
  }
  // Direct retained Text avoids source escape decoding. The supplementary
  // scalar and combining mark before NUL still each contribute one position.
  for
    (part, expected) in [
      ("\u{0}", 4.0),
      ("\u{0}x", 4.0),
      ("x\u{0}", 5.0),
      ("\u{0}\u{0}", 0.0),
    ] {
    let logical = text_expression_budget(1000L, 1000L)
    let workspace = row_workspace(20)
    let result = evaluate_expression_retained(
      borrowed_text_comparison("strpos"),
      Map([("left", Text("😀é\u{0}x\u{0}")), ("right", Text(part))]),
      [],
      { remaining: 1000, max_frames: 10, },
      workspace,
      logical_work=Some(logical),
    ).unwrap()
    assert_true(result.value is Number(actual) && actual == expected)
    release_logical_root(logical, result.root.unwrap()).unwrap()
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "strpos keeps strict NULL and left to right eager child failures" {
  for args in ["NULL, 'a'", "'a', NULL", "NULL, NULL", "NULL, ''", "'', NULL"] {
    assert_true(run_expr("\"strpos(" + args + ")\"") is Ok(Null))
  }
  for
    args in [
      "NULL, if(1 / 0 > 0, 'a', 'b')", "if(1 / 0 > 0, 'a', 'b'), NULL", "'', if(1 / 0 > 0, 'a', 'b')",
      "if(1 / 0 > 0, 'a', 'b'), ''",
    ] {
    guard run_expr("\"strpos(" + args + ")\"") is Err(issue) else {
      fail("STRPOS suppressed a demanded child failure")
    }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Divide, _, _),
    )
  }
  assert_true(
    run_expr("\"if(FALSE, strpos(NULL, if(1 / 0 > 0, 'a', 'b')), 7)\"")
    is Ok(Number(7.0)),
  )
  guard run_expr(
      "\"strpos(if(sqrt(-1) > 0, 'a', 'b'), if(1 / 0 > 0, 'c', 'd'))\"",
    )
    is Err(issue) else {
    fail("STRPOS first demanded failure missing")
  }
  assert_true(
    @lower.expression_body(issue.expression) is @lower.Unary(@lower.Sqrt, _),
  )
}

///|
test "strpos charges every repeated prefix comparison at exact control limits" {
  // Six expression transitions and left/right field names cost 15 units.
  // Equal strings need 256 comparisons. The absent repeated-prefix case
  // needs 128 candidates times 129 comparisons and one cannot-fit poll.
  for
    (input, needle, expected, exact) in [
      (String::make(256, 'a'), String::make(256, 'a'), 1.0, 271),
      (String::make(256, 'a'), String::make(128, 'a') + "b", 0.0, 16528),
    ] {
    for drain in [false, true] {
      for quantum in [1, 7, 256] {
        for short in [false, true] {
          let control = {
            remaining: exact - (if short { 1 } else { 0 }),
            max_frames: 10,
          }
          let workspace = row_workspace(2)
          let frame = expression_frame(
            borrowed_text_comparison("strpos"),
            Map([("left", Text(input)), ("right", Text(needle))]),
            [],
            control,
            workspace,
            None,
          ).unwrap()
          let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
          let mut polls = 0
          while result is Ok(None) && polls < 20000 {
            for _ in 0..<quantum {
              let before = control.remaining
              let searching = frame.state is TextFunction(_)
              result = advance_expression_frame(frame, drain~)
              polls += 1
              if !drain {
                assert_true(before - control.remaining <= 64)
                if searching && before > 0 {
                  assert_eq(before - control.remaining, 1)
                }
              }
              if !(result is Ok(None)) {
                break
              }
            }
          }
          if short {
            assert_true(result is Err({ kind: ControlLimit, .. }))
          } else {
            assert_true(
              result is Ok(Some({ value: Number(actual), .. })) &&
              actual == expected,
            )
            assert_eq(control.remaining, 0)
          }
          assert_eq((workspace.peak, workspace.live), (2, 0))
          assert_true(frame.closed)
        }
      }
    }
  }
}

///|
test "strpos short Unicode empty and absent searches have bounded exact costs" {
  for
    (input, needle, expected, exact) in [
      (Text("😀é"), Text("é"), Number(2.0), 17),
      (Text("😀é"), Text("😀"), Number(1.0), 17),
      (Text("😀é"), Text("😁"), Number(0.0), 18),
      (Text(""), Text(""), Number(1.0), 16),
      (Text(""), Text("a"), Number(0.0), 16),
      (Text("a"), Text("ab"), Number(0.0), 16),
      (Null, Text(""), Null, 16),
    ] {
    for drain in [false, true] {
      for short in [false, true] {
        let control = {
          remaining: exact - (if short { 1 } else { 0 }),
          max_frames: 10,
        }
        let workspace = row_workspace(2)
        let frame = expression_frame(
          borrowed_text_comparison("strpos"),
          Map([("left", input), ("right", needle)]),
          [],
          control,
          workspace,
          None,
        ).unwrap()
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        for _ in 0..<100 {
          result = advance_expression_frame(frame, drain~)
          if !(result is Ok(None)) {
            break
          }
        }
        if short {
          assert_true(result is Err({ kind: ControlLimit, .. }))
        } else {
          guard result is Ok(Some(value)) else {
            fail("STRPOS exact short search boundary")
          }
          assert_eq(
            object_result_wire(value.value),
            object_result_wire(expected),
          )
          assert_eq(control.remaining, 0)
        }
        assert_eq(workspace.live, 0)
      }
    }
  }
}

///|
test "strpos reserves two cursor handles before matching" {
  for slots in [2, 1] {
    let workspace = row_workspace(slots)
    let frame = expression_frame(
      borrowed_text_comparison("strpos"),
      Map([
        ("left", Text(String::make(256, 'a'))),
        ("right", Text(String::make(128, 'a') + "b")),
      ]),
      [],
      { remaining: 20000, max_frames: 10, },
      workspace,
      None,
    ).unwrap()
    let result = advance_expression_frame(frame, drain=true)
    if slots == 2 {
      assert_true(result is Ok(Some({ value: Number(0.0), .. })))
    } else {
      assert_true(result is Err({ kind: WorkspaceLimit, .. }))
    }
    assert_eq((workspace.peak, workspace.live), (slots, 0))
    assert_true(frame.closed)
  }
}

///|
test "strpos keeps semantic work live bytes and workspace limits independent" {
  // Three entries, two produced Text weights (257), two consumed operands,
  // and one Number result give 1032 work. Input roots peak at 516 bytes.
  // A long operand's measurement under the parent slot peaks at 11 slots;
  // the search itself retains only its two fixed handles and no output buffer.
  for drain in [false, true] {
    for quantum in [1, 7, 256] {
      for
        (work, live, slots, failure) in [
          (1032L, 516L, 11, 0),
          (1031L, 516L, 11, 1),
          (1032L, 515L, 11, 2),
          (1032L, 516L, 10, 3),
        ] {
        let logical = text_expression_budget(work, live)
        let workspace = row_workspace(slots)
        let text = Text(String::make(256, 'a'))
        let frame = expression_frame(
          borrowed_text_comparison("strpos"),
          Map([("left", text), ("right", text)]),
          [],
          { remaining: 10000, max_frames: 10, },
          workspace,
          Some(expression_roots(logical, 10)),
        ).unwrap()
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        let mut polls = 0
        while result is Ok(None) && polls < 3000 {
          for _ in 0..<quantum {
            if frame.state is TextFunction(state) {
              assert_true(state.kind == TextStrpos)
              assert_eq(state.allocated, 0)
              assert_true(state.builder is None)
              assert_true(state.output_root is None)
              assert_eq(workspace.live, 2)
            }
            result = advance_expression_frame(frame, drain~)
            polls += 1
            if !(result is Ok(None)) {
              break
            }
          }
        }
        match failure {
          0 => {
            guard result is Ok(Some(value)) else {
              fail("STRPOS exact logical boundary")
            }
            assert_true(value.value is Number(1.0))
            assert_eq(
              (logical.work, logical.peak, workspace.peak),
              (1032L, 516L, 11),
            )
            assert_eq(logical.live, 1L)
            release_logical_root(logical, value.root.unwrap()).unwrap()
          }
          1 =>
            assert_true(
              result
              is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
            )
          2 =>
            assert_true(
              result is Err({ kind: LogicalValue(LiveValueLimit), .. }),
            )
          3 => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
          _ => fail("unknown STRPOS boundary")
        }
        close_expression_frame(frame)
        assert_eq((logical.live, workspace.live), (0L, 0))
      }
    }
  }
}

///|
test "strpos cancellation preserves borrowed roots and workspace across restarts" {
  for restarted in [false, true] {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Text("external")).unwrap()
    let workspace = row_workspace(30)
    assert_true(reserve_slots(workspace, 3))
    let frame = expression_frame(
      borrowed_text_comparison("strpos"),
      Map([
        ("left", Text(String::make(256, 'a'))),
        ("right", Text(String::make(128, 'a') + "b")),
      ]),
      [],
      { remaining: 20000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut reached = false
    for _ in 0..<3000 {
      assert_true(advance_expression_frame(frame) is Ok(None))
      if frame.state is TextFunction(state) &&
        state.matched == 64 &&
        state.position == (if restarted { 1 } else { 0 }) {
        assert_true(state.kind == TextStrpos)
        assert_eq(state.count, if restarted { 1 } else { 0 })
        assert_eq(state.allocated, 0)
        assert_true(state.builder is None)
        assert_true(state.output_root is None)
        reached = true
        break
      }
    }
    assert_true(reached)
    assert_eq(workspace.live, 5)
    assert_eq(logical.live, borrowed.bytes + 258L + 131L)
    let work = logical.work
    let remaining = frame.budget.remaining
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq((logical.work, frame.budget.remaining), (work, remaining))
    assert_eq((logical.live, workspace.live), (borrowed.bytes, 3))
    assert_false(borrowed.released)
    assert_true(
      advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
    )
    release_logical_root(logical, borrowed).unwrap()
    release_slots(workspace, 3)
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
fn bounded_strpos_filter_fixture() -> (
  @bounded.Control,
  BoundedBindingRowsExecution,
  ProducerRead,
) raise {
  let (source_owner, source) = bounded_binding_rows_source(
    "[{\"id\":1,\"tag\":\"" + String::make(256, 'a') + "\"}]",
    distinct=true,
  )
  let receiver = bounded_binding_rows_receiver(
    source_owner,
    metadata_operation=Some(
      "{\"filter\":{\"eq\":[{\"strpos\":[{\"field\":\"tag\"},{\"literal\":\"" +
      String::make(128, 'a') +
      "b\"}]},{\"literal\":0}]},\"from\":\"rows\",\"as\":\"derived\"}",
    ),
  )
  let sequence = prepared_sequence(receiver)
  let first = @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 0, 1L)],
    [@lower.node_id(first)],
    100000,
    10000,
  ).unwrap()
  let bound = bind_completed_input(receiver, 0, source_owner, source).unwrap()
  let input = prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_binding_rows(
    control,
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
  (control, execution, input)
}

///|
test "bounded strpos filter cancels inside a repeated prefix without publishing" {
  let (control, execution, input) = bounded_strpos_filter_fixture()
  let logical = execution.state.logical.unwrap()
  let mut reached = false
  for _ in 0..<5000 {
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    if execution.state.predicate_execution is Some(frame) &&
      frame.state is TextFunction(state) &&
      state.position == 1 &&
      state.matched == 64 {
      assert_true(state.kind == TextStrpos)
      reached = true
      break
    }
  }
  assert_true(reached)
  let frame = execution.state.predicate_execution.unwrap()
  let root = execution.state.input_roots[0]
  let consumed = logical.work
  let remaining = execution.state.control.remaining
  let held = execution.state.workspace.live
  assert_false(root.root.released)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
  )
  assert_eq((logical.work, execution.state.workspace.live), (consumed, held))
  assert_false(root.root.released)
  assert_false(frame.closed)
  assert_true(execution.state.rows.val is None)
  assert_false(execution.accepted.val)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(frame.closed)
  assert_true(root.root.released)
  assert_eq((logical.live, execution.state.workspace.live), (0L, 0))
  assert_eq(
    (logical.work, execution.state.control.remaining),
    (consumed, remaining),
  )
  assert_true(producer_read_available(input))
}

///|
test "bounded strpos filter preserves results and ledgers across polling quanta" {
  let mut prior : (Int, Int64)? = None
  for quantum in [1, 7, 256] {
    let (_, execution, input) = bounded_strpos_filter_fixture()
    let mut result : CompletedOutput? = None
    for _ in 0..<30000 {
      match advance_bounded_binding_rows(execution, quantum).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          result = Some(output)
          break
        }
        _ => fail("bounded STRPOS filter had an unrelated terminal outcome")
      }
    }
    guard result is Some(output) else {
      fail("bounded STRPOS filter did not terminate")
    }
    assert_eq(completed_row_count(output), 1)
    assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
    assert_true(completed_output_matches_inputs(output, [input]))
    let work = (
      execution.state.control.remaining,
      execution.state.logical.unwrap().work,
    )
    if prior is Some(expected) {
      assert_eq(work, expected)
    }
    prior = Some(work)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_false(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq(
      (execution.state.logical.unwrap().live, execution.state.workspace.live),
      (0L, 0),
    )
    assert_true(producer_read_available(input))
  }
}
