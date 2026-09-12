///|
test "derived preparation orders claims and preserves repeated dependencies" {
  let p = pipeline(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":1}]},"as":"seed"},{"derive":{}},{"append":{"with":"seed"}}]
    ),
  )
  let seed = proof("actql.bound.values", 2, "{\"op\":\"source\"}")
  let id = @wire.cid(@wire.program_proof_witness(seed))
  let sum = proof(
    "actql.bound.append",
    4,
    "{\"left\":\"" + id + "\",\"op\":\"add\",\"right\":\"" + id + "\"}",
    reference="checked-step:2",
    inputs=[id, id],
  )
  for proofs in [[sum, seed], [seed, sum]] {
    let claims = program_claims(proofs)
    let caps : @capacity_program_step.PreparationLimits = {
      max_work: 1000,
      max_input_work: 100,
      max_operand_work: 100,
    }
    let prepared = @capacity_program_step.prepare_derived_applications(
      p, claims, caps,
    ).unwrap()
    assert_true(
      physical_equal(
        @capacity_program_step.application_claims(prepared),
        claims,
      ),
    )
    let arithmetic = @wire.program_claim_arithmetic(claims)
    let first = @capacity_program_step.application_at(
      prepared,
      @wire.claim_index(arithmetic, id).unwrap(),
    ).unwrap()
    let last = @capacity_program_step.application_at(
      prepared,
      @wire.claim_index(arithmetic, @wire.cid(@wire.program_proof_witness(sum))).unwrap(),
    ).unwrap()
    assert_true(
      physical_equal(@capacity_program_step.checked_pipeline(last), p),
    )
    assert_eq(@capacity_program_step.checked_step(last), 2)
    assert_eq(@capacity_program_step.input_count(last), 2)
    for i in 0..<2 {
      assert_true(
        physical_equal(@capacity_program_step.input_at(last, i).unwrap(), first),
      )
    }
    assert_eq(
      @wire.value(
        @wire.program_proof_witness(@capacity_program_step.checked_proof(last)),
      ),
      4,
    )
    let exact : @capacity_program_step.PreparationLimits = {
      max_work: @capacity_program_step.application_work(prepared),
      max_input_work: @capacity_program_step.input_work(first) +
      @capacity_program_step.input_work(last),
      max_operand_work: @capacity_program_step.operand_work(first) +
      @capacity_program_step.operand_work(last),
    }
    assert_true(
      @capacity_program_step.prepare_derived_applications(p, claims, exact)
      is Ok(_),
    )
    assert_true(
      @capacity_program_step.prepare_derived_applications(p, claims, {
        ..exact,
        max_work: exact.max_work - 1,
      })
      is Err(_),
    )
    assert_true(exact.max_input_work > 0)
    assert_true(
      @capacity_program_step.prepare_derived_applications(p, claims, {
        ..exact,
        max_input_work: exact.max_input_work - 1,
      })
      is Err(_),
    )
    assert_true(
      @capacity_program_step.prepare_derived_applications(p, claims, {
        ..exact,
        max_work: -1,
      })
      is Err(InvalidLimits),
    )
  }
}

///|
test "derived preparation rejects false and detached claims rather than returning partial applications" {
  let p = pipeline("[{\"take\":3},{\"take\":2}]")
  let caps : @capacity_program_step.PreparationLimits = {
    max_work: 1000,
    max_input_work: 100,
    max_operand_work: 100,
  }
  let first = proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}")
  let detached = proof(
    "actql.bound.take",
    2,
    "{\"maximum\":2,\"op\":\"clamp\"}",
    reference="checked-step:99",
  )
  assert_true(
    @capacity_program_step.prepare_derived_applications(
      p,
      program_claims([first, detached]),
      caps,
    )
    is Err(UnknownSubject(_)),
  )
  let wrong = proof(
    "actql.bound.values",
    2,
    "{\"op\":\"source\"}",
    reference="checked-step:1",
  )
  assert_true(
    @capacity_program_step.prepare_derived_applications(
      p,
      program_claims([first, wrong]),
      caps,
    )
    is Err(Application(_, LawMismatch)),
  )
  let empty = @capacity_program_step.prepare_derived_applications(
    p,
    program_claims([]),
    { ..caps, max_work: 2, },
  ).unwrap()
  assert_eq(@capacity_program_step.application_work(empty), 2)
  assert_true(@capacity_program_step.application_at(empty, 0) is None)
}
