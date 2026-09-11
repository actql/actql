///|
fn join_operand(
  n : Int64,
) -> (@pipeline.CheckedPipeline, @capacity_program_step.StepBound) {
  if n == 0L {
    let p = pipeline(
      "[{\"take\":1},{\"unnest\":{\"column\":\"id\",\"as\":\"value\"}},{\"select\":[{\"id\":\"value\"}]}]",
      field_type=@contract.array_contract(
        @contract.primitive(NumberType, nullable=false),
        nullable=false,
        max_items=Some(0),
      ).unwrap(),
    )
    let seed = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 1, "{\"maximum\":1,\"op\":\"clamp\"}"),
    ).unwrap()
    let id = bound_id(seed)
    let bound = @capacity_program_step.check_with_inputs(
      p,
      1,
      proof(
        "actql.bound.unnest-array-items",
        0,
        "{\"factor\":0,\"input\":\"" + id + "\",\"op\":\"multiply\"}",
        reference="checked-step:1",
        inputs=[id],
      ),
      [seed],
    ).unwrap()
    return (p, bound)
  }
  // The actual input has one row. Keep an independently valid, looser take
  // proof so arithmetic overflow can be tested at this application boundary.
  let p = pipeline(
    "[{\"group\":{\"by\":[],\"aggregates\":{}}},{\"derive\":{\"id\":{\"literal\":1}}},{\"take\":" +
    n.to_string() +
    "}]",
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
  (p, bound)
}

///|
fn join_pipeline(
  left : @pipeline.CheckedPipeline,
  right : @pipeline.CheckedPipeline,
  family : String,
  kind : String,
  assertion? : String? = None,
) -> @pipeline.CheckedPipeline {
  let body = match family {
    "cross_join" => "{\"with\":\"r\"}"
    "interval_join" =>
      "{\"with\":\"r\",\"kind\":\"" +
      kind +
      "\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"id\"}}"
    _ =>
      "{\"with\":\"r\",\"kind\":\"" +
      kind +
      "\",\"on\":\"id\"" +
      (match assertion {
        Some(v) => ",\"cardinality\":\"" + v + "\""
        None => ""
      }) +
      "}"
  }
  @pipeline.check_with_evidence(
    cursor("[{\"from\":\"l\",\"" + family + "\":" + body + "}]"),
    [
      (
        "l",
        @pipeline.ProducedInput(
          @pipeline.produced_input(left, Step(2)).unwrap(),
        ),
      ),
      (
        "r",
        @pipeline.ProducedInput(
          @pipeline.produced_input(right, Step(2)).unwrap(),
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 1,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "join bounds preserve both owners and null extended unmatched occurrences" {
  for family in ["join", "cross_join", "interval_join"] {
    for kind in ["inner", "left", "full", "semi", "anti"] {
      if (family == "cross_join" && kind != "inner") ||
        (family == "interval_join" && kind == "full") {
        continue
      }
      for l in [0L, 1L, 2L, 3L] {
        for r in [0L, 1L, 2L, 3L] {
          let (lp, left) = join_operand(l)
          let (rp, right) = join_operand(r)
          let p = join_pipeline(lp, rp, family, kind)
          let expected = match kind {
            "inner" => l * r
            "left" => l * (if r == 0L { 1L } else { r })
            "full" => if l * r > l + r { l * r } else { l + r }
            "semi" => if r == 0L { 0L } else { l }
            _ => l
          }
          let ids = [bound_id(left), bound_id(right)]
          let claim = proof(
            "actql.bound.join-output",
            expected,
            "{\"op\":\"source\"}",
            inputs=ids,
          )
          let work = 2 +
            (if l == 0L { 1 } else { 0 }) +
            (if r == 0L { 1 } else { 0 })
          let checked = @capacity_program_step.check_with_inputs(
            p,
            0,
            claim,
            [left, right],
            max_input_work=work,
          ).unwrap()
          assert_eq(@capacity_program_step.input_work(checked), work)
          assert_eq(@capacity_program_step.input_count(checked), 2)
          assert_true(
            physical_equal(
              @capacity_program_step.input_at(checked, 1).unwrap(),
              right,
            ),
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              claim,
              [left, right],
              max_input_work=work - 1,
            )
            is Err(InputWorkLimit),
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              claim,
              [right, left],
              max_input_work=work + 2,
            )
            is Err(_),
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              proof(
                "actql.bound.join-output",
                expected + 1,
                "{\"op\":\"source\"}",
                inputs=ids,
              ),
              [left, right],
              max_input_work=work,
            )
            is Err(ValueMismatch),
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              claim,
              [left],
              max_input_work=work,
            )
            is Err(InputCountMismatch),
          )
        }
      }
    }
  }
}

///|
test "join bound arithmetic rejects overflow without overflowing unused alternatives" {
  let maximum = 9007199254740991L
  for
    (kind, l, r, expected) in [
      ("inner", maximum, 0L, Some(0L)),
      ("left", maximum, 0L, Some(maximum)),
      ("full", 0L, maximum, Some(maximum)),
      ("full", 1L, maximum - 1L, Some(maximum)),
      ("full", 1L, maximum, None),
      ("full", 2L, maximum / 2L, Some(maximum - 1L)),
      ("inner", 2L, maximum, None),
      ("left", maximum, 2L, None),
      ("full", 2L, maximum, None),
      ("semi", maximum, maximum, Some(maximum)),
      ("anti", maximum, maximum, Some(maximum)),
    ] {
    let (lp, left) = join_operand(l)
    let (rp, right) = join_operand(r)
    let p = join_pipeline(lp, rp, "join", kind)
    let claim = proof(
      "actql.bound.join-output",
      expected.unwrap_or(1L),
      "{\"op\":\"source\"}",
      inputs=[bound_id(left), bound_id(right)],
    )
    let result = @capacity_program_step.check_with_inputs(
      p,
      0,
      claim,
      [left, right],
      max_input_work=4,
    )
    if expected is Some(_) {
      assert_true(result is Ok(_))
    } else {
      assert_true(result is Err(BoundOverflow))
    }
  }
}

///|
test "join applications require source derivation and retain repeated data operands" {
  let (producer, bound) = join_operand(3)
  let p = join_pipeline(producer, producer, "cross_join", "inner")
  let id = bound_id(bound)
  let claim = proof("actql.bound.join-output", 9, "{\"op\":\"source\"}", inputs=[
    id, id,
  ])
  let result = @capacity_program_step.check_with_inputs(
    p,
    0,
    claim,
    [bound, bound],
    max_input_work=2,
  ).unwrap()
  let claims = program_claims([
    @capacity_program_step.checked_proof(bound),
    claim,
  ])
  assert_true(
    @capacity_program_step.check_applications(
      claims,
      [bound, result],
      max_work=8,
    )
    is Ok(_),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      0,
      proof(
        "actql.bound.join-output",
        9,
        "{\"factor\":3,\"input\":\"" + id + "\",\"op\":\"multiply\"}",
        inputs=[id],
      ),
      [bound],
      max_input_work=2,
    )
    is Err(InputCountMismatch),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      0,
      proof("actql.bound.append", 9, "{\"op\":\"source\"}", inputs=[id, id]),
      [bound, bound],
      max_input_work=2,
    )
    is Err(LawMismatch),
  )
}
