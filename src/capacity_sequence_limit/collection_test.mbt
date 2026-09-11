///|
fn branched_pipeline() -> @pipeline.CheckedPipeline {
  let sequence = "{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"id\",\"pattern\":[{\"as\":\"begin\",\"where\":\"true\"},{\"as\":\"end\",\"where\":\"true\"}],\"within\":1,\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"},\"from\":\"rows\"}"
  pipeline_text("[" + sequence + "," + sequence + "]")
}

///|
test "sequence collection requires unused branches and retains isolated consumption indices" {
  let p = branched_pipeline()
  let sources = fixture_set(0, [0, 1])
  let selected = policy(false)
  let first = @capacity_sequence_limit.check_host_limits(
    p,
    0,
    sources,
    selected,
    0,
    1,
    max_work=4,
  ).unwrap()
  let second = @capacity_sequence_limit.check_host_limits(
    p,
    1,
    sources,
    selected,
    2,
    3,
    max_work=4,
  ).unwrap()
  let applications = [second, first]
  let result = @capacity_sequence_limit.check_complete(
    p,
    sources,
    selected,
    applications,
    max_work=14,
  ).unwrap()
  assert_eq(@capacity_sequence_limit.application_work(result), 14)
  assert_eq(@capacity_sequence_limit.unconsumed_limit_count(result), 0)
  assert_true(
    physical_equal(@capacity_sequence_limit.application_pipeline(result), p),
  )
  assert_true(
    physical_equal(
      @capacity_sequence_limit.application_sources(result),
      sources,
    ),
  )
  assert_true(
    physical_equal(
      @capacity_sequence_limit.application_policy(result),
      selected,
    ),
  )
  assert_true(
    physical_equal(
      @capacity_sequence_limit.application_at(result, 0).unwrap(),
      first,
    ),
  )
  for i in 0..<4 {
    assert_true(@capacity_sequence_limit.consumes_limit(result, i))
  }
  assert_false(@capacity_sequence_limit.consumes_limit(result, -1))
  assert_false(@capacity_sequence_limit.consumes_limit(result, 4))
  assert_true(@capacity_sequence_limit.application_at(result, 2) is None)
  applications[0] = first
  assert_true(
    physical_equal(
      @capacity_sequence_limit.application_at(result, 1).unwrap(),
      second,
    ),
  )
  assert_true(
    @capacity_sequence_limit.check_complete(
      p,
      sources,
      selected,
      [first, second],
      max_work=13,
    )
    is Err(WorkLimit),
  )
  assert_true(
    @capacity_sequence_limit.check_complete(
      p,
      sources,
      selected,
      [second],
      max_work=11,
    )
    is Err(MissingApplication(0)),
  )
  assert_true(
    @capacity_sequence_limit.check_complete(
      p,
      sources,
      selected,
      [first],
      max_work=11,
    )
    is Err(MissingApplication(1)),
  )
  assert_true(
    @capacity_sequence_limit.check_complete(
      p,
      sources,
      selected,
      [first, first],
      max_work=14,
    )
    is Err(DuplicateApplication(1)),
  )
}

///|
test "sequence collection rejects foreign owners and does not consume unrelated limits" {
  let p = pipeline(false, "allow", "")
  let sources = fixture_set(0, [0, 1])
  let selected = policy(false)
  let app = @capacity_sequence_limit.check_host_limits(
    p,
    0,
    sources,
    selected,
    0,
    1,
    max_work=4,
  ).unwrap()
  let partial = @capacity_sequence_limit.check_applications(
    p,
    sources,
    selected,
    [app],
    max_work=9,
  ).unwrap()
  assert_eq(@capacity_sequence_limit.unconsumed_limit_count(partial), 2)
  assert_true(@capacity_sequence_limit.consumes_limit(partial, 0))
  assert_true(@capacity_sequence_limit.consumes_limit(partial, 1))
  assert_false(@capacity_sequence_limit.consumes_limit(partial, 2))
  assert_false(@capacity_sequence_limit.consumes_limit(partial, 3))
  assert_true(
    @capacity_sequence_limit.check_complete(
      p,
      sources,
      selected,
      [app],
      max_work=9,
    )
    is Err(UnconsumedLimits(2)),
  )
  assert_true(
    @capacity_sequence_limit.check_applications(
      p,
      sources,
      selected,
      [app],
      max_work=-1,
    )
    is Err(InvalidLimits),
  )
  let foreign = pipeline(false, "allow", "")
  assert_true(
    @capacity_sequence_limit.check_applications(
      foreign,
      sources,
      selected,
      [app],
      max_work=9,
    )
    is Err(ForeignPipeline(0)),
  )
  assert_true(
    @capacity_sequence_limit.check_applications(
      p,
      fixture_set(0, [0, 1]),
      selected,
      [app],
      max_work=9,
    )
    is Err(ForeignSources(0)),
  )
  assert_true(
    @capacity_sequence_limit.check_applications(
      p,
      sources,
      policy(true),
      [app],
      max_work=9,
    )
    is Err(ForeignPolicy(0)),
  )
  let empty = pipeline_text("[]")
  let empty_sources = fixture_set(0, [])
  assert_true(
    @capacity_sequence_limit.check_complete(
      empty,
      empty_sources,
      selected,
      [],
      max_work=0,
    )
    is Ok(_),
  )
  assert_true(
    @capacity_sequence_limit.check_complete(
      empty,
      sources,
      selected,
      [],
      max_work=4,
    )
    is Err(UnconsumedLimits(4)),
  )
}
