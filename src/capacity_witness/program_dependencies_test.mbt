///|
fn dependency_source_fixture() -> ProgramClaims {
  let witnesses = mixed_witnesses()
  let (preserved, proof) = mixed_program_fixture(0)
  witnesses[1] = preserved
  check_mixed_program_claims(
    check_mixed_claims(witnesses, mixed_artifacts(), mixed_caps()).unwrap(),
    [proof],
    { max_witnesses: 100, max_references: 1000, },
  ).unwrap()
}

///|
test "dependency union retains source occurrences and remaps enforced limit candidates" {
  let closure : ClosureLimits = { max_witnesses: 100, max_references: 1000, }
  let first = dependency_source_fixture()
  let second = dependency_source_fixture()
  // A distinct ordinary prefix forces every imported candidate coordinate to
  // move. Expected wire artifacts remain the independently pinned fixtures.
  let (ordinary, ordinary_proofs) = program_fixture_claims()
  let prefix = check_program_claims(
    check_arithmetic_claims(ordinary, closure).unwrap(),
    ordinary_proofs,
    closure,
  ).unwrap()
  let joined = collect_program_dependencies(
    [prefix, first, second, first],
    closure,
    max_work=10000,
  ).unwrap()
  assert_eq(program_dependency_source_count(joined), 4)
  for (index, source) in [(0, prefix), (1, first), (2, second), (3, first)] {
    assert_true(
      physical_equal(
        program_dependency_source_at(joined, index).unwrap(),
        source,
      ),
    )
  }
  assert_true(!physical_equal(first, second))
  let claims = program_dependency_claims(joined)
  let arithmetic = program_claim_arithmetic(claims)
  for index in 0..<ordinary.length() {
    assert_true(
      physical_equal(claim_at(arithmetic, index).unwrap(), ordinary[index]),
    )
  }
  let mixed = program_claim_mixed(claims).unwrap()
  assert_eq(mixed_limit_count(mixed), 2)
  let artifacts = mixed_artifacts()
  for index in 0..<2 {
    let limit = mixed_limit_at(mixed, index).unwrap()
    assert_true(physical_equal(limit_claims(limit), arithmetic))
    let writer = @encode.writer(100000, 10000, 100)
    emit_limit(limit, writer)
    assert_eq(@encode.finish(writer), @utf8.decode(artifacts[index].0))
    assert_eq(limit_cid(limit), artifacts[index].1)
  }
  let source_arithmetic = program_claim_arithmetic(first)
  for index in 0..<claim_count(source_arithmetic) {
    let witness = claim_at(source_arithmetic, index).unwrap()
    let merged_index = claim_index(arithmetic, cid(witness)).unwrap()
    assert_true(
      physical_equal(claim_at(arithmetic, merged_index).unwrap(), witness),
    )
    let before = mixed_enforced_limit(
      program_claim_mixed(first).unwrap(),
      index,
    )
    let after = mixed_enforced_limit(mixed, merged_index)
    match (before, after) {
      (Some(a), Some(b)) => assert_eq(limit_cid(a), limit_cid(b))
      (None, None) => ()
      _ => fail("enforced limit binding changed")
    }
  }
  assert_true(program_dependency_source_at(joined, 4) is None)
  // Duplicate body sharing never removes repeated sources or proof operands.
  let (_, proof) = mixed_program_fixture(1)
  let extended = extend_program_claims(claims, [proof], closure).unwrap()
  let index = claim_index(
    program_claim_arithmetic(extended),
    cid(program_proof_witness(proof)),
  ).unwrap()
  assert_eq(
    program_proof_input_count(program_claim_proof_at(extended, index).unwrap()),
    2,
  )
}

///|
test "dependency union reserves graph work before traversing retained references" {
  let caps : ClosureLimits = { max_witnesses: 100, max_references: 1000, }
  let source = dependency_source_fixture()
  let mixed = program_claim_mixed(source).unwrap()
  // Fixture has five witnesses, two limits, and one ordinary Program proof.
  // Count the union's phases independently of its returned remaining budget:
  // source visits/retention + input scans + arithmetic graph + candidate remapping
  // + enforced bindings + full Program graph closure.
  let arithmetic = program_claim_arithmetic(source)
  let n = claim_count(arithmetic)
  let r = claim_reference_count(arithmetic)
  let mut candidates = 0
  for index in 0..<mixed_limit_count(mixed) {
    candidates += @arithmetic.minimum_candidate_count(
      limit_minimum(mixed_limit_at(mixed, index).unwrap()),
    )
  }
  let inputs = program_proof_input_count(
    program_claim_proof_at(source, 1).unwrap(),
  )
  let expected = 4 +
    2 * (n + 2) +
    (n + r) +
    2 * candidates +
    n +
    (n + 3) +
    r +
    candidates +
    inputs
  let result = collect_program_dependencies(
    [source, source],
    caps,
    max_work=expected,
  ).unwrap()
  assert_eq(program_dependency_work(result), expected)
  assert_true(
    collect_program_dependencies([source, source], caps, max_work=expected - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_program_dependencies(
      [source],
      { ..caps, max_witnesses: n + 1, },
      max_work=10000,
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_program_dependencies(
      [source],
      { ..caps, max_references: r + candidates - 1, },
      max_work=10000,
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_program_dependencies([source], caps, max_work=-1)
    is Err(InvalidLimits),
  )
}
