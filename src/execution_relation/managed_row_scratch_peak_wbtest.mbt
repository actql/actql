///|
test "managed scratch keeps the first large row funded across smaller and larger later rows" {
  let growth = {
    ..working_growth_fixture(_ => Ok(())),
    live_ceiling: 1048576L,
    retained_outputs: Some(1000L),
  }
  let budget = value_budget(stream_value_limits()).unwrap()
  budget.retention = Some(growth)
  budget.row_scratch_start = Some((0, 0))
  let rows = [(2, 100), (2, 1), (2, 200), (2, 1)]
  let mut peak = 0L
  for index, (nodes, text) in rows {
    budget.nodes += nodes
    budget.text += text
    let row_bytes = output_retention_required_bytes(nodes, text).unwrap()
    peak = Int64::max(peak, row_bytes)
    assert_true(fund_output_retention(budget, budget.nodes, budget.text))
    let copies = if index == 0 { 1L } else { 2L }
    assert_eq(budget.row_scratch_peak, peak)
    assert_eq(budget.retention_funded, copies * peak)
    assert_eq(growth.retained_outputs, Some(1000L + copies * peak))
    budget.row_scratch_start = Some((budget.nodes, budget.text))
  }
  assert_eq((budget.nodes, budget.text), (8, 302))
}

///|
test "managed first row keeps exact quota refusal sticky and later peak overflow closed" {
  for overflow in [false, true] {
    let calls = Ref(0)
    let growth = {
      ..working_growth_fixture(_ => {
        calls.val += 1
        Err(WorkspaceBudgetUnavailable)
      }),
      live_ceiling: 1048576L,
      retained_outputs: Some(0L),
    }
    let budget = value_budget(stream_value_limits()).unwrap()
    budget.retention = Some(growth)
    budget.nodes = 2
    budget.text = 2
    budget.row_scratch_start = Some(if overflow { (1, 1) } else { (0, 0) })
    if overflow {
      budget.row_scratch_peak = 9223372036854775807L
    }
    assert_false(fund_output_retention(budget, budget.nodes, budget.text))
    assert_true(growth.failed)
    assert_eq(growth.retained_outputs, Some(0L))
    assert_eq(budget.retention_funded, 0L)
    let before = calls.val
    assert_false(fund_output_retention(budget, budget.nodes, budget.text))
    assert_eq(calls.val, before)
    if overflow {
      assert_eq(calls.val, 0)
    } else {
      assert_true(calls.val > 0)
    }
  }
}
