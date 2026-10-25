///|
test "Values limit retains typed construction and independent complete-wire bounds" {
  let cells = wire_bound_cells()
  let bound = check_values_wire_bound(cells, 0, values_wire_claim(25), 25, 7, 2).unwrap()
  let limits : @wire.LimitLimits = {
    max_bytes: 784,
    max_nodes: 25,
    max_depth: 4,
    max_candidates: 1,
  }
  let result = create_values_wire_limit(bound, limits).unwrap()
  assert_true(physical_equal(result.bound, bound))
  // These are the independently pinned complete wire size/node counts minus
  // the fixed 95-byte/one-node identity field, not product-derived expectations.
  assert_eq(@wire.limit_creation_usage(result.limit), Some((689, 24)))
  assert_eq(
    @wire.limit_cid(result.limit),
    "sha256:0e8b43abe5a8df37e7afe6b1dea944021d4db74a9d17fec465fb05c7671b56c2",
  )
  assert_eq(@wire.measure_limit(result.limit, 784, 25, 4), (784, 25, 4))
  for (bytes, nodes, depth) in [(783, 25, 4), (784, 24, 4), (784, 25, 3)] {
    try @wire.measure_limit(result.limit, bytes, nodes, depth) catch {
      @encode.OutputLimit => ()
      _ => fail("Expected the original complete-wire limit refusal")
    } noraise {
      _ => fail("Expected the complete-wire limit to refuse")
    }
  }
  assert_eq(@wire.measure_limit(result.limit, 784, 25, 4), (784, 25, 4))
}
