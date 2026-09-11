///|
fn join_branches() -> @pipeline.CheckedPipeline {
  pipeline(
    "[{\"from\":\"rows\",\"join\":{\"with\":\"rows\",\"kind\":\"inner\",\"on\":\"id\"}},{\"from\":\"rows\",\"cross_join\":{\"with\":\"rows\"}},{\"from\":\"rows\",\"interval_join\":{\"with\":\"rows\",\"kind\":\"inner\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"id\"}}}]",
  )
}

///|
test "join collection covers every family and unused branch under a shared budget" {
  let p = join_branches()
  let source = join_limit_sources([], 1, limit_steps=[0, 1, 2])
  let program = @capacity_program_step.check_applications(
    @host.source_claims(source),
    [],
    max_work=2,
  ).unwrap()
  let selected = join_policy()
  let a = @capacity_program_step.check_join_limit(
    p,
    0,
    source,
    program,
    selected,
    0,
    max_work=2,
  ).unwrap()
  let b = @capacity_program_step.check_join_limit(
    p,
    1,
    source,
    program,
    selected,
    1,
    max_work=2,
  ).unwrap()
  let c = @capacity_program_step.check_join_limit(
    p,
    2,
    source,
    program,
    selected,
    2,
    max_work=2,
  ).unwrap()
  let apps = [c, a, b]
  let result = @capacity_program_step.check_join_complete(
    p,
    source,
    program,
    selected,
    apps,
    max_work=15,
  ).unwrap()
  assert_eq(@capacity_program_step.join_application_work(result), 15)
  assert_eq(@capacity_program_step.join_unconsumed_limit_count(result), 0)
  assert_true(
    physical_equal(@capacity_program_step.join_application_pipeline(result), p),
  )
  assert_true(
    physical_equal(
      @capacity_program_step.join_application_sources(result),
      source,
    ),
  )
  assert_true(
    physical_equal(
      @capacity_program_step.join_application_program(result),
      program,
    ),
  )
  assert_true(
    physical_equal(
      @capacity_program_step.join_application_policy(result),
      selected,
    ),
  )
  apps[0] = a
  assert_true(
    physical_equal(
      @capacity_program_step.join_application_at(result, 2).unwrap(),
      c,
    ),
  )
  for i in 0..<3 {
    assert_true(@capacity_program_step.join_consumes_limit(result, i))
  }
  assert_false(@capacity_program_step.join_consumes_limit(result, -1))
  assert_false(@capacity_program_step.join_consumes_limit(result, 3))
  assert_true(
    @capacity_program_step.check_join_complete(
      p,
      source,
      program,
      selected,
      [a, b, c],
      max_work=14,
    )
    is Err(WorkLimit),
  )
  assert_true(
    @capacity_program_step.check_join_complete(
      p,
      source,
      program,
      selected,
      [b, c],
      max_work=13,
    )
    is Err(MissingApplication(0)),
  )
  assert_true(
    @capacity_program_step.check_join_complete(
      p,
      source,
      program,
      selected,
      [a, c],
      max_work=13,
    )
    is Err(MissingApplication(1)),
  )
  assert_true(
    @capacity_program_step.check_join_complete(
      p,
      source,
      program,
      selected,
      [a, b],
      max_work=13,
    )
    is Err(MissingApplication(2)),
  )
  assert_true(
    @capacity_program_step.check_join_complete(
      p,
      source,
      program,
      selected,
      [a, a, c],
      max_work=15,
    )
    is Err(DuplicateApplication(1)),
  )
  assert_true(
    @capacity_program_step.check_join_complete(
      join_branches(),
      source,
      program,
      selected,
      [a, b, c],
      max_work=15,
    )
    is Err(ForeignPipeline(0)),
  )
  let other_program = @capacity_program_step.check_applications(
    @host.source_claims(source),
    [],
    max_work=2,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_join_complete(
      p,
      source,
      other_program,
      selected,
      [a, b, c],
      max_work=15,
    )
    is Err(ForeignProgram(0)),
  )
}

///|
test "join coverage reports unconsumed limits and rejects foreign proof source collections" {
  let p = join_branches()
  let source = join_limit_sources([], 1, limit_steps=[0, 1, 2, 9])
  let program = @capacity_program_step.check_applications(
    @host.source_claims(source),
    [],
    max_work=2,
  ).unwrap()
  let selected = join_policy()
  let apps : Array[@capacity_program_step.JoinLimit] = []
  for i in 0..<3 {
    apps.push(
      @capacity_program_step.check_join_limit(
        p,
        i,
        source,
        program,
        selected,
        i,
        max_work=2,
      ).unwrap(),
    )
  }
  let partial = @capacity_program_step.check_join_applications(
    p,
    source,
    program,
    selected,
    apps,
    max_work=16,
  ).unwrap()
  assert_eq(@capacity_program_step.join_unconsumed_limit_count(partial), 1)
  assert_false(@capacity_program_step.join_consumes_limit(partial, 3))
  assert_true(
    @capacity_program_step.check_join_complete(
      p,
      source,
      program,
      selected,
      apps,
      max_work=16,
    )
    is Err(UnconsumedLimits(1)),
  )
  let foreign = join_limit_sources([], 1, limit_steps=[0, 1, 2, 9])
  assert_true(
    @capacity_program_step.check_join_applications(
      p,
      foreign,
      program,
      selected,
      apps,
      max_work=16,
    )
    is Err(ForeignClaims),
  )
  let foreign_program = @capacity_program_step.check_applications(
    @host.source_claims(foreign),
    [],
    max_work=2,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_join_applications(
      p,
      foreign,
      foreign_program,
      selected,
      apps,
      max_work=16,
    )
    is Err(ForeignSources(0)),
  )
  assert_true(
    @capacity_program_step.check_join_complete(
      p,
      source,
      program,
      selected,
      apps,
      max_work=-1,
    )
    is Err(InvalidLimits),
  )
  let empty = pipeline("[]")
  let empty_source = join_limit_sources([], 1, limit_steps=[])
  let empty_program = @capacity_program_step.check_applications(
    @host.source_claims(empty_source),
    [],
    max_work=2,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_join_complete(
      empty,
      empty_source,
      empty_program,
      selected,
      [],
      max_work=0,
    )
    is Ok(_),
  )
}
