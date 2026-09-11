///|
test "conditional join assertions refine bounds without becoming validated key evidence" {
  for cardinality in ["one_to_one", "many_to_one", "one_to_many"] {
    for kind in ["inner", "left", "full", "semi", "anti"] {
      for l in [1L, 2L, 5L] {
        for r in [1L, 2L, 5L] {
          let p = pipeline(
            "[{\"take\":" +
            l.to_string() +
            ",\"as\":\"l\"},{\"take\":" +
            r.to_string() +
            ",\"from\":\"rows\",\"as\":\"r\"},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"" +
            kind +
            "\",\"on\":\"id\",\"cardinality\":\"" +
            cardinality +
            "\"}}]",
          )
          let left = @capacity_program_step.check(
            p,
            0,
            proof(
              "actql.bound.take",
              l,
              "{\"maximum\":" + l.to_string() + ",\"op\":\"clamp\"}",
            ),
          ).unwrap()
          let right = @capacity_program_step.check(
            p,
            1,
            proof(
              "actql.bound.take",
              r,
              "{\"maximum\":" + r.to_string() + ",\"op\":\"clamp\"}",
              reference="checked-step:1",
            ),
          ).unwrap()
          let expected = match kind {
            "inner" =>
              if cardinality == "one_to_one" {
                if l < r {
                  l
                } else {
                  r
                }
              } else if cardinality == "many_to_one" {
                l
              } else {
                r
              }
            "left" => if cardinality == "one_to_many" { l + r - 1L } else { l }
            "full" => l + r
            _ => l
          }
          let claim = proof(
            "actql.bound.join-output",
            expected,
            "{\"op\":\"source\"}",
            reference="checked-step:2",
            inputs=[bound_id(left), bound_id(right)],
          )
          let app = @capacity_program_step.check_join_with_uniqueness(
            p,
            2,
            claim,
            [left, right],
          ).unwrap()
          let retained = @capacity_program_step.checked_join_evidence(app).unwrap()
          assert_eq(
            retained.assertion,
            @pipeline.join_evidence(p, 2).unwrap().assertion,
          )
          assert_true(retained.assertion is Some(_))
          assert_true(retained.left is None && retained.right is None)
          assert_true(
            physical_equal(@capacity_program_step.checked_pipeline(app), p),
          )
          let ordinary = @capacity_program_step.check_with_inputs(p, 2, claim, [
            left, right,
          ])
          if ordinary is Ok(ordinary) {
            assert_true(
              @capacity_program_step.checked_join_evidence(ordinary) is None,
            )
          }
          assert_true(
            @capacity_program_step.check_join_with_uniqueness(
              p,
              2,
              proof(
                "actql.bound.join-output",
                expected + 1,
                "{\"op\":\"source\"}",
                reference="checked-step:2",
                inputs=[bound_id(left), bound_id(right)],
              ),
              [left, right],
            )
            is Err(ValueMismatch),
          )
          assert_true(
            @capacity_program_step.check_join_with_uniqueness(p, 2, claim, [
              right, left,
            ])
            is Err(InputTargetMismatch(0)),
          )
        }
      }
    }
  }
}

///|
test "join refinement retains exact key owners and keeps empty side rules" {
  for kind in ["inner", "left", "full", "semi", "anti"] {
    for l in [0L, 1L, 5L] {
      for r in [0L, 1L, 7L] {
        let (lp, left) = join_operand(l)
        let (rp, right) = join_operand(r)
        let p = join_pipeline(
          lp,
          rp,
          "join",
          kind,
          assertion=Some("one_to_one"),
        )
        let expected = if l == 0L || r == 0L {
          match kind {
            "full" => l + r
            "left" | "anti" => l
            _ => 0L
          }
        } else {
          match kind {
            "inner" => if l < r { l } else { r }
            "full" => l + r
            _ => l
          }
        }
        let claim = proof(
          "actql.bound.join-output",
          expected,
          "{\"op\":\"source\"}",
          inputs=[bound_id(left), bound_id(right)],
        )
        let app = @capacity_program_step.check_join_with_uniqueness(
          p,
          0,
          claim,
          [left, right],
          max_input_work=4,
        ).unwrap()
        let retained = @capacity_program_step.checked_join_evidence(app).unwrap()
        let original = @pipeline.join_evidence(p, 0).unwrap()
        for
          (actual, wanted) in [
            (retained.left, original.left),
            (retained.right, original.right),
          ] {
          match (actual, wanted) {
            (Some(a), Some(b)) => assert_true(physical_equal(a, b))
            (None, None) => ()
            _ => fail("lost join key evidence")
          }
        }
      }
    }
  }
  let (lp, left) = unique_join_operand(9007199254740991L)
  let (rp, right) = unique_join_operand(9007199254740991L)
  let p = join_pipeline(lp, rp, "join", "inner")
  let claim = proof(
    "actql.bound.join-output",
    9007199254740991L,
    "{\"op\":\"source\"}",
    inputs=[bound_id(left), bound_id(right)],
  )
  let app = @capacity_program_step.check_join_with_uniqueness(
    p,
    0,
    claim,
    [left, right],
    max_input_work=2,
  ).unwrap()
  let evidence = @capacity_program_step.checked_join_evidence(app).unwrap()
  assert_true(
    evidence.assertion is None &&
    evidence.left is Some(_) &&
    evidence.right is Some(_),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      0,
      claim,
      [left, right],
      max_input_work=2,
    )
    is Err(BoundOverflow),
  )
  let full = join_pipeline(lp, rp, "join", "full")
  assert_true(
    @capacity_program_step.check_join_with_uniqueness(
      full,
      0,
      claim,
      [left, right],
      max_input_work=2,
    )
    is Err(BoundOverflow),
  )
}

///|
fn unique_join_operand(
  n : Int64,
  unique? : Bool = true,
) -> (@pipeline.CheckedPipeline, @capacity_program_step.StepBound) {
  if !unique {
    let p = pipeline(
      "[{\"take\":1},{\"take\":1},{\"take\":" + n.to_string() + "}]",
      field_type=@contract.primitive(TimestampType, nullable=false),
    )
    let bound = @capacity_program_step.check(
      p,
      2,
      proof(
        "actql.bound.take",
        n,
        "{\"maximum\":" + n.to_string() + ",\"op\":\"clamp\"}",
        reference="checked-step:2",
      ),
    ).unwrap()
    return (p, bound)
  }
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"time_series\":{\"start\":\"2020-01-01T00:00:00.000Z\",\"end\":\"2020-01-01T00:00:00.003Z\",\"step\":1},\"as\":\"grid\"},{\"select\":[{\"id\":\"time\"}]},{\"take\":" +
      n.to_string() +
      "}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 3,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let bound = @capacity_program_step.check(
    p,
    2,
    proof(
      "actql.bound.take",
      n,
      "{\"maximum\":" + n.to_string() + ",\"op\":\"clamp\"}",
      reference="checked-step:2",
    ),
  ).unwrap()
  (p, bound)
}

///|
test "join refinement combines static keys and assertions without losing either source" {
  for
    (lu, ru, assertion, kind, expected) in [
      (true, false, None, "inner", 7L),
      (false, true, None, "inner", 3L),
      (true, true, None, "inner", 3L),
      (true, false, None, "left", 9L),
      (false, true, None, "left", 3L),
      (true, false, None, "full", 10L),
      (false, true, None, "full", 10L),
      (true, false, Some("many_to_one"), "inner", 3L),
      (false, true, Some("one_to_many"), "left", 3L),
    ] {
    let (lp, left) = unique_join_operand(3, unique=lu)
    let (rp, right) = unique_join_operand(7, unique=ru)
    let p = join_pipeline(lp, rp, "join", kind, assertion~)
    let claim = proof(
      "actql.bound.join-output",
      expected,
      "{\"op\":\"source\"}",
      inputs=[bound_id(left), bound_id(right)],
    )
    let app = @capacity_program_step.check_join_with_uniqueness(
      p,
      0,
      claim,
      [left, right],
      max_input_work=2,
    ).unwrap()
    let retained = @capacity_program_step.checked_join_evidence(app).unwrap()
    let original = @pipeline.join_evidence(p, 0).unwrap()
    assert_eq(retained.left is Some(_), lu)
    assert_eq(retained.right is Some(_), ru)
    assert_eq(retained.assertion is Some(_), assertion is Some(_))
    for
      (a, b) in [
        (retained.left, original.left),
        (retained.right, original.right),
      ] {
      if a is Some(a) {
        assert_true(physical_equal(a, b.unwrap()))
        assert_eq(@evidence.key_pending(a), [ValidateKeyProducer])
      }
    }
    let collection = program_claims([
      @capacity_program_step.checked_proof(left),
      @capacity_program_step.checked_proof(right),
      claim,
    ])
    let checked = @capacity_program_step.check_applications(
      collection,
      [left, right, app],
      max_work=11,
    ).unwrap()
    assert_eq(@capacity_program_step.remaining_source_count(checked), 0)
    // Collection coverage preserves the application's conditional evidence;
    // it does not discharge ValidateKeyProducer or the authored assertion.
    assert_true(
      @capacity_program_step.check_join_with_uniqueness(
        p,
        0,
        claim,
        [left, right],
        max_input_work=1,
      )
      is Err(InputWorkLimit),
    )
  }
}

///|
test "join refinement cannot borrow evidence from another operation or pipeline" {
  let p = pipeline(
    "[{\"take\":3,\"as\":\"l\"},{\"take\":4,\"from\":\"rows\",\"as\":\"r\"},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"}}]",
  )
  let claim = proof(
    "actql.bound.join-output",
    3,
    "{\"op\":\"source\"}",
    reference="checked-step:2",
  )
  assert_true(
    @capacity_program_step.check_join_with_uniqueness(p, 2, claim, [])
    is Err(MissingJoinUniqueness),
  )
  assert_true(
    @capacity_program_step.check_join_with_uniqueness(p, 0, claim, [])
    is Err(MissingJoinUniqueness),
  )
  let (lp, left) = join_operand(3)
  let cross = join_pipeline(lp, lp, "cross_join", "inner")
  assert_true(
    @capacity_program_step.check_join_with_uniqueness(
      cross,
      0,
      claim,
      [left, left],
      max_input_work=2,
    )
    is Err(MissingJoinUniqueness),
  )
}
