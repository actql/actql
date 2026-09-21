///|
test "ordered bindings advance one expression transition and retain roots" {
  let snapshot : Map[String, Value] = {
    "left": runtime_vector([1.0, 2.0, 3.0, 4.0]),
    "right": runtime_vector([4.0, 3.0, 2.0, 1.0]),
  }
  let logical = test_logical_budget(10000L, 10000L)
  let scope = expression_roots(logical, 100)
  let workspace = { limit: 1000, live: 0, peak: 0, }
  let execution = start_ordered_bindings_execution(
    [
      ("score", lowered_vector_score("dot")),
      ("joined", lowered_vector_concat()),
    ],
    snapshot,
    { remaining: 10000, max_frames: 100, },
    workspace,
    scope,
    0,
  )
  let mut advances = 0
  let mut completed : (Array[Value], Array[ExpressionRootLease])? = None
  while completed is None {
    advances += 1
    match advance_ordered_bindings_execution(execution).unwrap() {
      OrderedBindingsContinue => ()
      OrderedBindingsComplete(values, roots) =>
        completed = Some((values, roots))
    }
  }
  let (values, roots) = completed.unwrap()
  assert_true(advances > 2)
  assert_true(values[0] is Number(20.0))
  guard values[1] is Captured(@admitted.Vector(vector)) else {
    fail("expected vector")
  }
  assert_eq(@admitted.elements(vector), [4.0, 3.0, 2.0, 1.0, 1.0, 2.0, 3.0, 4.0])
  assert_eq(roots.length(), 2)
  assert_true(logical.live > 0L)
  for root in roots {
    release_expression_root(root).unwrap()
  }
  release_slots(workspace, values.length() * 2)
  assert_eq(logical.live, 0L)
  assert_eq(workspace.live, 0)
}

///|
test "ordered bindings cancellation reclaims active and completed slots" {
  let snapshot : Map[String, Value] = {
    "left": runtime_vector([1.0, 2.0, 3.0, 4.0]),
    "right": runtime_vector([4.0, 3.0, 2.0, 1.0]),
  }
  let logical = test_logical_budget(10000L, 10000L)
  let scope = expression_roots(logical, 100)
  let workspace = { limit: 1000, live: 0, peak: 0, }
  let execution = start_ordered_bindings_execution(
    [
      ("score", lowered_vector_score("dot")),
      ("joined", lowered_vector_concat()),
    ],
    snapshot,
    { remaining: 10000, max_frames: 100, },
    workspace,
    scope,
    0,
  )
  while execution.slot == 0 || execution.active is None {
    assert_true(
      advance_ordered_bindings_execution(execution)
      is Ok(OrderedBindingsContinue),
    )
  }
  assert_true(logical.live > 0L)
  assert_true(workspace.live > 0)
  cancel_ordered_bindings_execution(execution)
  assert_eq(logical.live, 0L)
  assert_eq(workspace.live, 0)
  assert_true(advance_ordered_bindings_execution(execution) is Err(InvalidRows))
}
