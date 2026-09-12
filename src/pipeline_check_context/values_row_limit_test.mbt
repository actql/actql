///|
test "values row selection retains exact count and applicable Host ceiling" {
  let wire = resolve_values_wire_limit(
    wire_bound_cells(),
    0,
    { max_bytes: 25, max_nodes: 7, max_depth: 2, },
    { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_candidates: 1, },
  ).unwrap()
  let limits : @wire.LimitLimits = {
    max_bytes: 1259,
    max_nodes: 100,
    max_depth: 10,
    max_candidates: 2,
  }
  let result = resolve_values_row_limit(wire, limits).unwrap()
  assert_true(physical_equal(result.wire, wire))
  assert_true(
    physical_equal(
      @program.checked_pipeline(result.rows),
      wire.bound.site.pipeline,
    ),
  )
  assert_eq(@program.checked_step(result.rows), wire.bound.site.step)
  assert_true(
    physical_equal(
      @policy.ceiling_policy(@host.ceiling(result.host)),
      wire.policy,
    ),
  )
  let witness = @wire.program_proof_witness(@program.checked_proof(result.rows))
  // Independent Node crypto vectors, not computed from product output.
  assert_eq(
    @wire.cid(witness),
    "sha256:4eeab1520aae127f1de078042f0ec9a4dd9d9841e6b78cf3dbfd23ba7f727554",
  )
  assert_eq(
    @host.cid(result.host),
    "sha256:cc804f91bfb333cce941d90ede1e71d04e829b342464a24e88f237db814f4236",
  )
  assert_eq(
    @wire.limit_cid(result.limit),
    "sha256:5f7e6e782681fe6844158d635b2d3f1644baf671eb2e23203d1afb4c9309391a",
  )
  assert_eq(@wire.value(witness), 3L)
  assert_eq(@derivation.minimum_value(@wire.limit_minimum(result.limit)), 1L)
  assert_eq(@wire.claim_count(@wire.limit_claims(result.limit)), 2)
  assert_eq(@wire.limit_enforcement(result.limit), @wire.EngineAtomic)
  // A limit below the exact count remains an enforcement requirement. This
  // selector neither truncates the input nor certifies successful publication.
  assert_eq(result.wire.bound.bytes, 25)
  for
    short in [
      { ..limits, max_bytes: 1258, },
      { ..limits, max_candidates: 1, },
      { ..limits, max_nodes: 0, },
      { ..limits, max_depth: 0, },
      { ..limits, max_bytes: -1, },
    ] {
    assert_true(resolve_values_row_limit(wire, short) is Err(_))
  }
  assert_true(resolve_values_row_limit(wire, limits) is Ok(_))
}

///|
test "empty values select the zero Program count without omitting Host candidate" {
  let cells = check_program_operation_cells(
    cells_fixture(
      "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"default\":7}",
      "[]",
    ),
    10000000,
    100,
  ).unwrap()
  let limits : @wire.LimitLimits = {
    max_bytes: 2000,
    max_nodes: 100,
    max_depth: 10,
    max_candidates: 2,
  }
  let wire = resolve_values_wire_limit(
    cells,
    0,
    { max_bytes: 2, max_nodes: 1, max_depth: 1, },
    limits,
  ).unwrap()
  let result = resolve_values_row_limit(wire, limits).unwrap()
  assert_eq(@derivation.minimum_value(@wire.limit_minimum(result.limit)), 0L)
  assert_eq(@wire.claim_count(@wire.limit_claims(result.limit)), 2)
  assert_eq(result.wire.bound.bytes, 2)
}
