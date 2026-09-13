///|
test "sequence atomic checks retain independent original claims and reject foreign owners" {
  let source = asof_test_cursor(
    "[{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"id\",\"pattern\":[{\"as\":\"a\",\"where\":\"TRUE\"},{\"as\":\"b\",\"where\":\"TRUE\"}],\"within\":10,\"overlap\":\"allow\",\"contiguity\":\"subsequence\"}}]",
  )
  let schema = @schema.from_object(
    @contract.object_contract(
      [("id", @contract.primitive(NumberType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  ).unwrap()
  let build = fn() {
    @pipeline.check(source, [("rows", schema)], None, None, {
      max_steps: 1,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    }).unwrap()
  }
  let pipeline = build()
  let sources = sequence_limit_sources()
  let policy = sequence_limit_policy(false)
  let limits = @sequence_limits.check_host_limits(
    pipeline,
    0,
    sources,
    policy,
    0,
    1,
    max_work=4,
  ).unwrap()
  let step = @pipeline.step_at(pipeline, 0).unwrap()
  let obligations = @pipeline.operation_obligation_group_at(step.operation, 1).unwrap()
  let mut found = false
  for index in 0..<@pipeline.operation_obligations_count(obligations) {
    let requirement = @pipeline.operation_obligations_at(obligations, index).unwrap()
    if requirement is @pipeline.SequenceRequirement(AtomicMatchLimits) {
      found = true
      let site : OperationRequirementSite = {
        stage: 1,
        producer_visit: 2,
        step: 0,
        group: 1,
        index,
        pipeline,
        obligations,
        requirement,
      }
      guard sequence_limits_check(site, limits, policy)
        is Ok(SequenceLimits(check)) else {
        fail("atomic limits")
      }
      assert_true(physical_equal(check.site, site))
      assert_true(physical_equal(check.step, step))
      assert_true(physical_equal(check.limits, limits))
      for
        (scope, expected) in [
          (@sequence_limits.MatchesPerKey, 3L),
          (OutputRows, 7L),
        ] {
        let claim = @sequence_limits.limit(check.limits, scope)
        assert_eq(
          @derivation.minimum_value(@wire.limit_minimum(claim)),
          expected,
        )
        assert_eq(@wire.limit_enforcement(claim), @wire.EngineAtomic)
        assert_true(
          physical_equal(claim, @sequence_limits.limit(limits, scope)),
        )
      }
      assert_eq(
        operation_execution_phase(SequenceLimits(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(SequenceLimits(check)),
        RejectOperationOutput,
      )
      for
        changed in [
          { ..site, pipeline: build(), },
          { ..site, step: 1, },
          { ..site, index: 100, },
          {
            ..site,
            requirement: @pipeline.SequenceRequirement(BoundedMatchSearch),
          },
        ] {
        assert_true(
          sequence_limits_check(changed, limits, policy)
          is Err(ForeignOccurrence(_)),
        )
      }
      assert_true(
        sequence_limits_check(site, limits, sequence_limit_policy(true))
        is Err(ForeignOccurrence(_)),
      )
    }
  }
  assert_true(found)
}
