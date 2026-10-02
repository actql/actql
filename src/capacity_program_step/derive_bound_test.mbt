///|
fn derive_limits() -> @capacity_program_step.DeriveBoundLimits {
  {
    max_input_work: 10000,
    max_operand_work: 10000,
    max_reference_work: 10000,
    metadata: { max_bytes: 100000, max_nodes: 10000, max_depth: 30, },
  }
}

///|
test "derived operation preparation spends one aggregate work budget across its scopes" {
  let root = pipeline("[{\"take\":7}]")
  let a = @capacity_program_step.derive_bound(
    root,
    0,
    [],
    derive_limits(),
    max_work=24,
  ).unwrap()
  // Independent structure: a source proof has seven nodes; the complete take
  // witness has sixteen, including maximum and self CID. One dependency visit.
  assert_eq(a.metadata_nodes, 23)
  assert_eq(a.work, 24)
  assert_true(
    @capacity_program_step.derive_bound(
      root,
      0,
      [],
      derive_limits(),
      max_work=23,
    )
    is Err(_),
  )
  let middle = consume(root, @pipeline.Step(0), "[]")
  let end = consume(
    middle,
    @pipeline.Input(0),
    "[{\"append\":{\"with\":\"prior\"}}]",
  )
  let inputs = [@capacity_program_step.StepInput(a.bound), StepInput(a.bound)]
  // Nine proof nodes plus eighteen complete witness nodes, four import-edge
  // visits and ten copy/sort/dependency steps. Each scope fits forty, their
  // sum does not. These expectations do not come from a remaining-work counter.
  let exact = @capacity_program_step.derive_bound(
    end,
    0,
    inputs,
    derive_limits(),
    max_work=41,
  ).unwrap()
  assert_eq(exact.metadata_nodes, 27)
  assert_eq(exact.work, 41)
  assert_true(
    @capacity_program_step.derive_bound(
      end,
      0,
      inputs,
      derive_limits(),
      max_work=40,
    )
    is Err(_),
  )
  let broad = @capacity_program_step.derive_bound(
    end,
    0,
    inputs,
    derive_limits(),
  ).unwrap()
  assert_eq(bound_id(exact.bound), bound_id(broad.bound))
  assert_eq(exact.metadata_bytes, broad.metadata_bytes)
  for max_work in [-1, 0, 1, 2, 3, 4, 5, 13, 14, 15] {
    assert_true(
      @capacity_program_step.derive_bound(
        end,
        0,
        inputs,
        derive_limits(),
        max_work~,
      )
      is Err(_),
    )
  }
}

///|
fn assert_derived_application(
  p : @pipeline.CheckedPipeline,
  index : Int,
  inputs : Array[@capacity_program_step.BoundInput],
  expected : Int64,
) -> @capacity_program_step.StepBound raise {
  let result = @capacity_program_step.derive_bound(
    p,
    index,
    inputs,
    derive_limits(),
  ).unwrap()
  let claim = @capacity_program_step.checked_proof(result.bound)
  assert_eq(@wire.value(@wire.program_proof_witness(claim)), expected)
  ignore(
    @capacity_program_step.check_with_sources(
      p,
      index,
      claim,
      inputs,
      max_input_work=10000,
      max_operand_work=10000,
    ).unwrap(),
  )
  result.bound
}

///|
test "compiler construction covers source clamp multiply preserve and ranking derivations" {
  let p = pipeline(
    "[{\"take\":7},{\"take\":3},{\"unpivot\":{\"columns\":[\"id\",\"id\"],\"keep\":[],\"name_column\":\"name\",\"value_column\":\"value\"}}]",
  )
  let a = assert_derived_application(p, 0, [], 7)
  let b = assert_derived_application(p, 1, [StepInput(a)], 3)
  ignore(assert_derived_application(p, 2, [StepInput(b)], 6))
  let p = pipeline(
    "[{\"take\":3,\"as\":\"l\"},{\"take\":7,\"from\":\"rows\",\"as\":\"r\"},{\"from\":\"l\",\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"id\",\"right_time\":\"id\",\"left_id\":\"id\",\"direction\":\"backward\",\"tolerance\":1,\"select\":{\"id\":\"left.id\"}}}]",
  )
  let a = assert_derived_application(p, 0, [], 3)
  ignore(assert_derived_application(p, 2, [StepInput(a)], 3))
  for global in [false, true] {
    let p = fusion_pipeline(global, 3)
    let a = assert_derived_application(p, 0, [], 3)
    ignore(
      assert_derived_application(
        p,
        2,
        [StepInput(a), StepInput(a), StepInput(a)],
        if global {
          5
        } else {
          9
        },
      ),
    )
    if global {
      ignore(assert_derived_application(p, 2, [], 5))
    }
  }
  let p = pipeline(
    "[{\"take\":1},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"c\"},{\"take\":3,\"from\":\"rows\"},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"q\"},{\"nearest\":{\"queries\":\"q\",\"k\":2,\"metric\":\"dot\"},\"from\":\"c\"}]",
    field_type=@contract.vector_contract(2, nullable=false).unwrap(),
  )
  let c = assert_derived_application(p, 0, [], 1)
  let q = assert_derived_application(p, 3, [], 3)
  ignore(assert_derived_application(p, 6, [StepInput(q)], 6))
  ignore(assert_derived_application(p, 6, [StepInput(c), StepInput(q)], 3))
}

///|
test "compiler derived append retains repeated owned inputs and matches independent wire" {
  let p = pipeline("[{\"take\":7,\"as\":\"a\"},{\"append\":{\"with\":\"a\"}}]")
  let a = @capacity_program_step.derive_bound(p, 0, [], derive_limits()).unwrap()
  let expected_a = proof(
    "actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}",
  )
  assert_eq(
    bound_id(a.bound),
    @wire.cid(@wire.program_proof_witness(expected_a)),
  )
  let inputs = [
    @capacity_program_step.StepInput(a.bound),
    @capacity_program_step.StepInput(a.bound),
  ]
  let sum = @capacity_program_step.derive_bound(p, 1, inputs, derive_limits()).unwrap()
  let id = bound_id(a.bound)
  let expected = proof(
    "actql.bound.append",
    14,
    "{\"left\":\"" + id + "\",\"op\":\"add\",\"right\":\"" + id + "\"}",
    reference="checked-step:1",
    inputs=[id, id],
  )
  assert_eq(
    bound_id(sum.bound),
    @wire.cid(@wire.program_proof_witness(expected)),
  )
  let claim = @capacity_program_step.checked_proof(sum.bound)
  assert_eq(@wire.program_proof_input_count(claim), 2)
  assert_eq(@wire.dependencies(@wire.program_proof_witness(claim)).length(), 2)
  assert_true(
    @capacity_program_step.check_with_sources(p, 1, claim, inputs) is Ok(_),
  )
  ignore(
    @capacity_program_step.check_applications(
      program_claims([expected_a, expected]),
      [a.bound, sum.bound],
      max_work=100,
    ).unwrap(),
  )
  inputs.clear()
  assert_eq(@capacity_program_step.input_count(sum.bound), 2)
  assert_true(
    physical_equal(
      @capacity_program_step.input_at(sum.bound, 0).unwrap(),
      a.bound,
    ),
  )
  assert_true(
    physical_equal(
      @capacity_program_step.input_at(sum.bound, 1).unwrap(),
      a.bound,
    ),
  )
}

///|
test "compiler derived values reserves independent complete artifact sizes" {
  let p = generator_pipeline(
    "\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]}",
  )
  let exact : @capacity_program_step.DeriveBoundLimits = {
    ..derive_limits(),
    max_reference_work: 1,
    metadata: { max_bytes: 606, max_nodes: 22, max_depth: 30, },
  }
  let v = @capacity_program_step.derive_bound(p, 0, [], exact).unwrap()
  assert_eq(v.metadata_bytes, 606)
  assert_eq(v.metadata_nodes, 22)
  assert_eq(v.reference_work, 1)
  let expected = proof("actql.bound.values", 0, "{\"op\":\"source\"}")
  assert_eq(bound_id(v.bound), @wire.cid(@wire.program_proof_witness(expected)))
  for
    short in [
      { ..exact, metadata: { ..exact.metadata, max_bytes: 605, }, },
      { ..exact, metadata: { ..exact.metadata, max_nodes: 21, }, },
      { ..exact, max_reference_work: 0, },
    ] {
    assert_true(@capacity_program_step.derive_bound(p, 0, [], short) is Err(_))
  }
}

///|
test "compiler derivation rejects foreign equal-CID owners and arithmetic overflow" {
  let body = "[{\"take\":7,\"as\":\"a\"},{\"append\":{\"with\":\"a\"}}]"
  let p = pipeline(body)
  let foreign = pipeline(body)
  let a = @capacity_program_step.derive_bound(p, 0, [], derive_limits()).unwrap().bound
  let b = @capacity_program_step.derive_bound(foreign, 0, [], derive_limits()).unwrap().bound
  assert_eq(bound_id(a), bound_id(b))
  assert_true(
    @capacity_program_step.derive_bound(
      p,
      1,
      [StepInput(a), StepInput(b)],
      derive_limits(),
    )
    is Err(Application(_)),
  )
  let large = pipeline(
    "[{\"group\":{\"by\":[],\"aggregates\":{}}},{\"take\":9007199254740991,\"as\":\"a\"},{\"append\":{\"with\":\"a\"}}]",
  )
  let input = @capacity_program_step.derive_bound(large, 1, [], derive_limits()).unwrap().bound
  assert_true(
    @capacity_program_step.derive_bound(
      large,
      2,
      [StepInput(input), StepInput(input)],
      derive_limits(),
    )
    is Err(Application(BoundOverflow)),
  )
}

///|
test "compiler derived bounds preserve imported edges under cumulative work limits" {
  let root = pipeline("[{\"take\":7}]")
  let a = @capacity_program_step.derive_bound(root, 0, [], derive_limits()).unwrap().bound
  let middle = consume(root, @pipeline.Step(0), "[]")
  let end = consume(
    middle,
    @pipeline.Input(0),
    "[{\"append\":{\"with\":\"prior\"}}]",
  )
  let inputs = [
    @capacity_program_step.StepInput(a),
    @capacity_program_step.StepInput(a),
  ]
  // Two import edges per operand. Sorting two equal CIDs costs two copies,
  // one comparison and two merge writes; preparation copies two inputs and
  // dependency construction visits two operands plus the proof reference.
  let caps = { ..derive_limits(), max_input_work: 4, max_reference_work: 10, }
  let result = @capacity_program_step.derive_bound(end, 0, inputs, caps).unwrap()
  assert_eq(@capacity_program_step.input_work(result.bound), 4)
  assert_eq(result.reference_work, 10)
  for
    short in [
      { ..caps, max_input_work: 3, },
      { ..caps, max_reference_work: 9, },
    ] {
    assert_true(
      @capacity_program_step.derive_bound(end, 0, inputs, short) is Err(_),
    )
  }
  assert_true(
    @capacity_program_step.check_with_sources(
      end,
      0,
      @capacity_program_step.checked_proof(result.bound),
      inputs,
      max_input_work=4,
    )
    is Ok(_),
  )
}

///|
test "compiler derived graph measures preserve units and repeated structural operands" {
  let p = keyed_repeated_measure_pipeline()
  let seed = @capacity_program_step.derive_bound(p, 0, [], derive_limits()).unwrap().bound
  let node = @capacity_program_step.derive_bound(
      p,
      1,
      [StepInput(seed)],
      derive_limits(),
      unit=@arithmetic.Nodes,
    ).unwrap().bound
  let inputs = [
    @capacity_program_step.StepInput(seed),
    StepInput(seed),
    StepInput(seed),
  ]
  let result = @capacity_program_step.derive_bound(
    p,
    1,
    inputs,
    { ..derive_limits(), max_operand_work: 15, },
    unit=@arithmetic.Edges,
  ).unwrap()
  let claim = @capacity_program_step.checked_proof(result.bound)
  assert_eq(@wire.unit(@wire.program_proof_witness(claim)), @arithmetic.Edges)
  assert_eq(@wire.value(@wire.program_proof_witness(claim)), 3)
  assert_eq(@wire.program_proof_input_count(claim), 3)
  assert_true(
    @capacity_program_step.check_with_sources(
      p,
      1,
      claim,
      inputs,
      max_operand_work=15,
    )
    is Ok(_),
  )
  assert_true(
    @capacity_program_step.derive_bound(
      p,
      1,
      inputs,
      { ..derive_limits(), max_operand_work: 14, },
      unit=@arithmetic.Edges,
    )
    is Err(Application(OperandWorkLimit)),
  )
  assert_true(
    @capacity_program_step.derive_bound(
      p,
      1,
      [StepInput(node), StepInput(node), StepInput(node)],
      derive_limits(),
      unit=@arithmetic.Edges,
    )
    is Err(Application(InputUnitMismatch(0))),
  )
}
