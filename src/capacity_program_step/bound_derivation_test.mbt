///|
test "supplied retained derivations meter rejected input traversal without rebuilding metadata" {
  let root = pipeline("[{\"take\":7}]")
  let seed = @capacity_program_step.derive_bound(root, 0, [], derive_limits()).unwrap().bound
  let middle = consume(root, @pipeline.Step(0), "[]")
  let end = consume(
    middle,
    @pipeline.Input(0),
    "[{\"append\":{\"with\":\"prior\"}}]",
  )
  let inputs = [@capacity_program_step.StepInput(seed), StepInput(seed)]
  let emitted = @capacity_program_step.derive_bound(
    end,
    0,
    inputs,
    derive_limits(),
  ).unwrap()
  let request = @capacity_program_step.prepare_bound_derivation(end, 0).unwrap()
  let claim = @capacity_program_step.checked_proof(emitted.bound)
  // Two import edges per operand; repeated operands still make four visits.
  let (exact, work) = @capacity_program_step.check_prepared_bound(
    request, claim, inputs, 4,
  )
  assert_eq(work, 4)
  assert_eq(bound_id(exact.unwrap()), bound_id(emitted.bound))
  let (short, work) = @capacity_program_step.check_prepared_bound(
    request, claim, inputs, 3,
  )
  assert_true(short is Err(InputWorkLimit))
  assert_eq(work, 3)
  let foreign = @capacity_program_step.derive_bound(
      pipeline("[{\"take\":7}]"),
      0,
      [],
      derive_limits(),
    ).unwrap().bound
  assert_eq(bound_id(seed), bound_id(foreign))
  let (rejected, work) = @capacity_program_step.check_prepared_bound(
    request,
    claim,
    [StepInput(foreign), StepInput(seed)],
    4,
  )
  // The foreign target is never reached: after both import edges and take,
  // the root input has no producer. That unsuccessful lookup is charged too.
  assert_true(rejected is Err(MissingInputProducer(0)))
  assert_eq(work, 4)
}

///|
test "retained bound derivations expose exact operand shapes without weakening admission" {
  let p = pipeline(
    "[{\"take\":7},{\"take\":3,\"as\":\"a\"},{\"append\":{\"with\":\"a\"}}]",
  )
  let take = @capacity_program_step.prepare_bound_derivation(p, 1).unwrap()
  assert_true(physical_equal(take.pipeline, p))
  assert_eq(take.index, 1)
  assert_eq(take.input_count, 1)
  assert_eq(take.fallback_input_count, Some(0))
  let operand = @capacity_program_step.bound_derivation_input_at(take, 1, 0).unwrap()
  assert_eq(operand.target, @pipeline.Step(0))
  assert_eq(operand.edge, 0)
  assert_eq(operand.unit, @arithmetic.Rows)
  for (count, index) in [(0, 0), (1, -1), (1, 1), (2, 0), (-1, 0)] {
    assert_true(
      @capacity_program_step.bound_derivation_input_at(take, count, index)
      is None,
    )
  }
  let a = @capacity_program_step.derive_bound(p, 0, [], derive_limits()).unwrap().bound
  let direct = @capacity_program_step.derive_bound(
    p,
    1,
    [StepInput(a)],
    derive_limits(),
  ).unwrap()
  let retained = @capacity_program_step.derive_prepared_bound(
    take,
    [StepInput(a)],
    derive_limits(),
  ).unwrap()
  assert_eq(bound_id(direct.bound), bound_id(retained.bound))
  assert_eq(direct.work, retained.work)
  let append = @capacity_program_step.prepare_bound_derivation(p, 2).unwrap()
  assert_eq(append.input_count, 2)
  assert_eq(append.fallback_input_count, None)
  for i in 0..<2 {
    let operand = @capacity_program_step.bound_derivation_input_at(append, 2, i).unwrap()
    assert_eq(operand.target, @pipeline.Step(1))
    assert_eq(operand.edge, i)
  }
  let foreign = @capacity_program_step.derive_bound(
      pipeline("[{\"take\":7}]"),
      0,
      [],
      derive_limits(),
    ).unwrap().bound
  assert_true(
    @capacity_program_step.derive_prepared_bound(
      take,
      [StepInput(foreign)],
      derive_limits(),
    )
    is Err(Application(_)),
  )
}

///|
test "bound operand readers distinguish query fallback graph measures and ranking arities" {
  let p = pipeline(
    "[{\"take\":1},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"c\"},{\"take\":3,\"from\":\"rows\"},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"},\"as\":\"q\"},{\"nearest\":{\"queries\":\"q\",\"k\":2,\"metric\":\"dot\"},\"from\":\"c\"}]",
    field_type=@contract.vector_contract(2, nullable=false).unwrap(),
  )
  let nearest = @capacity_program_step.prepare_bound_derivation(p, 6).unwrap()
  assert_eq(nearest.input_count, 2)
  assert_eq(nearest.fallback_input_count, Some(1))
  let query = @capacity_program_step.bound_derivation_input_at(nearest, 1, 0).unwrap()
  assert_eq(query.target, @pipeline.Step(5))
  assert_eq(query.edge, 1)
  let candidate = @capacity_program_step.bound_derivation_input_at(
    nearest, 2, 0,
  ).unwrap()
  assert_eq(candidate.target, @pipeline.Step(2))
  assert_eq(candidate.edge, 0)
  for global in [true, false] {
    let p = fusion_pipeline(global, 3)
    let ranking = @capacity_program_step.prepare_bound_derivation(p, 2).unwrap()
    assert_eq(ranking.input_count, 3)
    assert_eq(ranking.fallback_input_count, if global { Some(0) } else { None })
    // Global fallback is zero or all three, not an arbitrary prefix.
    assert_true(
      @capacity_program_step.bound_derivation_input_at(ranking, 1, 0) is None,
    )
    assert_true(
      @capacity_program_step.bound_derivation_input_at(ranking, 2, 0) is None,
    )
    for i in 0..<3 {
      let input = @capacity_program_step.bound_derivation_input_at(
        ranking, 3, i,
      ).unwrap()
      assert_eq(input.target, @pipeline.Step(1))
      assert_eq(input.edge, i)
    }
  }
  let p = graph_measure_pipeline(
    "[" +
    graph_seed("seed", 1) +
    ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"union_graphs\":{\"with\":[\"g\",\"g\"]}}]",
  )
  let graph = @capacity_program_step.prepare_bound_derivation(
    p,
    1,
    unit=@arithmetic.Nodes,
  ).unwrap()
  assert_eq(graph.unit, @arithmetic.Nodes)
  assert_eq(
    @capacity_program_step.bound_derivation_input_at(graph, 1, 0).unwrap().unit,
    @arithmetic.Rows,
  )
  let union = @capacity_program_step.prepare_bound_derivation(
    p,
    2,
    unit=@arithmetic.Edges,
  ).unwrap()
  assert_eq(union.input_count, 3)
  for i in 0..<3 {
    assert_eq(
      @capacity_program_step.bound_derivation_input_at(union, 3, i).unwrap().unit,
      @arithmetic.Edges,
    )
  }
}

///|
test "forwarded bound readers use the existing measure-specific transfer rules" {
  let p = pipeline(
    "[{\"take\":3},{\"filter\":\"id > 0\"},{\"append\":{\"with\":\"rows\"}}]",
  )
  assert_eq(
    @capacity_program_step.forwarded_bound_target(p, 1, @arithmetic.Rows),
    Some(@pipeline.Step(0)),
  )
  assert_eq(
    @capacity_program_step.forwarded_bound_target(p, 1, @arithmetic.Nodes),
    None,
  )
  assert_eq(
    @capacity_program_step.forwarded_bound_target(p, 2, @arithmetic.Rows),
    None,
  )
  assert_eq(
    @capacity_program_step.forwarded_bound_target(p, -1, @arithmetic.Rows),
    None,
  )
}
