///|
test "values wire resolution derives fixed identities without supplied proofs" {
  let cells = wire_bound_cells()
  let payload : @wire.Limits = { max_bytes: 25, max_nodes: 7, max_depth: 2, }
  let metadata : @wire.LimitLimits = {
    max_bytes: 784,
    max_nodes: 25,
    max_depth: 4,
    max_candidates: 1,
  }
  let result = resolve_values_wire_limit(cells, 0, payload, metadata).unwrap()
  assert_true(physical_equal(result.bound.cells, cells))
  assert_eq(
    (result.bound.bytes, result.bound.nodes, result.bound.depth),
    (25, 7, 2),
  )
  assert_eq(
    @wire.cid(@wire.program_proof_witness(result.bound.proof)),
    "sha256:15622500b68d7891fc269aca0d7cb37561307a912578cd88f3d2dadcc54fb56e",
  )
  assert_eq(
    @wire.limit_cid(result.limit),
    "sha256:0e8b43abe5a8df37e7afe6b1dea944021d4db74a9d17fec465fb05c7671b56c2",
  )
  let changed = wire_bound_cells(supplied=Some(cursor("{\"n\":100}")))
  assert_true(
    resolve_values_wire_limit(changed, 0, payload, metadata) is Err(_),
  )
  let changed_result = resolve_values_wire_limit(
    changed,
    0,
    { ..payload, max_bytes: 29, },
    metadata,
  ).unwrap()
  assert_eq(changed_result.bound.bytes, 29)
  assert_true(
    @wire.limit_cid(changed_result.limit) != @wire.limit_cid(result.limit),
  )
  for
    short in [
      { ..payload, max_bytes: 24, },
      { ..payload, max_nodes: 6, },
      { ..payload, max_depth: 1, },
      { ..payload, max_bytes: -1, },
    ] {
    assert_true(resolve_values_wire_limit(cells, 0, short, metadata) is Err(_))
  }
  for
    short in [
      { ..metadata, max_bytes: 783, },
      { ..metadata, max_nodes: 24, },
      { ..metadata, max_depth: 3, },
      { ..metadata, max_candidates: 0, },
      { ..metadata, max_nodes: -1, },
    ] {
    assert_true(resolve_values_wire_limit(cells, 0, payload, short) is Err(_))
  }
  for index in [-1, 1, 10000] {
    assert_true(
      resolve_values_wire_limit(cells, index, payload, metadata) is Err(_),
    )
  }
  assert_true(resolve_values_wire_limit(cells, 0, payload, metadata) is Ok(_))
}

///|
test "empty values derive a byte proof for brackets rather than a zero row proof" {
  let cells = check_program_operation_cells(
    cells_fixture(
      "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"default\":7}",
      "[]",
    ),
    10000000,
    100,
  ).unwrap()
  let result = resolve_values_wire_limit(
    cells,
    0,
    { max_bytes: 2, max_nodes: 1, max_depth: 1, },
    { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_candidates: 1, },
  ).unwrap()
  assert_eq(
    (result.bound.bytes, result.bound.nodes, result.bound.depth),
    (2, 1, 1),
  )
  assert_eq(@wire.value(@wire.program_proof_witness(result.bound.proof)), 2L)
  assert_eq(
    @wire.unit(@wire.program_proof_witness(result.bound.proof)),
    @derivation.Bytes,
  )
  // Independent supplied-claim path must agree without being the expectation
  // source for the fixed identity vector above.
  let applied = check_values_wire_bound(cells, 0, values_wire_claim(2), 2, 1, 1).unwrap()
  assert_eq(
    @wire.cid(@wire.program_proof_witness(result.bound.proof)),
    @wire.cid(@wire.program_proof_witness(applied.proof)),
  )
}
