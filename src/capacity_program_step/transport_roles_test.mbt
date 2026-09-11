///|
test "left bound transport keeps unused right proofs and never borrows their owners" {
  for operation in ["except", "intersect"] {
    let p = pipeline(
      "[{\"take\":3,\"as\":\"l\"},{\"take\":7,\"from\":\"rows\",\"as\":\"r\"},{\"from\":\"l\",\"" +
      operation +
      "\":{\"with\":\"r\",\"duplicates\":\"all\"}},{\"take\":9}]",
    )
    let lp = proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}")
    let rp = proof(
      "actql.bound.take",
      7,
      "{\"maximum\":7,\"op\":\"clamp\"}",
      reference="checked-step:1",
    )
    let left = @capacity_program_step.check(p, 0, lp).unwrap()
    let right = @capacity_program_step.check(p, 1, rp).unwrap()
    let id = bound_id(left)
    let claim = proof(
      "actql.bound.take",
      3,
      "{\"input\":\"" + id + "\",\"maximum\":9,\"op\":\"clamp\"}",
      reference="checked-step:3",
      inputs=[id],
    )
    let app = @capacity_program_step.check_with_inputs(
      p,
      3,
      claim,
      [left],
      max_input_work=1,
    ).unwrap()
    assert_eq(@capacity_program_step.input_work(app), 1)
    let edges = @pipeline.input_occurrences(
      @pipeline.step_at(@capacity_program_step.checked_pipeline(app), 2).unwrap(),
    )
    assert_eq(edges.map(e => e.target), [@pipeline.Step(0), @pipeline.Step(1)])
    let claims = program_claims([lp, rp, claim])
    assert_true(
      @capacity_program_step.check_applications(
        claims,
        [left, right, app],
        max_work=10,
      )
      is Ok(_),
    )
    assert_true(
      @capacity_program_step.check_applications(
        claims,
        [left, app],
        max_work=10,
      )
      is Err(MissingApplication(_)),
    )
    let wrong = bound_id(right)
    let wrong_claim = proof(
      "actql.bound.take",
      7,
      "{\"input\":\"" + wrong + "\",\"maximum\":9,\"op\":\"clamp\"}",
      reference="checked-step:3",
      inputs=[wrong],
    )
    assert_true(
      @capacity_program_step.check_with_inputs(
        p,
        3,
        wrong_claim,
        [right],
        max_input_work=3,
      )
      is Err(MissingInputProducer(0)),
    )
  }
}

///|
test "transporting a singleton cross join does not discharge its right row assertion" {
  let p = pipeline(
    "[{\"take\":3},{\"cross_join\":{\"with\":\"rows\",\"right_rows\":\"one\"}},{\"take\":9}]",
  )
  let bound = @capacity_program_step.check(
    p,
    0,
    proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
  ).unwrap()
  let id = bound_id(bound)
  let claim = proof(
    "actql.bound.take",
    3,
    "{\"input\":\"" + id + "\",\"maximum\":9,\"op\":\"clamp\"}",
    reference="checked-step:2",
    inputs=[id],
  )
  let app = @capacity_program_step.check_with_inputs(
    p,
    2,
    claim,
    [bound],
    max_input_work=1,
  ).unwrap()
  guard @pipeline.step_at(@capacity_program_step.checked_pipeline(app), 1).unwrap().operation
    is CrossJoin(checked~, ..) else {
    fail("cross join expected")
  }
  assert_true(
    @join.cross_pending_validations(checked).contains(
      @join.ValidateExactlyOneRightRow,
    ),
  )
  assert_eq(
    @pipeline.input_occurrences(@pipeline.step_at(p, 1).unwrap()).length(),
    2,
  )
}
