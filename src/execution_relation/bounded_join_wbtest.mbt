///|
fn bounded_join_fixture(
  left_rows? : String = "[{\"id\":1,\"v\":10}]",
  right_rows? : String = "[{\"id\":1,\"v\":20}]",
  kind? : String = "inner",
  options? : String = "",
  key_type? : String = "number",
  max_work? : Int = 100000,
  max_entries? : Int = 1000,
  output_nodes? : Int = 1000,
) -> (@bounded.Control, BoundedJoinExecution, Array[ProducerRead]) raise {
  let schema = "{\"id\":{\"type\":\"" +
    key_type +
    "\",\"nullable\":true},\"v\":{\"type\":\"number\",\"nullable\":false}}"
  let (left_owner, left_output) = bounded_cross_source(schema, left_rows)
  let (right_owner, right_output) = bounded_cross_source(schema, right_rows)
  let producer = fn(owner) {
    @pipeline.produced_input(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    ).unwrap()
  }
  let projection = if kind == "semi" || kind == "anti" {
    "{\"k\":\"left.id\",\"l\":\"left.v\"}"
  } else {
    "{\"k\":\"left.id\",\"l\":\"left.v\",\"r\":\"right.v\"}"
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"" +
      kind +
      "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}]," +
      "\"select\":" +
      projection +
      options +
      "}}]",
    ),
    [
      ("l", @pipeline.ProducedInput(producer(left_owner))),
      ("r", @pipeline.ProducedInput(producer(right_owner))),
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
    ["join_0"],
    100000,
    10000,
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
  let execution = start_bounded_join(
    control,
    generated,
    trusted_output_relation_input(left),
    trusted_output_relation_input(right),
    100,
    run_limits().input_values,
    { ..run_limits().output_values, max_nodes: output_nodes, },
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, execution, [left, right])
}

///|
fn finish_bounded_join_test(
  execution : BoundedJoinExecution,
  quantum? : Int = 1,
) -> Result[CompletedOutput, BoundedJoinIssue] raise {
  let mut previous_work = 0L
  for _ in 0..<100000 {
    match advance_bounded_join(execution, quantum).unwrap() {
      BoundedJoinContinue(work~, ..) => {
        assert_true(work > previous_work)
        assert_true(work - previous_work <= quantum.to_int64())
        previous_work = work
      }
      BoundedJoinComplete(output, work~, ..) => {
        assert_true(work - previous_work <= quantum.to_int64())
        return Ok(output)
      }
      BoundedJoinFailed(issue, ..) => return Err(issue)
      _ => fail("unexpected join stop")
    }
  }
  fail("join did not terminate within its finite fixture bound")
}

///|
test "bounded joins preserve pair order and null extension at every quantum" {
  for quantum in [1, 7, 128] {
    for
      (kind, expected) in [
        (
          "inner",
          [
            [Number(1), Number(10), Number(20)],
            [Number(1), Number(10), Number(21)],
            [Number(1), Number(11), Number(20)],
            [Number(1), Number(11), Number(21)],
          ],
        ),
        (
          "left",
          [
            [Number(1), Number(10), Number(20)],
            [Number(1), Number(10), Number(21)],
            [Null, Number(12), Null],
            [Number(1), Number(11), Number(20)],
            [Number(1), Number(11), Number(21)],
          ],
        ),
        (
          "full",
          [
            [Number(1), Number(10), Number(20)],
            [Number(1), Number(10), Number(21)],
            [Null, Number(12), Null],
            [Number(1), Number(11), Number(20)],
            [Number(1), Number(11), Number(21)],
            [Null, Null, Number(22)],
            [Null, Null, Number(23)],
          ],
        ),
        ("semi", [[Number(1), Number(10)], [Number(1), Number(11)]]),
        ("anti", [[Null, Number(12)]]),
      ] {
      let (_, execution, reads) = bounded_join_fixture(
        left_rows="[{\"id\":1,\"v\":10},{\"id\":null,\"v\":12},{\"id\":1,\"v\":11}]",
        right_rows="[{\"id\":1,\"v\":20},{\"id\":null,\"v\":22},{\"id\":1,\"v\":21},{\"id\":2,\"v\":23}]",
        kind~,
      )
      let output = finish_bounded_join_test(execution, quantum~).unwrap()
      let rows = Array::makei(completed_row_count(output), row => {
        Array::makei(expected[0].length(), column => {
          completed_cell(output, row, column).unwrap()
        })
      })
      assert_true(join_numeric_rows_equal(rows, expected))
      assert_true(cleanup_bounded_join(execution).unwrap())
      assert_eq(execution.state.workspace.live, 0)
      assert_true(producer_read_available(reads[0]))
      assert_true(producer_read_available(reads[1]))
    }
  }
}

///|
test "bounded join validates empty sides and preserves obligation priority" {
  for
    (left, right, options, expected) in [
      (
        "[]",
        "[{\"id\":1,\"v\":20},{\"id\":1,\"v\":21}]",
        ",\"cardinality\":\"many_to_one\"",
        JoinDuplicateKey(false, 1, 0),
      ),
      (
        "[{\"id\":2,\"v\":10},{\"id\":2,\"v\":11}]",
        "[{\"id\":null,\"v\":20}]",
        ",\"cardinality\":\"one_to_one\",\"null_key\":\"fail\"",
        JoinDuplicateKey(true, 1, 0),
      ),
      (
        "[{\"id\":2,\"v\":10},{\"id\":2,\"v\":11},{\"id\":null,\"v\":12}]",
        "[]",
        ",\"cardinality\":\"one_to_one\",\"null_key\":\"fail\"",
        JoinNullKey(true, 2, 0),
      ),
    ] {
    let (_, execution, _) = bounded_join_fixture(
      left_rows=left,
      right_rows=right,
      options~,
    )
    guard finish_bounded_join_test(execution) is Err(Rows(actual)) else {
      fail("join obligation was not enforced")
    }
    match (actual, expected) {
      (JoinDuplicateKey(a, b, c), JoinDuplicateKey(x, y, z))
      | (JoinNullKey(a, b, c), JoinNullKey(x, y, z)) =>
        assert_eq((a, b, c), (x, y, z))
      _ => fail("wrong join obligation")
    }
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
  }
}

///|
test "bounded join cancels during private index construction and output" {
  for phase in [0, 1, 2] {
    let (control, execution, reads) = bounded_join_fixture()
    let state = execution.state
    let mut reached = false
    for _ in 0..<1000 {
      if !reached {
        assert_true(
          advance_bounded_join(execution, 1).unwrap() is BoundedJoinContinue(..),
        )
        reached = if phase == 0 {
          state.pairs.sorter is Some(_)
        } else if phase == 1 {
          state.pairs.phase is SearchRight
        } else {
          state.phase is ChargeCell
        }
      }
    }
    assert_true(reached)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_join(execution, 1).unwrap() is BoundedJoinStopped(_, ..),
    )
    assert_true(state.rows.val is None)
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(state.workspace.live, 0)
    assert_true(producer_read_available(reads[0]))
    assert_true(producer_read_available(reads[1]))
  }
}

///|
test "bounded join output node admission rejects before completion" {
  // One row object and three scalar cells require four value nodes.
  for limit in [3, 4] {
    let (_, execution, _) = bounded_join_fixture(output_nodes=limit)
    let result = finish_bounded_join_test(execution)
    if limit == 4 {
      assert_eq(completed_row_count(result.unwrap()), 1)
    } else {
      assert_true(result is Err(Capture(CaptureLimit)))
      assert_true(execution.state.rows.val is None)
    }
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
  }
}

///|
test "empty bounded join has independent exact work and workspace limits" {
  // Two input-end checks, six key lookup units, six projected-name units,
  // eleven projected-source units, and six pair-state transitions.
  let work = 2 + 6 + 6 + 11 + 6
  // Two base slots, three key slots, and three slots per projected field.
  let workspace = 2 + 3 + 3 * 3
  for
    (work_limit, workspace_limit, succeeds) in [
      (work, workspace, true),
      (work - 1, workspace, false),
      (work, workspace - 1, false),
    ] {
    let (_, execution, _) = bounded_join_fixture(
      left_rows="[]",
      right_rows="[]",
      max_work=work_limit,
      max_entries=workspace_limit,
    )
    let result = finish_bounded_join_test(execution)
    if succeeds {
      assert_eq(completed_row_count(result.unwrap()), 0)
      assert_eq(execution.state.control.remaining, 0)
      assert_eq(execution.state.workspace.peak, workspace)
    } else {
      assert_true(result is Err(Rows(RowLimit)))
      assert_true(execution.state.rows.val is None)
    }
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
  }
}

///|
test "bounded join reserves overlapping output and index workspace" {
  // Base (2), key mapping/order (3), projection metadata (9), NULL flags
  // (2), retained right index (1), row handles (2), three cells (3), and
  // the two live value/name measurement frames (2).
  let exact = 2 + 3 + 9 + 2 + 1 + 2 + 3 + 2
  for limit in [exact - 1, exact] {
    let (_, execution, _) = bounded_join_fixture(max_entries=limit)
    let result = finish_bounded_join_test(execution)
    if limit == exact {
      assert_eq(completed_row_count(result.unwrap()), 1)
      assert_eq(execution.state.workspace.peak, exact)
    } else {
      assert_true(result is Err(Rows(RowLimit)))
      assert_true(execution.state.rows.val is None)
    }
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
  }
}

///|
test "bounded join yields within a long equal text key comparison" {
  let prefix = "x".repeat(256)
  let row = "[{\"id\":\"" + prefix + "\",\"v\":10}]"
  let (control, execution, reads) = bounded_join_fixture(
    left_rows=row,
    right_rows=row,
    key_type="string",
  )
  let mut reached = false
  for _ in 0..<10000 {
    if !reached {
      assert_true(
        advance_bounded_join(execution, 1).unwrap() is BoundedJoinContinue(..),
      )
      let comparison = execution.state.pairs.comparison
      reached = comparison.phase == 3 && comparison.offset == 64
    }
  }
  assert_true(reached)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_join(execution, 1).unwrap() is BoundedJoinStopped(_, ..),
  )
  assert_true(execution.state.rows.val is None)
  assert_true(cleanup_bounded_join(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
  assert_true(producer_read_available(reads[0]))
  assert_true(producer_read_available(reads[1]))
}
