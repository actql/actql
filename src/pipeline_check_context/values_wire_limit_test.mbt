///|
test "values wire limit retains its bound and policy with independent canonical identity" {
  let cells = wire_bound_cells()
  let bound = check_values_wire_bound(cells, 0, values_wire_claim(25), 25, 7, 2).unwrap()
  let limits : @wire.LimitLimits = {
    max_bytes: 784,
    max_nodes: 25,
    max_depth: 4,
    max_candidates: 1,
  }
  let resolved = create_values_wire_limit(bound, limits).unwrap()
  assert_true(physical_equal(resolved.bound, bound))
  assert_eq(
    @wire.limit_cid(resolved.limit),
    "sha256:0e8b43abe5a8df37e7afe6b1dea944021d4db74a9d17fec465fb05c7671b56c2",
  )
  assert_eq(@wire.limit_subject(resolved.limit), "values:checked-step:0:wire")
  assert_eq(@wire.limit_enforcement(resolved.limit), @wire.EngineAtomic)
  let out = @encode.measuring_writer(784, 25, 4)
  @wire.emit_limit(resolved.limit, out)
  assert_eq(@encode.finish_measurement_usage(out), (784, 25, 4))
  let claims = @wire.limit_claims(resolved.limit)
  assert_eq(@wire.claim_count(claims), 1)
  assert_eq(
    @wire.cid(@wire.claim_at(claims, 0).unwrap()),
    @wire.cid(@wire.program_proof_witness(bound.proof)),
  )
  // A second construction retains the same selected policy owner, not merely CID.
  let again = create_values_wire_limit(bound, limits).unwrap()
  assert_true(physical_equal(again.policy, resolved.policy))
  for
    short in [
      { ..limits, max_bytes: 783, },
      { ..limits, max_nodes: 24, },
      { ..limits, max_depth: 3, },
      { ..limits, max_candidates: 0, },
      { ..limits, max_candidates: -1, },
    ] {
    assert_true(create_values_wire_limit(bound, short) is Err(_))
  }
  assert_true(create_values_wire_limit(bound, limits) is Ok(_))
}
