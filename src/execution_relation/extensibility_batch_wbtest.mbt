///|
fn ext_test_batch_plan(owner : @lower.BoundPrepared) -> ExtBatchPlan {
  ext_prepare_batch(
    row_kernel(owner, 1),
    { remaining: 1000000, max_frames: 100, },
    { limit: 1000000, live: 0, peak: 0, },
  )
  .unwrap()
  .unwrap()
}

///|
fn ext_batch_budget(rows : Int, work : Int64, live : Int64) -> LogicalBudget {
  logical_budget(
    {
      max_input_rows: rows.to_int64(),
      max_work: work,
      max_live_value_bytes: live,
      max_value_bytes: 1000L,
    },
    10000,
    10000,
    100,
  ).unwrap()
}

///|
test "typed batches cross real chunk boundaries with exact independent accounting" {
  let data = Array::makei(15, i => {
    if i % 2 == 0 {
      "{\"a\":1,\"b\":0}"
    } else {
      "{\"a\":0,\"b\":1}"
    }
  }).join(",")
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    data +
    "]},\"as\":\"seed\"},{\"derive\":[{\"x\":\"if(a > 0, a + 1, b + 2)\"},{\"a\":\"if(x > 2, x / 2, x + 3)\"}]}]",
  )
  let plan = ext_test_batch_plan(owner)
  let captured = capture_values(
    owner,
    0,
    max_rows=15,
    run_limits().input_values,
  ).unwrap()
  // 15 * (5 input + 1 row + 2 bindings + 40 expression + 7 output).
  // Last row peak: 280 preceding output bytes + 13 input + 2 slots + 19 output.
  let baseline_budget = ext_batch_budget(15, 825L, 314L)
  let baseline = run_ordered_rows(owner, row_capture(owner), baseline_budget).unwrap()
  assert_eq((baseline_budget.work, baseline_budget.peak), (825L, 314L))
  for width in [1, 7, 1000] {
    for
      (work, live, success) in [
        (825L, 314L, true),
        (824L, 314L, false),
        (825L, 313L, false),
      ] {
      let budget = ext_batch_budget(15, work, live)
      let ledger = layout_ledger(100000, 100000, 100000)
      let physical = {
        ..layout_allocation(100000, 100000, 100000),
        ledger: Some(ledger),
      }
      let trace = { chunks: 0, selected: 0, rejected: 0, }
      let result = ext_run_batch(
        plan,
        layout_relation(captured, TypedColumns),
        width,
        budget,
        physical,
        trace,
      )
      if success {
        let output = result.unwrap()
        assert_eq(trace.chunks, (15 + width - 1) / width)
        assert_eq((trace.selected, trace.rejected), (15, 15))
        assert_eq((budget.work, budget.peak), (825L, 314L))
        for row in 0..<15 {
          let expected = if row % 2 == 0 {
            [5.0, 0.0, 2.0]
          } else {
            [1.5, 1.0, 3.0]
          }
          for column in 0..<3 {
            assert_true(
              layout_cell(output, row, column) is Some(Number(n)) &&
              n == expected[column],
            )
            assert_true(
              baseline.rows[row][column] is Number(n) && n == expected[column],
            )
          }
        }
        release_layout_columns(output)
      } else {
        assert_true(result is Err(LogicalRows(_)))
        assert_true(budget.failed)
      }
      assert_eq(budget.live, 0L)
      assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    }
  }
}

///|
test "typed masks suppress unselected failure and retain row before slot priority" {
  for fails in [false, true] {
    let owner = row_owner(
      if fails {
        ",{\"derive\":[{\"x\":\"if(a > 0, a + 1, 1 / 0)\"},{\"a\":\"1 / b\"}]}"
      } else {
        ",{\"derive\":[{\"x\":\"if(a >= 0, a + 1, 1 / 0)\"}]}"
      },
    )
    let plan = ext_test_batch_plan(owner)
    let captured = capture_values(
      owner,
      0,
      max_rows=2,
      run_limits().input_values,
    ).unwrap()
    for width in [1, 7, 1000] {
      let budget = ordered_row_budget(10000L, 10000L)
      let baseline_budget = ordered_row_budget(10000L, 10000L)
      let baseline = run_ordered_rows(
        owner,
        row_capture(owner),
        baseline_budget,
      )
      let ledger = layout_ledger(100000, 100000, 100000)
      let physical = {
        ..layout_allocation(100000, 100000, 100000),
        ledger: Some(ledger),
      }
      let trace = { chunks: 0, selected: 0, rejected: 0, }
      let result = ext_run_batch(
        plan,
        layout_relation(captured, TypedColumns),
        width,
        budget,
        physical,
        trace,
      )
      if fails {
        assert_true(
          result
          is Err(Evaluation(0, 1, { kind: Scalar(ArithmeticFailure), .. })),
        )
        assert_true(
          baseline
          is Err(Evaluation(0, 1, { kind: Scalar(ArithmeticFailure), .. })),
        )
      } else {
        let output = result.unwrap()
        assert_eq((trace.selected, trace.rejected), (2, 0))
        assert_true(layout_cell(output, 0, 2) is Some(Number(2.0)))
        assert_true(layout_cell(output, 1, 2) is Some(Number(1.0)))
        assert_true(baseline is Ok(_))
        release_layout_columns(output)
      }
      assert_eq(
        (budget.work, budget.peak, budget.live),
        (baseline_budget.work, baseline_budget.peak, 0L),
      )
      assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    }
  }
}

///|
test "typed conditional batch executes shared events without row snapshots" {
  let owner = row_owner(
    ",{\"derive\":[{\"x\":\"if(a > 0, a + 1, b + 2)\"},{\"a\":\"if(x > 2, x / 2, x + 3)\"}]}",
  )
  let plan = ext_test_batch_plan(owner)
  let capture = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  let baseline = ordered_row_budget(110L, 57L, bytes=21L)
  let expected = run_ordered_rows(owner, row_capture(owner), baseline).unwrap()
  assert_eq((baseline.work, baseline.peak, baseline.live), (110L, 57L, 0L))
  for width in [1, 7, 1000] {
    let input = layout_relation(capture, TypedColumns)
    let ledger = layout_ledger(100000, 100000, 100000)
    let physical = {
      ..layout_allocation(100000, 100000, 100000),
      ledger: Some(ledger),
    }
    let logical = ordered_row_budget(110L, 57L, bytes=21L)
    let trace = { chunks: 0, selected: 0, rejected: 0, }
    let output = ext_run_batch(plan, input, width, logical, physical, trace).unwrap()
    assert_eq((trace.selected, trace.rejected), (2, 2))
    assert_eq(trace.chunks, if width == 1 { 2 } else { 1 })
    assert_eq((logical.work, logical.peak, logical.live), (110L, 57L, 0L))
    for (row, numbers) in [(0, [5.0, 0.0, 2.0]), (1, [1.5, 1.0, 3.0])] {
      for column in 0..<3 {
        assert_true(
          layout_cell(output, row, column) is Some(Number(n)) &&
          n == numbers[column],
        )
        assert_true(
          expected.rows[row][column] is Number(n) && n == numbers[column],
        )
      }
    }
    release_layout_columns(output)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  }
}

///|
test "batch selection checks undemanded vocabulary before execution" {
  let owner = row_owner(",{\"derive\":{\"x\":\"if(TRUE, a, coalesce(b, 7))\"}}")
  assert_true(
    ext_prepare_batch(
      row_kernel(owner, 1),
      { remaining: 100000, max_frames: 100, },
      { limit: 100000, live: 0, peak: 0, },
    )
    is Ok(None),
  )
  assert_true(
    ext_prepare_batch(
      row_kernel(owner, 1),
      { remaining: 0, max_frames: 100, },
      { limit: 100000, live: 0, peak: 0, },
    )
    is Err(RowLimit),
  )
}

///|
test "typed batch temporary buffers enforce exact capacity and never fallback" {
  let owner = row_owner(
    ",{\"derive\":[{\"x\":\"if(a > 0, a + 1, b + 2)\"},{\"a\":\"if(x > 2, x / 2, x + 3)\"}]}",
  )
  let plan = ext_test_batch_plan(owner)
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  for width in [1, 7, 1000] {
    // Output: 3 columns * 2 rows * 9 bytes. Two numeric slot+mask
    // buffers: 2 * active lanes * (9+1). Borrowed input is not this ledger's owner.
    let peak = 54 + 20 * Int::min(width, 2)
    for (cap, succeeds) in [(peak - 1, false), (peak, true)] {
      let ledger = layout_ledger(100000, cap, 100000)
      let b = ordered_row_budget(110L, 57L)
      let result = ext_run_choice(
        Typed(plan),
        layout_relation(captured, TypedColumns),
        width,
        b,
        { ..layout_allocation(100000, 100000, 100000), ledger: Some(ledger), },
        { chunks: 0, selected: 0, rejected: 0, },
      )
      if succeeds {
        release_layout_columns(result.unwrap())
        assert_eq(ledger.bytes.peak, peak)
        assert_eq(b.work, 110L)
      } else {
        assert_true(result is Err(RowLimit))
        assert_true(b.failed)
      }
      assert_eq((b.live, ledger.slots.live, ledger.bytes.live), (0L, 0, 0))
    }
  }
}

///|
test "typed nullable masks empty input and failures across width seven" {
  for
    (data, failure_row) in [
      ("", -1),
      ("{\"a\":null,\"b\":null}", -1),
      (
        Array::makei(9, i => {
          if i == 7 {
            "{\"a\":null,\"b\":0}"
          } else {
            "{\"a\":1,\"b\":null}"
          }
        }).join(","),
        7,
      ),
      (
        Array::makei(9, i => {
          if i == 6 {
            "{\"a\":null,\"b\":0}"
          } else {
            "{\"a\":1,\"b\":null}"
          }
        }).join(","),
        6,
      ),
    ] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[" +
      data +
      "]},\"as\":\"seed\"},{\"derive\":[{\"x\":\"if(a > 0, a + 1, 1 / b)\"}]}]",
    )
    let plan = ext_test_batch_plan(owner)
    let captured = capture_values(
      owner,
      0,
      max_rows=9,
      run_limits().input_values,
    ).unwrap()
    for width in [1, 7, 1000] {
      let b = ext_batch_budget(9, 10000L, 10000L)
      let reference_budget = ext_batch_budget(9, 10000L, 10000L)
      let reference = run_ordered_rows(
        owner,
        row_capture(owner),
        reference_budget,
      )
      let ledger = layout_ledger(100000, 100000, 100000)
      let trace = { chunks: 0, selected: 0, rejected: 0, }
      let result = ext_run_choice(
        Typed(plan),
        layout_relation(captured, TypedColumns),
        width,
        b,
        { ..layout_allocation(100000, 100000, 100000), ledger: Some(ledger), },
        trace,
      )
      if failure_row >= 0 {
        assert_true(
          result
          is Err(Evaluation(r, 0, { kind: Scalar(ArithmeticFailure), .. })) &&
          r == failure_row,
        )
        assert_true(
          reference
          is Err(Evaluation(r, 0, { kind: Scalar(ArithmeticFailure), .. })) &&
          r == failure_row,
        )
      } else {
        let output = result.unwrap()
        assert_eq(output.count, if data == "" { 0 } else { 1 })
        if output.count == 1 {
          assert_true(layout_cell(output, 0, 2) is Some(Null))
          assert_eq((trace.selected, trace.rejected), (0, 1))
        }
        assert_true(reference is Ok(_))
        release_layout_columns(output)
      }
      assert_eq(
        (b.work, b.peak, b.live),
        (reference_budget.work, reference_budget.peak, 0L),
      )
      assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    }
  }
}

///|
test "preselected batch and ordinary row operation share one owned private chain" {
  let owner = row_owner(
    ",{\"derive\":[{\"x\":\"if(a >= 0, a + 1, 1 / 0)\"}]},{\"derive\":{\"y\":\"coalesce(x, 7)\"}}",
  )
  let choose = fn(step) {
    ext_choose_batch(
      row_kernel(owner, step),
      { remaining: 100000, max_frames: 100, },
      { limit: 100000, live: 0, peak: 0, },
    ).unwrap()
  }
  let first = choose(1)
  let second = choose(2)
  assert_true(first is Typed(_))
  assert_true(second is Row(_))
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  for width in [1, 7, 1000] {
    let ledger = layout_ledger(100000, 100000, 100000)
    let physical = {
      ..layout_allocation(100000, 100000, 100000),
      work: { remaining: 100000, max_frames: 100, },
      ledger: Some(ledger),
    }
    let trace = { chunks: 0, selected: 0, rejected: 0, }
    let output = ext_run_choice(
      first,
      layout_relation(captured, TypedColumns),
      width,
      ordered_row_budget(10000L, 10000L),
      physical,
      trace,
    ).unwrap()
    let producer = LayoutRelation::{
      candidate: TypedColumns,
      owner,
      id: @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
      ),
      names: ["a", "b", "x"],
      storage: output,
    }
    let chunks = trace.chunks
    let result = ext_run_choice(
      second,
      producer,
      width,
      ordered_row_budget(10000L, 10000L),
      physical,
      trace,
    ).unwrap()
    assert_eq(trace.chunks, chunks)
    assert_true(layout_cell(result, 0, 3) is Some(Number(2.0)))
    assert_true(layout_cell(result, 1, 3) is Some(Number(1.0)))
    release_layout_columns(output)
    assert_true(layout_cell(result, 0, 3) is Some(Number(2.0)))
    release_layout_columns(result)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  }
}
