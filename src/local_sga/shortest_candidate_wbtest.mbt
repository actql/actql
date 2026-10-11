///|
test "Shortest costs round each edge and keep selected overrange separate from invalid input" {
  let initial = FiniteShortestCost(9007199254740992.0)
  let one = shortest_cost_add(initial, 1.0).unwrap()
  assert_true(one is FiniteShortestCost(9007199254740992.0))
  assert_true(
    shortest_cost_add(one, 1.0).unwrap()
    is FiniteShortestCost(9007199254740992.0),
  )
  // Rounding once after exact summation would instead give 2^53 + 2.
  assert_true(
    shortest_cost_add(initial, 2.0).unwrap()
    is FiniteShortestCost(9007199254740994.0),
  )
  let maximum = FiniteShortestCost(1.7976931348623157e308)
  let overrange = shortest_cost_add(maximum, 1.7976931348623157e308).unwrap()
  assert_true(overrange is OverrangeShortestCost)
  assert_true(
    shortest_cost_add(overrange, 0.0).unwrap() is OverrangeShortestCost,
  )
  assert_eq(shortest_cost_compare(maximum, overrange), -1)
  assert_eq(shortest_cost_compare(overrange, overrange), 0)
  for invalid in [-1.0, 1.0 / 0.0, 0.0 / 0.0] {
    assert_true(
      shortest_cost_add(FiniteShortestCost(0.0), invalid)
      is Err(InvalidShortestCost),
    )
    assert_true(
      shortest_cost_add(overrange, invalid) is Err(InvalidShortestCost),
    )
  }
}

///|
fn shortest_comparison_fixture(
  source : GraphReadSource,
  left : ShortestCandidate,
  right : ShortestCandidate,
  quantum : Int,
  max_work : Int,
) -> (Int, Int) raise {
  let cursor = prepare_shortest_comparison(source, left, right, max_work).unwrap()
  let mut total = 0
  for _ in 0..<10000 {
    match advance_shortest_comparison(cursor, quantum) {
      ShortestComparisonContinue(work) => {
        assert_true(work > 0 && work <= quantum)
        total += work
      }
      ShortestComparisonComplete(order, work) => {
        assert_true(work >= 0 && work <= quantum)
        total += work
        cleanup_shortest_comparison(cursor)
        return (order, total)
      }
      ShortestComparisonFailed(issue, _) => fail(@debug.to_string(issue))
    }
  }
  fail("finite comparison fixture limit")
}

///|
test "Shortest cost and hop ordering have independent exact and one-short work" {
  let storage = union_token_input(union_token_carrier())
  let source = Accumulated(storage)
  let single = {
    path: { nodes: [0], edges: [], cost: None, },
    cost: FiniteShortestCost(0.0),
  }
  let double = {
    path: { nodes: [1, 0], edges: [0], cost: None, },
    cost: FiniteShortestCost(0.0),
  }
  let expensive = { ..double, cost: FiniteShortestCost(1.0), }
  for quantum in [1, 7, 64] {
    // Cost consumes one transition; tied cost then hops consumes exactly two.
    assert_eq(
      shortest_comparison_fixture(source, expensive, double, quantum, 1),
      (1, 1),
    )
    assert_eq(
      shortest_comparison_fixture(source, single, double, quantum, 2),
      (-1, 2),
    )
  }
  for (left, right, available) in [(expensive, double, 0), (single, double, 1)] {
    let cursor = prepare_shortest_comparison(source, left, right, available).unwrap()
    let mut charged = 0
    for _ in 0..<3 {
      match advance_shortest_comparison(cursor, 1) {
        ShortestComparisonContinue(work) => charged += work
        ShortestComparisonFailed(ShortestCandidateWorkLimit, work) => {
          charged += work
          assert_eq(charged, available)
          break
        }
        _ => fail("one-short must report its typed work cause")
      }
    } nobreak {
      fail("one-short did not fail")
    }
    cleanup_shortest_comparison(cursor)
  }
  assert_true(@storage.available(storage))
  @storage.discard(storage)
}

///|
test "Shortest cross-pair identity ties yield inside long Unicode keys and retain borrowed input" {
  let storage = union_token_input(union_token_carrier())
  let source = Accumulated(storage)
  let left = {
    path: { nodes: [1, 0], edges: [0], cost: None, },
    cost: FiniteShortestCost(1.0),
  }
  let right = {
    path: { nodes: [0, 1], edges: [0], cost: None, },
    cost: FiniteShortestCost(1.0),
  }
  let mut previous_work = None
  for quantum in [1, 7, 64] {
    let (order, work) = shortest_comparison_fixture(
      source, left, right, quantum, 10000,
    )
    // The independent keys are x*512 + U+10000 and x*512 + U+E000.
    // Their UTF-16 order is the opposite of scalar-code-point order.
    assert_eq(order, -1)
    if previous_work is Some(expected) {
      assert_eq(work, expected)
    }
    previous_work = Some(work)
  }
  let cursor = prepare_shortest_comparison(source, left, right, 10000).unwrap()
  for _ in 0..<100 {
    assert_true(
      advance_shortest_comparison(cursor, 1) is ShortestComparisonContinue(1),
    )
  }
  assert_true(cursor.identity_unit > 0)
  cleanup_shortest_comparison(cursor)
  cleanup_shortest_comparison(cursor)
  assert_eq(cursor.identity_unit, 0)
  assert_true(
    advance_shortest_comparison(cursor, 1)
    is ShortestComparisonFailed(InvalidShortestCandidateCursor, 0),
  )
  assert_true(@storage.available(storage))
  assert_eq(@storage.node_count(storage), 2)
  assert_eq(@storage.edge_count(storage), 1)
  @storage.discard(storage)
}
