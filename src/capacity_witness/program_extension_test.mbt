///|
test "Program extension preserves claim coordinates and exact admitted limits" {
  let witnesses = mixed_witnesses()
  let (preserved, first) = mixed_program_fixture(0)
  witnesses[1] = preserved
  let mixed = check_mixed_claims(witnesses, mixed_artifacts(), mixed_caps()).unwrap()
  let base = check_mixed_program_claims(mixed, [first], {
    max_witnesses: 8,
    max_references: 100,
  }).unwrap()
  let (_, added) = mixed_program_fixture(1)
  // The added source proof has three declared dependencies and two repeated
  // input occurrences. Both are charged, but neither changes old coordinates.
  let caps : ClosureLimits = {
    max_witnesses: 10,
    max_references: program_claim_reference_count(base) + 5,
  }
  let result = extend_program_claims(base, [added], caps).unwrap()
  let extended = program_claim_mixed(result).unwrap()
  assert_eq(claim_count(program_claim_arithmetic(result)), 6)
  assert_eq(program_claim_reference_count(result), caps.max_references)
  for i in 0..<5 {
    assert_true(
      physical_equal(
        claim_at(program_claim_arithmetic(result), i).unwrap(),
        witnesses[i],
      ),
    )
  }
  for i in 0..<2 {
    assert_true(
      physical_equal(
        mixed_limit_at(extended, i).unwrap(),
        mixed_limit_at(mixed, i).unwrap(),
      ),
    )
  }
  for i in [0, 4] {
    assert_true(
      physical_equal(
        mixed_enforced_limit(extended, i).unwrap(),
        mixed_enforced_limit(mixed, i).unwrap(),
      ),
    )
  }
  assert_true(physical_equal(program_claim_proof_at(result, 1).unwrap(), first))
  assert_true(physical_equal(program_claim_proof_at(result, 5).unwrap(), added))
  assert_eq(program_proof_input_count(added), 2)
  assert_true(mixed_enforced_limit(extended, 5) is None)
  assert_eq(claim_count(program_claim_arithmetic(base)), 5)
  assert_true(
    extend_program_claims(base, [added], { ..caps, max_witnesses: 9, })
    is Err(_),
  )
  assert_true(
    extend_program_claims(base, [added], {
      ..caps,
      max_references: caps.max_references - 1,
    })
    is Err(_),
  )
  assert_true(
    extend_program_claims(base, [first], {
      max_witnesses: 100,
      max_references: 1000,
    })
    is Err(Arithmetic(_)),
  )
  let (_, missing) = mixed_program_fixture(2)
  assert_true(
    extend_program_claims(base, [missing], {
      max_witnesses: 100,
      max_references: 1000,
    })
    is Err(Program(MissingProgramInput(_, _))),
  )
  assert_true(
    extend_program_claims(base, [], { max_witnesses: -1, max_references: 100, })
    is Err(InvalidLimits),
  )
}

///|
test "ordinary Program extension rechecks forward and repeated input dependencies" {
  let (witnesses, proofs) = program_fixture_claims()
  let host = witnesses[witnesses.length() - 1]
  let base = check_program_claims(
    check_arithmetic_claims([host], {
      max_witnesses: 100,
      max_references: 1000,
    }).unwrap(),
    [],
    { max_witnesses: 100, max_references: 1000, },
  ).unwrap()
  let extended = extend_program_claims(base, proofs, {
    max_witnesses: 100,
    max_references: 1000,
  }).unwrap()
  assert_true(program_claim_mixed(extended) is None)
  assert_true(
    physical_equal(
      claim_at(program_claim_arithmetic(extended), 0).unwrap(),
      host,
    ),
  )
  for i, proof in proofs {
    assert_true(
      physical_equal(program_claim_proof_at(extended, i + 1).unwrap(), proof),
    )
  }
}
