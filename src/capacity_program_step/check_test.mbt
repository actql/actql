///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 30,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn pipeline(
  body : String,
  parameters? : @parameter.Declarations? = None,
  field_type? : @contract.Contract = @contract.primitive(
    NumberType,
    nullable=false,
  ),
) -> @pipeline.CheckedPipeline {
  let schema = @schema.from_object(
    @contract.object_contract(
      [("id", field_type)],
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  ).unwrap()
  @pipeline.check(cursor(body), [("rows", schema)], parameters, None, {
    max_steps: 20,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }).unwrap()
}

///|
// Build integrity-valid claims, including intentionally false application claims.
// Hash correctness is covered independently by the SHA and wire corpus suites.
fn proof(
  law : String,
  value : Int64,
  derivation : String,
  reference? : String = "checked-step:0",
  unit? : String = "rows",
  inputs? : Array[String] = [],
) -> @wire.ProgramProofClaim {
  let body = "{\"inputs\":" +
    cid_array(inputs) +
    ",\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"" +
    reference +
    "\",\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let id = "sha256:" + @sha.hex(@utf8.encode(body))
  let dependencies = inputs.copy()
  dependencies.push(id)
  let preimage = "{\"dependencies\":" +
    cid_array(dependencies, unique=true) +
    ",\"derivation\":" +
    derivation +
    ",\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    id +
    "\",\"semantic_ref\":\"" +
    reference +
    "\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage + "}"))
  let bytes = @utf8.encode(preimage + ",\"witness_cid\":\"" + cid + "\"}")
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let wire = @wire.admit(bytes, cid, caps).unwrap()
  @wire.bind_program_proof(@utf8.encode(body), wire, caps).unwrap()
}

///|
fn cid_array(ids : Array[String], unique? : Bool = false) -> String {
  let ordered : Array[String] = []
  for id in ids {
    if unique && ordered.contains(id) {
      continue
    }
    ordered.push(id)
    let mut i = ordered.length() - 1
    while i > 0 && ordered[i] < ordered[i - 1] {
      let previous = ordered[i - 1]
      ordered[i - 1] = ordered[i]
      ordered[i] = previous
      i = i - 1
    }
  }
  "[" + ordered.map(id => "\"" + id + "\"").join(",") + "]"
}

///|
fn bound_id(bound : @capacity_program_step.StepBound) -> String {
  @wire.cid(
    @wire.program_proof_witness(@capacity_program_step.checked_proof(bound)),
  )
}

///|
fn fusion_pipeline(
  global : Bool,
  inputs : Int,
  parameters? : @parameter.Declarations? = None,
) -> @pipeline.CheckedPipeline {
  let amount = if parameters is Some(_) { "{\"$param\":\"n\"}" } else { "3" }
  pipeline(
    "[{\"take\":" +
    amount +
    "},{\"derive\":{\"query\":\"id\",\"rank\":{\"literal\":1}},\"as\":\"r\"}," +
    "{\"merge_rankings\":{\"with\":[" +
    Array::make(inputs - 1, "\"r\"").join(",") +
    "],\"by\":" +
    (if global { "[]" } else { "[\"query\"]" }) +
    ",\"candidate\":\"id\",\"rank\":\"rank\",\"k\":5,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[" +
    Array::make(inputs, "1").join(",") +
    "],\"rank_window\":10}}}}]",
    parameters~,
  )
}

///|
test "ranking bound applications cover every repeated operand under exact shared budgets" {
  for global in [false, true] {
    for n in [2, 3, 16, 32] {
      let p = fusion_pipeline(global, n)
      let seed = proof(
        "actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}",
      )
      let input = @capacity_program_step.check(p, 0, seed).unwrap()
      let id = bound_id(input)
      let ids = Array::make(n, id)
      let value = if global { 5L } else { 3L * n.to_int64() }
      let claim = proof(
        "actql.bound.merge-rankings",
        value,
        "{\"op\":\"source\"}",
        reference="checked-step:2",
        inputs=ids,
      )
      let supplied = Array::make(n, input)
      let checked = @capacity_program_step.check_with_inputs(
        p,
        2,
        claim,
        supplied,
        max_input_work=n,
        max_operand_work=5 * n,
      ).unwrap()
      assert_eq(@capacity_program_step.input_count(checked), n)
      assert_eq(@capacity_program_step.input_work(checked), n)
      assert_eq(@capacity_program_step.operand_work(checked), 5 * n)
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          claim,
          supplied,
          max_input_work=n,
          max_operand_work=5 * n - 1,
        )
        is Err(OperandWorkLimit),
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          claim,
          supplied,
          max_input_work=n - 1,
          max_operand_work=5 * n,
        )
        is Err(InputWorkLimit),
      )
      let step = @pipeline.step_at(p, 2).unwrap()
      assert_eq(@pipeline.input_occurrence_count(step), n)
      for i in 0..<n {
        assert_eq(
          @pipeline.input_occurrence_at(step, i).unwrap().target,
          Step(1),
        )
        assert_true(
          physical_equal(
            @capacity_program_step.input_at(checked, i).unwrap(),
            input,
          ),
        )
      }
      assert_true(@pipeline.input_occurrence_at(step, -1) is None)
      assert_true(@pipeline.input_occurrence_at(step, n) is None)
      let collection = program_claims([seed, claim])
      assert_true(
        @capacity_program_step.check_applications(
          collection,
          [checked, input],
          max_work=6 + n,
        )
        is Ok(_),
      )
      let other = proof(
        "actql.bound.take", 4, "{\"maximum\":4,\"op\":\"clamp\"}",
      )
      let wrong_ids = ids.copy()
      wrong_ids[n - 1] = @wire.cid(@wire.program_proof_witness(other))
      let wrong = proof(
        "actql.bound.merge-rankings",
        value,
        "{\"op\":\"source\"}",
        reference="checked-step:2",
        inputs=wrong_ids,
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          wrong,
          supplied,
          max_input_work=n,
          max_operand_work=5 * n,
        )
        is Err(InputWitnessMismatch(_)),
      )
      supplied[0] = @capacity_program_step.check(p, 0, seed).unwrap()
      assert_true(
        physical_equal(
          @capacity_program_step.input_at(checked, 0).unwrap(),
          input,
        ),
      )
      if n == 2 && !global {
        let binary = proof(
          "actql.bound.merge-rankings",
          6,
          "{\"left\":\"" + id + "\",\"op\":\"add\",\"right\":\"" + id + "\"}",
          reference="checked-step:2",
          inputs=ids,
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            2,
            binary,
            [input, input],
            max_input_work=2,
            max_operand_work=10,
          )
          is Ok(_),
        )
      }
    }
  }
}

///|
test "global ranking bounds clamp without overflowing and grouped sums reject overflow" {
  let d = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"default\":9007199254740991}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for global in [false, true] {
    let p = fusion_pipeline(global, 3, parameters=Some(d))
    let bindings = @capacity_program_step.bind_parameters(
      p,
      count_values(d, None),
      max_work=1,
      max_text_bytes=1,
    ).unwrap()
    let seed = proof(
      "actql.bound.take", 9007199254740991L, "{\"maximum\":9007199254740991,\"op\":\"clamp\"}",
    )
    let input = @capacity_program_step.check_with_inputs(
      p,
      0,
      seed,
      [],
      bindings=Some(bindings),
    ).unwrap()
    let claim = proof(
      "actql.bound.merge-rankings",
      5,
      "{\"op\":\"source\"}",
      reference="checked-step:2",
      inputs=Array::make(3, bound_id(input)),
    )
    let result = @capacity_program_step.check_with_inputs(
      p,
      2,
      claim,
      [input, input, input],
      max_input_work=3,
      max_operand_work=15,
    )
    if global {
      assert_true(result is Ok(_))
    } else {
      assert_true(result is Err(BoundOverflow))
    }
    let fallback = proof(
      "actql.bound.merge-rankings",
      5,
      "{\"maximum\":5,\"op\":\"clamp\"}",
      reference="checked-step:2",
    )
    if global {
      let bound = @capacity_program_step.check(p, 2, fallback).unwrap()
      assert_eq(@capacity_program_step.input_count(bound), 0)
      assert_eq(@capacity_program_step.operand_work(bound), 0)
    } else {
      assert_true(
        @capacity_program_step.check(p, 2, fallback) is Err(InputCountMismatch),
      )
    }
  }
}

///|
test "nearest bounds select query evidence and retain candidate-dependent factors" {
  for candidates in [1L, 2L, 7L] {
    for queries in [3L, 5L] {
      for k in [1L, 3L, 8L] {
        let p = pipeline(
          "[{\"take\":" +
          candidates.to_string() +
          "},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"c\"}," +
          "{\"take\":" +
          queries.to_string() +
          ",\"from\":\"rows\"},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"q\"}," +
          "{\"nearest\":{\"queries\":\"q\",\"k\":" +
          k.to_string() +
          ",\"metric\":\"dot\"},\"from\":\"c\"}]",
          field_type=@contract.vector_contract(2, nullable=false).unwrap(),
        )
        let cp = proof(
          "actql.bound.take",
          candidates,
          "{\"maximum\":" + candidates.to_string() + ",\"op\":\"clamp\"}",
        )
        let qp = proof(
          "actql.bound.take",
          queries,
          "{\"maximum\":" + queries.to_string() + ",\"op\":\"clamp\"}",
          reference="checked-step:3",
        )
        let c = @capacity_program_step.check(p, 0, cp).unwrap()
        let q = @capacity_program_step.check(p, 3, qp).unwrap()
        let cid = bound_id(c)
        let qid = bound_id(q)
        let loose = proof(
          "actql.bound.nearest",
          queries * k,
          "{\"factor\":" +
          k.to_string() +
          ",\"input\":\"" +
          qid +
          "\",\"op\":\"multiply\"}",
          reference="checked-step:6",
          inputs=[qid],
        )
        let bound = @capacity_program_step.check_with_inputs(
          p,
          6,
          loose,
          [q],
          max_input_work=2,
        ).unwrap()
        assert_eq(@capacity_program_step.input_work(bound), 2)
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            6,
            loose,
            [c],
            max_input_work=2,
          )
          is Err(InputTargetMismatch(0)),
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            6,
            loose,
            [q],
            max_input_work=1,
          )
          is Err(InputWorkLimit),
        )
        let factor = if candidates < k { candidates } else { k }
        let tight = proof(
          "actql.bound.nearest",
          queries * factor,
          "{\"op\":\"source\"}",
          reference="checked-step:6",
          inputs=[cid, qid],
        )
        let checked = @capacity_program_step.check_with_inputs(
          p,
          6,
          tight,
          [c, q],
          max_input_work=4,
        ).unwrap()
        assert_eq(@capacity_program_step.input_work(checked), 4)
        assert_true(
          physical_equal(
            @capacity_program_step.input_at(checked, 0).unwrap(),
            c,
          ),
        )
        assert_true(
          physical_equal(
            @capacity_program_step.input_at(checked, 1).unwrap(),
            q,
          ),
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            6,
            tight,
            [q, c],
            max_input_work=4,
          )
          is Err(InputTargetMismatch(0)),
        )
        let claims = program_claims([cp, qp, tight])
        assert_true(
          @capacity_program_step.check_applications(
            claims,
            [checked, c, q],
            max_work=11,
          )
          is Ok(_),
        )
        if candidates < k {
          let missing = proof(
            "actql.bound.nearest",
            queries * factor,
            "{\"factor\":" +
            factor.to_string() +
            ",\"input\":\"" +
            qid +
            "\",\"op\":\"multiply\"}",
            reference="checked-step:6",
            inputs=[qid],
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              6,
              missing,
              [q],
              max_input_work=2,
            )
            is Err(ValueMismatch),
          )
        }
        let false_value = proof(
          "actql.bound.nearest",
          0,
          "{\"op\":\"source\"}",
          reference="checked-step:6",
          inputs=[cid, qid],
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            6,
            false_value,
            [c, q],
            max_input_work=4,
          )
          is Err(ValueMismatch),
        )
      }
    }
  }
}

///|
fn window_pipeline(
  kind : String,
  options : String,
  events : Bool,
  parameters? : @parameter.Declarations? = None,
  rows? : Int64 = 3,
) -> @pipeline.CheckedPipeline {
  let (bridge, operation, time) = if events {
    ("{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},", "window_events", "")
  } else {
    ("", "row_window", ",\"time\":\"id\"")
  }
  pipeline(
    "[{\"take\":" +
    rows.to_string() +
    "}," +
    bridge +
    "{\"" +
    operation +
    "\":{\"kind\":\"" +
    kind +
    "\"" +
    time +
    "," +
    options +
    "}}]",
    parameters~,
  )
}

///|
test "maximum and weighted ranking policies bind both ordered score input bounds" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("query"), Some(number)),
        (Unqualified("id"), Some(number)),
        (Unqualified("score"), Some(number)),
      ],
      field_set=Closed,
      max_fields=3,
      max_name_bytes=20,
    ).unwrap(),
  )
  let contract = "{\"domain\":\"relevance\",\"range\":[0,1],\"normalization\":\"identity\"}"
  let ranking = @vector.declare_ranking_score(
    cursor(contract),
    rows,
    Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for global in [false, true] {
    for
      policy in ["\"max\"", "{\"weighted_sum\":{\"left\":0.25,\"right\":0.75}}"] {
      let p = @pipeline.check_with_evidence(
        cursor(
          "[{\"take\":2,\"as\":\"l\"},{\"take\":3,\"from\":\"rows\",\"as\":\"r\"},{\"from\":\"l\",\"merge_rankings\":{\"with\":\"r\",\"by\":" +
          (if global { "[]" } else { "[\"query\"]" }) +
          ",\"candidate\":\"id\",\"score\":\"score\",\"k\":3,\"score_policy\":" +
          policy +
          ",\"score_contract\":" +
          contract +
          "}}]",
        ),
        [("rows", @pipeline.RankingInput(ranking))],
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
      let lp = proof("actql.bound.take", 2, "{\"maximum\":2,\"op\":\"clamp\"}")
      let rp = proof(
        "actql.bound.take",
        3,
        "{\"maximum\":3,\"op\":\"clamp\"}",
        reference="checked-step:1",
      )
      let l = @capacity_program_step.check(p, 0, lp).unwrap()
      let r = @capacity_program_step.check(p, 1, rp).unwrap()
      let claim = proof(
        "actql.bound.merge-rankings",
        if global {
          3L
        } else {
          5L
        },
        "{\"op\":\"source\"}",
        reference="checked-step:2",
        inputs=[bound_id(l), bound_id(r)],
      )
      let checked = @capacity_program_step.check_with_inputs(
        p,
        2,
        claim,
        [l, r],
        max_operand_work=10,
      ).unwrap()
      assert_eq(@capacity_program_step.input_work(checked), 0)
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          claim,
          [r, l],
          max_operand_work=10,
        )
        is Err(InputTargetMismatch(0)),
      )
      if !global {
        let reversed = proof(
          "actql.bound.merge-rankings",
          5,
          "{\"left\":\"" +
          bound_id(r) +
          "\",\"op\":\"add\",\"right\":\"" +
          bound_id(l) +
          "\"}",
          reference="checked-step:2",
          inputs=[bound_id(l), bound_id(r)],
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            2,
            reversed,
            [l, r],
            max_operand_work=10,
          )
          is Err(InvalidDerivation),
        )
      }
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          claim,
          [l, r],
          max_operand_work=-1,
        )
        is Err(InvalidOperandWorkLimit),
      )
    }
  }
}

///|
test "self nearest retains both candidate and query proof occurrences" {
  let p = pipeline(
    "[{\"take\":3},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"v\"},{\"nearest\":{\"queries\":\"v\",\"k\":2,\"metric\":\"dot\"}}]",
    field_type=@contract.vector_contract(2, nullable=false).unwrap(),
  )
  let seed = proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}")
  let input = @capacity_program_step.check(p, 0, seed).unwrap()
  let id = bound_id(input)
  let claim = proof(
    "actql.bound.nearest",
    6,
    "{\"op\":\"source\"}",
    reference="checked-step:3",
    inputs=[id, id],
  )
  let checked = @capacity_program_step.check_with_inputs(
    p,
    3,
    claim,
    [input, input],
    max_input_work=4,
  ).unwrap()
  assert_eq(@capacity_program_step.input_count(checked), 2)
  assert_eq(@wire.program_proof_input_count(claim), 2)
  assert_eq(@capacity_program_step.input_work(checked), 4)
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      3,
      claim,
      [input, input],
      max_input_work=3,
    )
    is Err(InputWorkLimit),
  )
  let claims = program_claims([seed, claim])
  assert_true(
    @capacity_program_step.check_applications(
      claims,
      [checked, input],
      max_work=8,
    )
    is Ok(_),
  )
}

///|
test "nearest candidate-dependent bounds preserve empty candidates across producer owners" {
  let vector = @contract.vector_contract(2, nullable=false).unwrap()
  let candidates = pipeline(
    "[{\"take\":3},{\"unnest\":{\"column\":\"id\",\"as\":\"v\"}},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"v\"}}]",
    field_type=@contract.array_contract(
      vector,
      nullable=false,
      max_items=Some(0),
    ).unwrap(),
  )
  let seed_proof = proof(
    "actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}",
  )
  let seed = @capacity_program_step.check(candidates, 0, seed_proof).unwrap()
  let seed_id = bound_id(seed)
  let cp = proof(
    "actql.bound.unnest-array-items",
    0,
    "{\"factor\":0,\"input\":\"" + seed_id + "\",\"op\":\"multiply\"}",
    reference="checked-step:1",
    inputs=[seed_id],
  )
  let c = @capacity_program_step.check_with_inputs(candidates, 1, cp, [seed]).unwrap()
  let queries = pipeline(
    "[{\"take\":2},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"}}]",
    field_type=vector,
  )
  let qp = proof("actql.bound.take", 2, "{\"maximum\":2,\"op\":\"clamp\"}")
  let q = @capacity_program_step.check(queries, 0, qp).unwrap()
  let p = @pipeline.check_with_evidence(
    cursor(
      "[{\"nearest\":{\"queries\":\"q\",\"k\":5,\"metric\":\"dot\"},\"from\":\"c\"}]",
    ),
    [
      (
        "c",
        @pipeline.ProducedInput(
          @pipeline.produced_input(candidates, Step(3)).unwrap(),
        ),
      ),
      (
        "q",
        @pipeline.ProducedInput(
          @pipeline.produced_input(queries, Step(2)).unwrap(),
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
  let claim = proof("actql.bound.nearest", 0, "{\"op\":\"source\"}", inputs=[
    bound_id(c),
    bound_id(q),
  ])
  let checked = @capacity_program_step.check_with_inputs(
    p,
    0,
    claim,
    [c, q],
    max_input_work=6,
  ).unwrap()
  assert_eq(@capacity_program_step.input_work(checked), 6)
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      0,
      claim,
      [c, q],
      max_input_work=5,
    )
    is Err(InputWorkLimit),
  )
  let claims = program_claims([seed_proof, cp, qp, claim])
  assert_true(
    @capacity_program_step.check_applications(
      claims,
      [checked, c, q, seed],
      max_work=15,
    )
    is Ok(_),
  )
}

///|
test "nearest bound multiplication fails after Parameter binding instead of saturating" {
  let d = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"default\":9007199254740991}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let p = pipeline(
    "[{\"take\":{\"$param\":\"n\"}},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"c\"}," +
    "{\"take\":{\"$param\":\"n\"},\"from\":\"rows\"},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"q\"}," +
    "{\"nearest\":{\"queries\":\"q\",\"k\":2,\"metric\":\"dot\"},\"from\":\"c\"}]",
    field_type=@contract.vector_contract(2, nullable=false).unwrap(),
    parameters=Some(d),
  )
  let bindings = @capacity_program_step.bind_parameters(
    p,
    count_values(d, None),
    max_work=1,
    max_text_bytes=1,
  ).unwrap()
  let cp = proof(
    "actql.bound.take", 9007199254740991L, "{\"maximum\":9007199254740991,\"op\":\"clamp\"}",
  )
  let qp = proof(
    "actql.bound.take",
    9007199254740991L,
    "{\"maximum\":9007199254740991,\"op\":\"clamp\"}",
    reference="checked-step:3",
  )
  let c = @capacity_program_step.check_with_inputs(
    p,
    0,
    cp,
    [],
    bindings=Some(bindings),
  ).unwrap()
  let q = @capacity_program_step.check_with_inputs(
    p,
    3,
    qp,
    [],
    bindings=Some(bindings),
  ).unwrap()
  let claim = proof(
    "actql.bound.nearest",
    1,
    "{\"op\":\"source\"}",
    reference="checked-step:6",
    inputs=[bound_id(c), bound_id(q)],
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      6,
      claim,
      [c, q],
      max_input_work=4,
    )
    is Err(BoundOverflow),
  )
  let loose = proof(
    "actql.bound.nearest",
    1,
    "{\"factor\":2,\"input\":\"" + bound_id(q) + "\",\"op\":\"multiply\"}",
    reference="checked-step:6",
    inputs=[bound_id(q)],
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 6, loose, [q], max_input_work=2)
    is Err(BoundOverflow),
  )
}

///|
fn window_proof(
  input : @capacity_program_step.StepBound,
  events : Bool,
  factor : Int64,
  value : Int64,
) -> @wire.ProgramProofClaim {
  let id = bound_id(input)
  proof(
    if events {
      "actql.bound.window-events"
    } else {
      "actql.bound.row-window"
    },
    value,
    "{\"factor\":" +
    factor.to_string() +
    ",\"input\":\"" +
    id +
    "\",\"op\":\"multiply\"}",
    reference=if events { "checked-step:2" } else { "checked-step:1" },
    inputs=[id],
  )
}

///|
test "fixed and sliding window proofs use exact checked membership factors on both Carriers" {
  for events in [false, true] {
    for
      (kind, options, factor, rows) in [
        ("fixed", "\"size\":10", 1L, 3L),
        ("fixed", "\"size\":10,\"step\":1,\"offset\":-9007199254740991", 1L, 3L),
        ("fixed", "\"size\":1,\"step\":9007199254740991", 1L, 3L),
        ("sliding", "\"size\":10,\"step\":3,\"offset\":-7", 4L, 3L),
        ("sliding", "\"size\":10,\"step\":5", 2L, 3L),
        ("sliding", "\"size\":10,\"step\":20", 1L, 3L),
        (
          "sliding", "\"size\":9007199254740991,\"step\":1", 9007199254740991L, 1L,
        ),
        (
          "sliding", "\"size\":9007199254740991,\"step\":9007199254740990", 2L, 3L,
        ),
      ] {
      let p = window_pipeline(kind, options, events, rows~)
      let input = @capacity_program_step.check(
        p,
        0,
        proof(
          "actql.bound.take",
          rows,
          "{\"maximum\":" + rows.to_string() + ",\"op\":\"clamp\"}",
        ),
      ).unwrap()
      let claim = window_proof(input, events, factor, rows * factor)
      let index = if events { 2 } else { 1 }
      let cost = if events { 1 } else { 0 }
      let checked = @capacity_program_step.check_with_inputs(
        p,
        index,
        claim,
        [input],
        max_input_work=cost,
      ).unwrap()
      assert_eq(@capacity_program_step.input_work(checked), cost)
      let false_factor = window_proof(
        input,
        events,
        if factor == 9007199254740991L {
          factor - 1
        } else {
          factor + 1
        },
        rows * factor,
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          index,
          false_factor,
          [input],
          max_input_work=cost,
        )
        is Err(InvalidDerivation),
      )
    }
    let d = @parameter.read_declarations(
      Some(
        cursor("{\"size\":{\"type\":\"number\",\"default\":9007199254740991}}"),
      ),
      {
        max_parameters: 1,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      },
    ).unwrap()
    let p = window_pipeline(
      "sliding",
      "\"size\":{\"$param\":\"size\"},\"step\":1",
      events,
      rows=2,
      parameters=Some(d),
    )
    let bound = @capacity_program_step.bind_parameters(
      p,
      count_values(d, None),
      max_work=1,
      max_text_bytes=4,
    ).unwrap()
    let input = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 2, "{\"maximum\":2,\"op\":\"clamp\"}"),
    ).unwrap()
    let claim = window_proof(input, events, 9007199254740991L, 1)
    assert_true(
      @capacity_program_step.check_with_inputs(
        p,
        if events {
          2
        } else {
          1
        },
        claim,
        [input],
        max_input_work=1,
        bindings=Some(bound),
      )
      is Err(BoundOverflow),
    )
  }
}

///|
test "window Parameters bind once and validate unused fixed step and signed offset" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"size\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"01s\"},\"step\":{\"type\":\"number\",\"default\":3},\"offset\":{\"type\":\"number\",\"default\":-1}}",
      ),
    ),
    { max_parameters: 3, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for events in [false, true] {
    for kind in ["fixed", "sliding"] {
      let p = window_pipeline(
        kind,
        "\"size\":{\"$param\":\"size\"},\"step\":{\"$param\":\"step\"},\"offset\":{\"$param\":\"offset\"}",
        events,
        parameters=Some(declarations),
      )
      let input = @capacity_program_step.check(
        p,
        0,
        proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
      ).unwrap()
      let factor = if kind == "fixed" { 1L } else { 334L }
      let claim = window_proof(input, events, factor, 3 * factor)
      let index = if events { 2 } else { 1 }
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          index,
          claim,
          [input],
          max_input_work=1,
        )
        is Err(UnresolvedCount),
      )
      let values = count_values(declarations, None)
      let bindings = @capacity_program_step.bind_parameters(
        p,
        values,
        max_work=3,
        max_text_bytes=17,
      ).unwrap()
      assert_eq(@capacity_program_step.binding_usage(bindings), (3, 17))
      assert_true(
        @capacity_program_step.bind_parameters(
          p,
          values,
          max_work=3,
          max_text_bytes=16,
        )
        is Err(BindingTextLimit),
      )
      let checked = @capacity_program_step.check_with_inputs(
        p,
        index,
        claim,
        [input],
        max_input_work=1,
        bindings=Some(bindings),
      ).unwrap()
      assert_true(
        physical_equal(
          @capacity_program_step.checked_bindings(checked).unwrap(),
          bindings,
        ),
      )
      for
        (field, value) in [
          ("step", "0"),
          ("step", "-1"),
          ("step", "0.5"),
          ("step", "9007199254740992"),
          ("offset", "0.5"),
          ("offset", "-9007199254740992"),
        ] {
        let bad = count_values(
          declarations,
          Some("{\"" + field + "\":" + value + "}"),
        )
        let bad_bindings = @capacity_program_step.bind_parameters(
          p,
          bad,
          max_work=3,
          max_text_bytes=17,
        ).unwrap()
        assert_eq(
          @capacity_program_step.check_with_inputs(
            p,
            index,
            claim,
            [input],
            max_input_work=1,
            bindings=Some(bad_bindings),
          ).unwrap_err(),
          InvalidBoundMilliseconds(field),
        )
      }
    }
  }
}

///|
fn transport_case(
  body : String,
  last : Int,
  field_type? : @contract.Contract = @contract.primitive(
    NumberType,
    nullable=false,
  ),
) -> Unit raise {
  let p = pipeline(body, field_type~)
  let first = proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}")
  let input = @capacity_program_step.check(p, 0, first).unwrap()
  let id = bound_id(input)
  let output_proof = proof(
    "actql.bound.take",
    3,
    "{\"input\":\"" + id + "\",\"maximum\":9,\"op\":\"clamp\"}",
    reference="checked-step:" + last.to_string(),
    inputs=[id],
  )
  let links = last - 1
  let checked = @capacity_program_step.check_with_inputs(
    p,
    last,
    output_proof,
    [input],
    max_input_work=links,
  ).unwrap()
  assert_eq(@capacity_program_step.input_work(checked), links)
  assert_true(
    physical_equal(@capacity_program_step.input_at(checked, 0).unwrap(), input),
  )
  assert_true(
    physical_equal(@capacity_program_step.checked_pipeline(checked), p),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      last,
      output_proof,
      [input],
      max_input_work=links - 1,
    )
    is Err(InputWorkLimit),
  )
  let claims = program_claims([first, output_proof])
  assert_true(
    @capacity_program_step.check_applications(
      claims,
      [checked, input],
      max_work=7,
    )
    is Ok(_),
  )
}

///|
test "repeated duration window options share a budgeted canonical millisecond lookup" {
  let d = @parameter.read_declarations(
    Some(cursor("{\"t\":{\"type\":\"string\",\"format\":\"duration\"}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for events in [false, true] {
    let p = window_pipeline(
      "sliding",
      "\"size\":{\"$param\":\"t\"},\"step\":{\"$param\":\"t\"},\"offset\":{\"$param\":\"t\"}",
      events,
      parameters=Some(d),
    )
    let input = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
    ).unwrap()
    let claim = window_proof(input, events, 1, 3)
    for token in ["1s", "1S", "01s", "1000ms"] {
      let values = count_values(d, Some("{\"t\":\"" + token + "\"}"))
      let bytes = 1 + token.length()
      let bindings = @capacity_program_step.bind_parameters(
        p,
        values,
        max_work=1,
        max_text_bytes=bytes,
      ).unwrap()
      assert_eq(@capacity_program_step.binding_usage(bindings), (1, bytes))
      assert_true(
        @capacity_program_step.bind_parameters(
          p,
          values,
          max_work=1,
          max_text_bytes=bytes - 1,
        )
        is Err(BindingTextLimit),
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          if events {
            2
          } else {
            1
          },
          claim,
          [input],
          max_input_work=1,
          bindings=Some(bindings),
        )
        is Ok(_),
      )
    }
  }
}

///|
test "row bounds cross non-expanding Relation operations without claiming exact counts" {
  for
    operation in [
      "{\"filter\":\"TRUE\"}", "{\"filter\":\"FALSE\"}", "{\"derive\":{}}", "{\"select\":[\"id\"]}",
      "{\"rename\":{}}", "{\"drop\":[]}", "{\"sort\":[]}", "{\"distinct\":true}",
      "{\"distinct\":[\"id\"]}", "{\"dedupe_rows\":{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}}",
    ] {
    transport_case("[{\"take\":3}," + operation + ",{\"take\":9}]", 2)
  }
}

///|
test "row bound transport crosses Events and Vectors bridges with their original obligations" {
  for policy in ["mark", "drop"] {
    transport_case(
      "[{\"take\":3},{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}}," +
      "{\"session\":{\"by\":[],\"gap\":10}},{\"watermark_events\":{\"watermark_ms\":1,\"policy\":\"" +
      policy +
      "\"}}," +
      "{\"dedupe_events\":{\"by\":[\"id\"],\"order_by\":[{\"id\":\"asc\"}]}},{\"events\":true},{\"take\":9}]",
      6,
    )
  }
  transport_case(
    "[{\"take\":3},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"}}," +
    "{\"normalize_vectors\":true},{\"score_vectors\":{\"query\":[1,2],\"metric\":\"dot\"}},{\"vectors\":true},{\"take\":9}]",
    6,
    field_type=@contract.vector_contract(2, nullable=false).unwrap(),
  )
}

///|
test "row bound transport charges repeated paths and refuses expanding or unrelated producers" {
  let p = pipeline(
    "[{\"take\":3},{\"derive\":{},\"as\":\"kept\"},{\"append\":{\"with\":\"kept\"}}]",
  )
  let input = @capacity_program_step.check(
    p,
    0,
    proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
  ).unwrap()
  let id = bound_id(input)
  let sum = proof(
    "actql.bound.append",
    6,
    "{\"left\":\"" + id + "\",\"op\":\"add\",\"right\":\"" + id + "\"}",
    reference="checked-step:2",
    inputs=[id, id],
  )
  let checked = @capacity_program_step.check_with_inputs(
    p,
    2,
    sum,
    [input, input],
    max_input_work=2,
  ).unwrap()
  assert_eq(@capacity_program_step.input_work(checked), 2)
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      2,
      sum,
      [input, input],
      max_input_work=1,
    )
    is Err(InputWorkLimit),
  )
  for
    middle in [
      "{\"row_window\":{\"kind\":\"sliding\",\"time\":\"id\",\"size\":10,\"step\":1}}",
      "{\"group\":{\"by\":[],\"aggregates\":{}}}", "{\"derive\":{},\"from\":\"rows\"}",
    ] {
    let other = pipeline("[{\"take\":3}," + middle + ",{\"take\":9}]")
    let first = @capacity_program_step.check(
      other,
      0,
      proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
    ).unwrap()
    let cid = bound_id(first)
    let output_proof = proof(
      "actql.bound.take",
      3,
      "{\"input\":\"" + cid + "\",\"maximum\":9,\"op\":\"clamp\"}",
      reference="checked-step:2",
      inputs=[cid],
    )
    assert_true(
      @capacity_program_step.check_with_inputs(
        other,
        2,
        output_proof,
        [first],
        max_input_work=100,
      )
      is Err(_),
    )
  }
}

///|
fn program_claims(
  proofs : Array[@wire.ProgramProofClaim],
) -> @wire.ProgramClaims {
  let arithmetic = @wire.check_arithmetic_claims(
    proofs.map(@wire.program_proof_witness),
    { max_witnesses: 100, max_references: 1000, },
  ).unwrap()
  @wire.check_program_claims(arithmetic, proofs, {
    max_witnesses: 200,
    max_references: 2000,
  }).unwrap()
}

///|
test "as-of output bounds retain the left application independently of right cardinality" {
  for kind in ["left", "inner"] {
    for direction in ["backward", "forward", "nearest"] {
      for left_count in [1L, 3L, 9007199254740991L] {
        let p = pipeline(
          "[{\"take\":" +
          left_count.to_string() +
          ",\"as\":\"l\"},{\"take\":7,\"from\":\"rows\",\"as\":\"r\"}," +
          "{\"from\":\"l\",\"asof_join\":{\"with\":\"r\",\"kind\":\"" +
          kind +
          "\",\"by\":[],\"left_time\":\"id\",\"right_time\":\"id\",\"left_id\":\"id\"," +
          "\"direction\":\"" +
          direction +
          "\",\"tolerance\":1,\"select\":{\"id\":\"left.id\"}}}]",
        )
        let left_proof = proof(
          "actql.bound.take",
          left_count,
          "{\"maximum\":" + left_count.to_string() + ",\"op\":\"clamp\"}",
        )
        let right_proof = proof(
          "actql.bound.take",
          7,
          "{\"maximum\":7,\"op\":\"clamp\"}",
          reference="checked-step:1",
        )
        let left = @capacity_program_step.check(p, 0, left_proof).unwrap()
        let right = @capacity_program_step.check(p, 1, right_proof).unwrap()
        let id = bound_id(left)
        let derivation = "{\"input\":\"" + id + "\",\"op\":\"preserve\"}"
        let claim = proof(
          "actql.bound.asof-left",
          left_count,
          derivation,
          reference="checked-step:2",
          inputs=[id],
        )
        let checked = @capacity_program_step.check_with_inputs(p, 2, claim, [
          left,
        ]).unwrap()
        assert_true(
          physical_equal(
            @capacity_program_step.input_at(checked, 0).unwrap(),
            left,
          ),
        )
        assert_eq(@capacity_program_step.input_count(checked), 1)
        assert_eq(
          @pipeline.input_occurrences(@pipeline.step_at(p, 2).unwrap()).map(e => {
            e.target
          }),
          [Step(0), Step(1)],
        )
        let claims = program_claims([left_proof, right_proof, claim])
        let applications = @capacity_program_step.check_applications(
          claims,
          [checked, right, left],
          max_work=10,
        ).unwrap()
        assert_eq(
          @capacity_program_step.remaining_source_count(applications),
          0,
        )
        assert_true(
          @capacity_program_step.check_with_inputs(p, 2, claim, [])
          is Err(InputCountMismatch),
        )
        assert_true(
          @capacity_program_step.check_with_inputs(p, 2, claim, [left, right])
          is Err(InputCountMismatch),
        )
        assert_true(
          @capacity_program_step.check_with_inputs(p, 2, claim, [right])
          is Err(InputTargetMismatch(0)),
        )
        let false_value = proof(
          "actql.bound.asof-left",
          2,
          derivation,
          reference="checked-step:2",
          inputs=[id],
        )
        assert_true(
          @capacity_program_step.check_with_inputs(p, 2, false_value, [left])
          is Err(ValueMismatch),
        )
        let wrong_derivation = proof(
          "actql.bound.asof-left",
          left_count,
          "{\"factor\":1,\"input\":\"" + id + "\",\"op\":\"multiply\"}",
          reference="checked-step:2",
          inputs=[id],
        )
        assert_true(
          @capacity_program_step.check_with_inputs(p, 2, wrong_derivation, [
            left,
          ])
          is Err(InvalidDerivation),
        )
        let wrong_law = proof(
          "actql.bound.join-projection",
          left_count,
          derivation,
          reference="checked-step:2",
          inputs=[id],
        )
        assert_true(
          @capacity_program_step.check_with_inputs(p, 2, wrong_law, [left])
          is Err(LawMismatch),
        )
      }
    }
  }
}

///|
test "application collections cover unused proofs and preserve exact dependency handles" {
  let p = pipeline(
    "[{\"take\":7,\"as\":\"a\"},{\"append\":{\"with\":\"a\"}},{\"take\":3,\"from\":\"rows\"}]",
  )
  let leaf = proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}")
  let a = @capacity_program_step.check(p, 0, leaf).unwrap()
  let id = bound_id(a)
  let sum = proof(
    "actql.bound.append",
    14,
    "{\"left\":\"" + id + "\",\"op\":\"add\",\"right\":\"" + id + "\"}",
    reference="checked-step:1",
    inputs=[id, id],
  )
  let b = @capacity_program_step.check_with_inputs(p, 1, sum, [a, a]).unwrap()
  let unused = proof(
    "actql.bound.take",
    3,
    "{\"maximum\":3,\"op\":\"clamp\"}",
    reference="checked-step:2",
  )
  let c = @capacity_program_step.check(p, 2, unused).unwrap()
  let claims = program_claims([leaf, sum, unused])
  let supplied = [c, b, a]
  let checked = @capacity_program_step.check_applications(
    claims,
    supplied,
    max_work=11,
  ).unwrap()
  assert_eq(@capacity_program_step.application_work(checked), 11)
  assert_eq(@capacity_program_step.remaining_source_count(checked), 0)
  assert_true(
    physical_equal(@capacity_program_step.application_claims(checked), claims),
  )
  let index = @wire.claim_index(@wire.program_claim_arithmetic(claims), id).unwrap()
  supplied[2] = c
  assert_true(
    physical_equal(
      @capacity_program_step.application_at(checked, index).unwrap(),
      a,
    ),
  )
  assert_true(@capacity_program_step.application_at(checked, -1) is None)
  assert_true(@capacity_program_step.application_at(checked, 3) is None)
  assert_true(
    @capacity_program_step.check_applications(claims, [a, b, c], max_work=10)
    is Err(WorkLimit),
  )
  assert_true(
    @capacity_program_step.check_applications(claims, [a, b], max_work=11)
    is Err(MissingApplication(_)),
  )
  assert_true(
    @capacity_program_step.check_applications(claims, [a, b, c, c], max_work=20)
    is Err(DuplicateApplication(3)),
  )
  let foreign = @capacity_program_step.check(
    pipeline("[{\"take\":7}]"),
    0,
    leaf,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_applications(
      claims,
      [foreign, b, c],
      max_work=11,
    )
    is Err(ForeignDependency(_, 0)),
  )
  let other = @capacity_program_step.check(
    pipeline("[{\"take\":8}]"),
    0,
    proof("actql.bound.take", 8, "{\"maximum\":8,\"op\":\"clamp\"}"),
  ).unwrap()
  assert_true(
    @capacity_program_step.check_applications(
      claims,
      [other, b, c],
      max_work=11,
    )
    is Err(ForeignApplication(0)),
  )
}

///|
test "integrity-valid but unapplied Program claims cannot hide in a collection" {
  let false_claim = proof("actql.bound.global-group", 99, "{\"op\":\"source\"}")
  let claims = program_claims([false_claim])
  assert_true(
    @capacity_program_step.check_applications(claims, [], max_work=2)
    is Err(MissingApplication(0)),
  )
  let empty = program_claims([])
  let checked = @capacity_program_step.check_applications(empty, [], max_work=0).unwrap()
  assert_eq(@capacity_program_step.application_work(checked), 0)
  assert_eq(@capacity_program_step.remaining_source_count(checked), 0)
  assert_true(
    @capacity_program_step.check_applications(empty, [], max_work=-1)
    is Err(InvalidLimits),
  )
}

///|
test "application coverage does not promote a Host claim to an admitted source" {
  // Independent fixed wire fixture shared with the mixed-closure suite.
  let id = "sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84"
  let text = "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"" +
    id +
    "\"}"
  let witness = @wire.admit(@utf8.encode(text), id, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let arithmetic = @wire.check_arithmetic_claims([witness], {
    max_witnesses: 1,
    max_references: 10,
  }).unwrap()
  let claims = @wire.check_program_claims(arithmetic, [], {
    max_witnesses: 1,
    max_references: 10,
  }).unwrap()
  let checked = @capacity_program_step.check_applications(
    claims,
    [],
    max_work=2,
  ).unwrap()
  assert_eq(@capacity_program_step.remaining_source_count(checked), 1)
  assert_true(@capacity_program_step.application_at(checked, 0) is None)
}

///|
fn count_declarations() -> @parameter.Declarations {
  @parameter.read_declarations(
    Some(
      cursor(
        "{\"n\":{\"type\":\"number\",\"default\":7},\"unused\":{\"type\":\"string\",\"default\":\"text\"}}",
      ),
    ),
    { max_parameters: 2, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn count_values(
  d : @parameter.Declarations,
  supplied : String?,
) -> @parameter.BoundValues raise {
  let result = @parameter.bind(d, supplied.map(cursor), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
  guard result is Ready(values) else { fail("complete binding expected") }
  values
}

///|
test "bound selection counts retain default or supplied values from the exact owner" {
  let d = count_declarations()
  for
    body in [
      "[{\"take\":{\"$param\":\"n\"}}]", "[{\"top_k\":{\"k\":{\"$param\":\"n\"},\"by\":[{\"id\":\"asc\"}]}}]",
      "[{\"top_k_by\":{\"partition_by\":[],\"k\":{\"$param\":\"n\"},\"by\":[{\"id\":\"asc\"}]}}]",
    ] {
    let p = pipeline(body, parameters=Some(d))
    let law = if body.contains("top_k") {
      "actql.bound.top-k"
    } else {
      "actql.bound.take"
    }
    for
      (supplied, n) in [
        (None, 7L),
        (Some("{\"n\":9}"), 9L),
        (Some("{\"n\":9007199254740991}"), 9007199254740991L),
      ] {
      let values = count_values(d, supplied)
      let bindings = @capacity_program_step.bind_parameters(
        p,
        values,
        max_work=2,
        max_text_bytes=7,
      ).unwrap()
      assert_eq(@capacity_program_step.binding_usage(bindings), (2, 7))
      assert_true(
        physical_equal(
          @capacity_program_step.parameter_values(bindings),
          values,
        ),
      )
      let claim = proof(
        law,
        n,
        "{\"maximum\":" + n.to_string() + ",\"op\":\"clamp\"}",
      )
      let checked = @capacity_program_step.check_with_inputs(
        p,
        0,
        claim,
        [],
        bindings=Some(bindings),
      ).unwrap()
      assert_true(
        physical_equal(
          @capacity_program_step.checked_bindings(checked).unwrap(),
          bindings,
        ),
      )
      assert_true(
        @capacity_program_step.check(p, 0, claim) is Err(UnresolvedCount),
      )
      assert_true(
        @capacity_program_step.bind_parameters(
          p,
          values,
          max_work=1,
          max_text_bytes=7,
        )
        is Err(BindingWorkLimit),
      )
      assert_true(
        @capacity_program_step.bind_parameters(
          p,
          values,
          max_work=2,
          max_text_bytes=6,
        )
        is Err(BindingTextLimit),
      )
      assert_true(
        @capacity_program_step.bind_parameters(
          p,
          values,
          max_work=-1,
          max_text_bytes=7,
        )
        is Err(InvalidBindingLimits),
      )
      let other = pipeline(body, parameters=Some(d))
      assert_true(
        @capacity_program_step.check_with_inputs(
          other,
          0,
          claim,
          [],
          bindings=Some(bindings),
        )
        is Err(BindingOwnerMismatch),
      )
    }
    let foreign_values = count_values(count_declarations(), None)
    assert_true(
      @capacity_program_step.bind_parameters(
        p,
        foreign_values,
        max_work=2,
        max_text_bytes=7,
      )
      is Err(BindingOwnerMismatch),
    )
    for
      supplied in [
        "{\"n\":0}", "{\"n\":-1}", "{\"n\":1.5}", "{\"n\":9007199254740992}",
      ] {
      let bindings = @capacity_program_step.bind_parameters(
        p,
        count_values(d, Some(supplied)),
        max_work=2,
        max_text_bytes=7,
      ).unwrap()
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          0,
          proof(law, 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
          [],
          bindings=Some(bindings),
        )
        is Err(InvalidBoundCount),
      )
    }
  }
}

///|
test "bound counts clamp producer bounds without replacing derivation maxima" {
  let d = count_declarations()
  let p = pipeline(
    "[{\"take\":3},{\"take\":{\"$param\":\"n\"}}]",
    parameters=Some(d),
  )
  let bindings = @capacity_program_step.bind_parameters(
    p,
    count_values(d, None),
    max_work=2,
    max_text_bytes=7,
  ).unwrap()
  let input = @capacity_program_step.check(
    p,
    0,
    proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
  ).unwrap()
  let id = bound_id(input)
  for maximum in [7, 3] {
    let claim = proof(
      "actql.bound.take",
      3,
      "{\"input\":\"" +
      id +
      "\",\"maximum\":" +
      maximum.to_string() +
      ",\"op\":\"clamp\"}",
      reference="checked-step:1",
      inputs=[id],
    )
    let result = @capacity_program_step.check_with_inputs(
      p,
      1,
      claim,
      [input],
      bindings=Some(bindings),
    )
    if maximum == 7 {
      assert_true(result is Ok(_))
    } else {
      assert_true(result is Err(InvalidDerivation))
    }
  }
}

///|
fn consume(
  producer : @pipeline.CheckedPipeline,
  target : @pipeline.Target,
  body : String,
) -> @pipeline.CheckedPipeline {
  @pipeline.check_with_evidence(
    cursor(body),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(producer, target).unwrap(),
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 20,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "producer edges retain exact source owners and cumulative traversal work" {
  let root = pipeline("[{\"take\":7}]")
  let root_claim = proof(
    "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
  )
  let a = @capacity_program_step.check(root, 0, root_claim).unwrap()
  let id = bound_id(a)
  let middle = consume(root, @pipeline.Step(0), "[]")
  let end = consume(
    middle,
    @pipeline.Input(0),
    "[{\"append\":{\"with\":\"prior\"}}]",
  )
  let claim = proof(
    "actql.bound.append",
    14,
    "{\"left\":\"" + id + "\",\"op\":\"add\",\"right\":\"" + id + "\"}",
    inputs=[id, id],
  )
  let checked = @capacity_program_step.check_with_inputs(
    end,
    0,
    claim,
    [a, a],
    max_input_work=4,
  ).unwrap()
  assert_eq(@capacity_program_step.input_work(checked), 4)
  assert_true(
    physical_equal(@capacity_program_step.checked_pipeline(checked), end),
  )
  assert_true(
    physical_equal(@capacity_program_step.input_at(checked, 0).unwrap(), a),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      end,
      0,
      claim,
      [a, a],
      max_input_work=3,
    )
    is Err(InputWorkLimit),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(end, 0, claim, [a, a])
    is Err(InputWorkLimit),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      end,
      0,
      claim,
      [a, a],
      max_input_work=-1,
    )
    is Err(InvalidInputWorkLimit),
  )
  let foreign = @capacity_program_step.check(
    pipeline("[{\"take\":7}]"),
    0,
    root_claim,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_with_inputs(
      end,
      0,
      claim,
      [a, foreign],
      max_input_work=4,
    )
    is Err(InputOwnerMismatch(1)),
  )
  let ordinary = pipeline("[{\"append\":{\"with\":\"rows\"}}]")
  assert_true(
    @capacity_program_step.check_with_inputs(
      ordinary,
      0,
      claim,
      [a, a],
      max_input_work=4,
    )
    is Err(MissingInputProducer(0)),
  )
}

///|
test "forwarded proof inputs use an iterative bounded walk" {
  let root = pipeline("[{\"take\":7}]")
  let a = @capacity_program_step.check(
    root,
    0,
    proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
  ).unwrap()
  let id = bound_id(a)
  let claim = proof(
    "actql.bound.take",
    3,
    "{\"input\":\"" + id + "\",\"maximum\":3,\"op\":\"clamp\"}",
    inputs=[id],
  )
  for
    (body, forwarded, cost) in [
      ("[]", @pipeline.Input(0), 2001),
      ("[{\"derive\":{}}]", @pipeline.Step(0), 4001),
    ] {
    let mut owner = root
    let mut target = @pipeline.Step(0)
    for _ in 0..<2000 {
      owner = consume(owner, target, body)
      target = forwarded
    }
    let end = consume(owner, target, "[{\"take\":3}]")
    let checked = @capacity_program_step.check_with_inputs(
      end,
      0,
      claim,
      [a],
      max_input_work=cost,
    ).unwrap()
    assert_eq(@capacity_program_step.input_work(checked), cost)
    assert_true(
      @capacity_program_step.check_with_inputs(
        end,
        0,
        claim,
        [a],
        max_input_work=cost - 1,
      )
      is Err(InputWorkLimit),
    )
    let foreign = @capacity_program_step.check(
      pipeline("[{\"take\":7}]"),
      0,
      proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
    ).unwrap()
    assert_true(
      @capacity_program_step.check_with_inputs(
        end,
        0,
        claim,
        [foreign],
        max_input_work=cost,
      )
      is Err(InputOwnerMismatch(0)),
    )
  }
}

///|
test "unnest derives expansion from the admitted array bound including outer empty arrays" {
  for
    (maximum, outer, factor) in [
      (Some(0L), false, 0L),
      (Some(0L), true, 1L),
      (Some(3L), true, 3L),
      (None, false, 0L),
    ] {
    let p = pipeline(
      "[{\"take\":7},{\"unnest\":{\"column\":\"id\",\"as\":\"value\",\"outer\":" +
      outer.to_string() +
      "}}]",
      field_type=@contract.array_contract(
        @contract.primitive(NumberType, nullable=false),
        nullable=false,
        max_items=maximum,
      ).unwrap(),
    )
    let a = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
    ).unwrap()
    let id = bound_id(a)
    let claim = proof(
      "actql.bound.unnest-array-items",
      7 * factor,
      "{\"factor\":" +
      factor.to_string() +
      ",\"input\":\"" +
      id +
      "\",\"op\":\"multiply\"}",
      reference="checked-step:1",
      inputs=[id],
    )
    let checked = @capacity_program_step.check_with_inputs(p, 1, claim, [a])
    if maximum is None {
      assert_true(checked is Err(UnresolvedCount))
    } else {
      assert_true(checked is Ok(_))
    }
  }
}

///|
test "repeated append operands remain two occurrences and arithmetic overflow fails" {
  for maximum in [7L, 9007199254740991L] {
    // The actual group has at most one row, while the independent take proof
    // deliberately uses its looser literal bound. Pipeline counting stays valid.
    let p = pipeline(
      "[{\"group\":{\"by\":[],\"aggregates\":{}}},{\"take\":" +
      maximum.to_string() +
      ",\"as\":\"a\"},{\"append\":{\"with\":\"a\"}}]",
    )
    let a = @capacity_program_step.check(
      p,
      1,
      proof(
        "actql.bound.take",
        maximum,
        "{\"maximum\":" + maximum.to_string() + ",\"op\":\"clamp\"}",
        reference="checked-step:1",
      ),
    ).unwrap()
    let id = bound_id(a)
    let derivation = "{\"left\":\"" +
      id +
      "\",\"op\":\"add\",\"right\":\"" +
      id +
      "\"}"
    let claim = proof(
      "actql.bound.append",
      14,
      derivation,
      reference="checked-step:2",
      inputs=[id, id],
    )
    let result = @capacity_program_step.check_with_inputs(p, 2, claim, [a, a])
    if maximum == 7 {
      let checked = result.unwrap()
      assert_eq(@capacity_program_step.input_count(checked), 2)
      assert_true(
        physical_equal(
          @capacity_program_step.input_at(checked, 0).unwrap(),
          @capacity_program_step.input_at(checked, 1).unwrap(),
        ),
      )
    } else {
      assert_true(result is Err(BoundOverflow))
    }
  }
}

///|
test "selection clamps a verified input and unpivot counts repeated columns" {
  let p = pipeline(
    "[{\"take\":7},{\"take\":3},{\"unpivot\":{\"columns\":[\"id\",\"id\"],\"keep\":[],\"name_column\":\"name\",\"value_column\":\"value\"}}]",
  )
  let a = @capacity_program_step.check(
    p,
    0,
    proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
  ).unwrap()
  let a_id = bound_id(a)
  let b = @capacity_program_step.check_with_inputs(
    p,
    1,
    proof(
      "actql.bound.take",
      3,
      "{\"input\":\"" + a_id + "\",\"maximum\":3,\"op\":\"clamp\"}",
      reference="checked-step:1",
      inputs=[a_id],
    ),
    [a],
  ).unwrap()
  let b_id = bound_id(b)
  let claim = proof(
    "actql.bound.unpivot",
    6,
    "{\"factor\":2,\"input\":\"" + b_id + "\",\"op\":\"multiply\"}",
    reference="checked-step:2",
    inputs=[b_id],
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [b]) is Ok(_),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [a])
    is Err(InputTargetMismatch(0)),
  )
  let false_factor = proof(
    "actql.bound.unpivot",
    6,
    "{\"factor\":1,\"input\":\"" + b_id + "\",\"op\":\"multiply\"}",
    reference="checked-step:2",
    inputs=[b_id],
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, false_factor, [b])
    is Err(InvalidDerivation),
  )
}

///|
test "append binds ordered edges independently of sorted proof operands" {
  let body = "[{\"group\":{\"by\":[],\"aggregates\":{}},\"as\":\"a\"},{\"group\":{\"by\":[],\"aggregates\":{}},\"from\":\"rows\",\"as\":\"b\"},{\"append\":{\"with\":\"b\"},\"from\":\"a\"}]"
  let p = pipeline(body)
  let a_claim = proof("actql.bound.global-group", 1, "{\"op\":\"source\"}")
  let a = @capacity_program_step.check(p, 0, a_claim).unwrap()
  let b = @capacity_program_step.check(
    p,
    1,
    proof(
      "actql.bound.global-group",
      1,
      "{\"op\":\"source\"}",
      reference="checked-step:1",
    ),
  ).unwrap()
  let left = bound_id(a)
  let right = bound_id(b)
  let derivation = "{\"left\":\"" +
    left +
    "\",\"op\":\"add\",\"right\":\"" +
    right +
    "\"}"
  let claim = proof(
    "actql.bound.append",
    2,
    derivation,
    reference="checked-step:2",
    inputs=[left, right],
  )
  let inputs = [a, b]
  let result = @capacity_program_step.check_with_inputs(p, 2, claim, inputs).unwrap()
  inputs[0] = b
  assert_true(
    physical_equal(@capacity_program_step.input_at(result, 0).unwrap(), a),
  )
  assert_eq(@capacity_program_step.input_count(result), 2)
  assert_true(@capacity_program_step.input_at(result, -1) is None)
  assert_true(@capacity_program_step.input_at(result, 2) is None)
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [b, a])
    is Err(InputTargetMismatch(0)),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [a])
    is Err(InputCountMismatch),
  )
  let foreign = @capacity_program_step.check(pipeline(body), 0, a_claim).unwrap()
  assert_true(
    @capacity_program_step.check_with_inputs(p, 2, claim, [foreign, b])
    is Err(InputOwnerMismatch(0)),
  )
  let reversed = "{\"left\":\"" +
    right +
    "\",\"op\":\"add\",\"right\":\"" +
    left +
    "\"}"
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      2,
      proof("actql.bound.append", 2, reversed, reference="checked-step:2", inputs=[
        left, right,
      ]),
      [a, b],
    )
    is Err(InvalidDerivation),
  )
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      2,
      proof("actql.bound.append", 3, derivation, reference="checked-step:2", inputs=[
        left, right,
      ]),
      [a, b],
    )
    is Err(ValueMismatch),
  )
}

///|
test "operation applications retain the checked owner and verify global and literal clamp laws" {
  for
    (body, law, n, derivation) in [
      (
        "[{\"group\":{\"by\":[],\"aggregates\":{}}}]", "actql.bound.global-group",
        1, "{\"op\":\"source\"}",
      ),
      (
        "[{\"take\":7}]", "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"take\":{\"count\":7,\"offset\":100}}]", "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"top_k\":{\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]", "actql.bound.top-k",
        7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
      (
        "[{\"top_k_by\":{\"partition_by\":[],\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]",
        "actql.bound.top-k", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
      ),
    ] {
    let p = pipeline(body)
    let claim = proof(law, n.to_int64(), derivation)
    let checked = @capacity_program_step.check(p, 0, claim).unwrap()
    assert_true(
      physical_equal(@capacity_program_step.checked_pipeline(checked), p),
    )
    assert_true(
      physical_equal(@capacity_program_step.checked_proof(checked), claim),
    )
    assert_eq(@capacity_program_step.checked_step(checked), 0)
    assert_eq(@capacity_program_step.subject_ref(p, 0), Some("checked-step:0"))
    assert_true(@capacity_program_step.subject_ref(p, -1) is None)
    assert_true(@capacity_program_step.subject_ref(p, 1) is None)
    assert_true(@capacity_program_step.check(p, 1, claim) is Err(MissingStep))
  }
}

///|
test "matching values and valid proof identities do not establish an operation application" {
  let group = pipeline(
    "[{\"group\":{\"by\":[],\"aggregates\":{}},\"as\":\"grouped\"}]",
  )
  let take = pipeline("[{\"take\":1}]")
  let grouped = pipeline("[{\"group\":{\"by\":[\"id\"],\"aggregates\":{}}}]")
  let source = "{\"op\":\"source\"}"
  let group_proof = proof("actql.bound.global-group", 1, source)
  assert_true(
    @capacity_program_step.check(take, 0, group_proof) is Err(LawMismatch),
  )
  assert_true(
    @capacity_program_step.check(grouped, 0, group_proof)
    is Err(UnsupportedOperation),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 2, source),
    )
    is Err(ValueMismatch),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 1, source, unit="nodes"),
    )
    is Err(LawMismatch),
  )
  assert_true(
    @capacity_program_step.check(
      group,
      0,
      proof("actql.bound.global-group", 1, source, reference="grouped"),
    )
    is Err(SubjectMismatch),
  )
  assert_true(
    @capacity_program_step.check(take, 0, proof("actql.bound.take", 1, source))
    is Err(InvalidDerivation),
  )
  assert_true(
    @capacity_program_step.check(
      take,
      0,
      proof("actql.bound.take", 1, "{\"maximum\":2,\"op\":\"clamp\"}"),
    )
    is Err(InvalidDerivation),
  )
}

///|
test "partitioned selection and unresolved Parameter counts cannot supply global literal bounds" {
  let claim = proof("actql.bound.top-k", 7, "{\"maximum\":7,\"op\":\"clamp\"}")
  let partitioned = pipeline(
    "[{\"top_k_by\":{\"partition_by\":[\"id\"],\"k\":7,\"by\":[{\"id\":\"asc\"}]}}]",
  )
  assert_true(
    @capacity_program_step.check(partitioned, 0, claim)
    is Err(UnsupportedOperation),
  )
  let d = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"default\":7}}")),
    { max_parameters: 1, max_nodes: 30, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let p = pipeline("[{\"take\":{\"$param\":\"n\"}}]", parameters=Some(d))
  assert_true(
    @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}"),
    )
    is Err(UnresolvedCount),
  )
}
