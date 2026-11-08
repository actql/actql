///|
fn working_growth_fixture(
  reserve : (Int64) -> Result[Unit, WorkspaceGrowthIssue],
) -> WorkspaceGrowth {
  {
    initial_slots: 4,
    initial_live: 8L,
    live_ceiling: 1000L,
    reserve,
    reserve_retained: None,
    slots: 0,
    logical: 0L,
    text: 0L,
    text_peak: 0L,
    slot_peak: 0,
    logical_peak: 0L,
    funded: 0L,
    used: 0L,
    retained_funded: 0L,
    retained_outputs: None,
    busy: false,
    failed: false,
  }
}

///|
test "working growth reserves actual slots before mutation and retains funding through release" {
  let requests : Array[Int64] = []
  let growth = working_growth_fixture(bytes => {
    requests.push(bytes)
    Ok(())
  })
  let workspace = { ..row_workspace(100), growth: Some(growth), }
  assert_true(reserve_slots(workspace, 4))
  assert_eq(requests, [])
  assert_true(reserve_slots(workspace, 3))
  assert_eq(requests, [768L])
  release_slots(workspace, 5)
  assert_eq(growth.slots, 2)
  assert_eq(growth.funded, 768L)
  assert_true(reserve_slots(workspace, 5))
  assert_eq(requests, [768L])
  assert_true(reserve_slots(workspace, 1))
  assert_eq(requests, [768L, 1024L])
}

///|
test "working growth refusal leaves the constructor slots unallocated and is sticky" {
  let requests = Ref(0)
  let growth = working_growth_fixture(_ => {
    requests.val += 1
    Err(WorkspaceUnavailable)
  })
  let workspace = { ..row_workspace(100), growth: Some(growth), }
  assert_true(reserve_slots(workspace, 4))
  assert_false(reserve_slots(workspace, 1))
  assert_eq(workspace.live, 4)
  assert_eq(growth.slots, 4)
  assert_eq(growth.funded, 0L)
  assert_false(reserve_slots(workspace, 2))
  assert_eq(requests.val, 1)
  release_slots(workspace, 4)
  assert_eq(workspace.live, 0)
}

///|
test "working growth composes logical roots and slots without returning spent backing" {
  let requests : Array[Int64] = []
  let growth = working_growth_fixture(bytes => {
    requests.push(bytes)
    Ok(())
  })
  let limits : LogicalLimits = {
    max_input_rows: 1L,
    max_value_bytes: 100L,
    max_live_value_bytes: 100L,
    max_work: 1000L,
  }
  let budget = logical_budget(limits, 100, 100, 10, growth=Some(growth)).unwrap()
  let root = reserve_logical_bytes(budget, 10L).unwrap()
  assert_eq(requests, [528L])
  let workspace = { ..row_workspace(100), growth: Some(growth), }
  assert_true(reserve_slots(workspace, 5))
  assert_eq(requests, [528L, 784L])
  release_logical_root(budget, root).unwrap()
  release_slots(workspace, 5)
  assert_eq(growth.logical, 0L)
  assert_eq(growth.slots, 0)
  assert_eq(growth.funded, 784L)
  assert_true(reserve_slots(workspace, 5))
  assert_eq(requests.length(), 2)
}

///|
test "working growth cannot accept a callback that reenters the same attachment" {
  let reentered = Ref(true)
  let owner : Ref[WorkspaceGrowth?] = Ref(None)
  let growth = working_growth_fixture(_ => {
    reentered.val = grow_workspace(owner.val.unwrap(), 20, 0L)
    Ok(())
  })
  owner.val = Some(growth)
  let workspace = { ..row_workspace(100), growth: Some(growth), }
  assert_false(reserve_slots(workspace, 5))
  assert_false(reentered.val)
  assert_eq(workspace.live, 0)
  assert_eq(growth.slots, 0)
  assert_eq(growth.funded, 0L)
}

///|
test "working accumulator growth funds the same original root before mutation" {
  let requests : Array[Int64] = []
  let growth = working_growth_fixture(bytes => {
    requests.push(bytes)
    Ok(())
  })
  let limits : LogicalLimits = {
    max_input_rows: 1L,
    max_value_bytes: 100L,
    max_live_value_bytes: 100L,
    max_work: 1000L,
  }
  let budget = logical_budget(limits, 100, 100, 10, growth=Some(growth)).unwrap()
  let root = reserve_logical_bytes(budget, 2L).unwrap()
  let lease = register_scope_root(expression_roots(budget, 0), root).unwrap()
  grow_object_root(lease, 10L).unwrap()
  assert_eq(requests, [1056L])
  assert_eq(root.bytes, 12L)
  assert_eq(growth.logical, 12L)
  release_expression_root(lease).unwrap()
  assert_eq(growth.logical, 0L)
  assert_eq(budget.live, 0L)
  assert_eq(growth.funded, 1056L)
}

///|
test "measured row framing counts escaping duplicates and overflow without policy maxima" {
  // Each actual key is counted separately, even when both selected values
  // refer to the same measured five-byte cell. Punctuation is included.
  let first = measured_row_wire_add(3, "a", 5, 100).unwrap()
  let second = measured_row_wire_add(first, "b", 5, 100).unwrap()
  assert_eq(second, 33)
  assert_true(
    second >= @utf8.encode("{\"a\":\"xxx\",\"b\":\"xxx\"}").length() + 1,
  )
  let escaped = measured_row_wire_add(3, "é\"\n😀", 5, 100).unwrap()
  assert_true(
    escaped >= @utf8.encode("{\"é\\\"\\n😀\":\"xxx\"}").length() + 1,
  )
  assert_true(measured_row_wire_add(3, "a", 5, 17) is None)
  assert_true(measured_row_wire_add(2147483647, "a", 5, 2147483647) is None)
}

///|
test "working accumulator refusal leaves original root unchanged for cleanup" {
  let growth = working_growth_fixture(_ => Err(WorkspaceUnavailable))
  let limits : LogicalLimits = {
    max_input_rows: 1L,
    max_value_bytes: 100L,
    max_live_value_bytes: 100L,
    max_work: 1000L,
  }
  let budget = logical_budget(limits, 100, 100, 10, growth=Some(growth)).unwrap()
  let root = reserve_logical_bytes(budget, 2L).unwrap()
  let lease = register_scope_root(expression_roots(budget, 0), root).unwrap()
  assert_true(grow_object_root(lease, 10L) is Err(LiveValueLimit))
  assert_eq(root.bytes, 2L)
  assert_eq(budget.live, 2L)
  assert_eq(growth.logical, 2L)
  release_expression_root(lease).unwrap()
  assert_eq(growth.logical, 0L)
  assert_eq(budget.live, 0L)
}

///|
test "working attachment preserves generic callers explicit finite execution" {
  let sequence = prepared_sequence(row_owner(",{\"select\":[\"a\"]}"))
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["select_1"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  let calls = Ref(0)
  let attached = bind_generated_workspace_growth(generated, limits, 1000000L, _ => {
    calls.val += 1
    Err(WorkspaceUnavailable)
  }).unwrap()
  // The synchronous caller keeps its own explicit bounds and allocates no
  // dynamic reservation. It does not reinterpret this attachment as authority.
  let completed = execute_generated_sequence(attached, [], limits).unwrap()
  let output = test_row_output(completed_output(completed, Step(1)).unwrap())
  assert_eq(output.rows.length(), 2)
  let mut one = false
  let mut zero = false
  for row in output.rows {
    if row[0] is Number(1.0) {
      assert_false(one)
      one = true
    } else if row[0] is Number(0.0) {
      assert_false(zero)
      zero = true
    } else {
      fail("original finite fixture values required")
    }
  }
  assert_true(one && zero)
  assert_eq(calls.val, 0)
}
