///|
test "capacity uses retain exact admitted limits and repeated operand roles" {
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"derive\":{}}],\"results\":{\"r\":{\"from\":\"generated\"}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
    {
      source: { max_input_bytes: 1000, max_nodes: 100, max_depth: 10, },
      tree: {
        max_nodes: 100,
        max_depth: 10,
        max_string_bytes: 1000,
        max_total_string_bytes: 1000,
      },
      max_stages: 1,
    },
    format=Json,
  ).unwrap()
  let sources = sequence_limit_sources()
  let mixed = @wire.program_claim_mixed(@host.source_claims(sources)).unwrap()
  let a = @wire.mixed_limit_at(mixed, 0).unwrap()
  let b = @wire.mixed_limit_at(mixed, 1).unwrap()
  let uses : Array[CapacityUse] = [
    Sequence(step=0, matches=a, output=b),
    Join(step=0, output=b),
    Traversal(step=0, paths=b, output=b),
  ]
  let entries = [{ stage: "s", sources, uses, }]
  let inputs = bind_capacity_inputs(program, entries, 10000).unwrap()
  assert_true(physical_equal(inputs.materials[0].sources, sources))
  assert_eq(inputs.materials[0].consumers, [
    @capacity.Sequence(step=0, matches=0, output=1),
    @capacity.Join(step=0, output=1),
    @capacity.Traversal(step=0, paths=1, output=1),
  ])
  assert_true(bind_capacity_inputs(program, entries, inputs.work) is Ok(_))
  assert_true(
    bind_capacity_inputs(program, entries, inputs.work - 1)
    is Err(BudgetExceeded),
  )
  uses.clear()
  assert_eq(inputs.materials[0].consumers.length(), 3)
  let foreign_sources = sequence_limit_sources()
  let foreign = @wire.mixed_limit_at(
    @wire.program_claim_mixed(@host.source_claims(foreign_sources)).unwrap(),
    1,
  ).unwrap()
  assert_eq(@wire.limit_cid(foreign), @wire.limit_cid(b))
  assert_true(
    bind_capacity_inputs(
      program,
      [{ stage: "s", sources, uses: [Join(step=0, output=foreign)], }],
      10000,
    )
    is Err(ForeignLimit(0, 0)),
  )
  for step in [-1, 1] {
    assert_true(
      bind_capacity_inputs(
        program,
        [{ stage: "s", sources, uses: [Join(step~, output=b)], }],
        10000,
      )
      is Err(InvalidStep(0, 0)),
    )
  }
}
