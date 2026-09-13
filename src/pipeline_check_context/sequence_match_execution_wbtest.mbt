///|
test "sequence matching retains exact within bindings and rejects foreign resolutions" {
  for symbolic in [false, true] {
    let declarations = @parameter.read_declarations(
      Some(
        asof_test_cursor("{\"window\":{\"type\":\"number\",\"default\":1000}}"),
      ),
      {
        max_parameters: 1,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      },
    ).unwrap()
    guard @parameter.bind(declarations, None, {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap()
      is @parameter.Ready(values) else {
      fail("bindings")
    }
    let parameter = @parameter.bound_value_at(values, 0).unwrap()
    let within = if symbolic { "{\"$param\":\"window\"}" } else { "1000" }
    let source = asof_test_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"id\",\"pattern\":[{\"as\":\"a\",\"where\":\"TRUE\"},{\"as\":\"b\",\"where\":\"TRUE\"}],\"within\":" +
      within +
      ",\"overlap\":\"allow\",\"contiguity\":\"subsequence\"}}]",
    )
    let pipeline = @pipeline.check_with_evidence(
      source,
      [],
      Some(declarations),
      None,
      {
        max_steps: 2,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      },
    ).unwrap()
    let step = @pipeline.step_at(pipeline, 1).unwrap()
    let obligations = @pipeline.operation_obligation_group_at(step.operation, 1).unwrap()
    let entries : Array[OperationRequirementSite] = []
    let mut scalar_index = -1
    let mut match_index = -1
    for index in 0..<@pipeline.operation_obligations_count(obligations) {
      let requirement = @pipeline.operation_obligations_at(obligations, index).unwrap()
      if requirement is @pipeline.SequenceRequirement(BindWithin(_)) {
        scalar_index = index
      }
      if requirement is @pipeline.SequenceRequirement(BoundedMatchSearch) {
        match_index = index
      }
      entries.push({
        stage: 1,
        producer_visit: 2,
        step: 1,
        group: 1,
        index,
        pipeline,
        obligations,
        requirement,
      })
    }
    let states : Array[OperationResolutionState] = Array::make(
      entries.length(),
      Unresolved,
    )
    let scalar : OperationScalarResolution? = if symbolic {
      Some({
        requirement_index: scalar_index,
        site: entries[scalar_index],
        parameter,
        value: Milliseconds(1000L),
      })
    } else {
      None
    }
    if scalar is Some(scalar) {
      states[scalar_index] = Resolved(Scalar(scalar))
    }
    let site = entries[match_index]
    let (result, work) = sequence_match_check(
      site, match_index, entries, states, 1000,
    )
    guard result is Ok(Some(SequenceMatch(check))) else {
      fail("matching check")
    }
    assert_true(physical_equal(check.site, site))
    assert_eq(check.within_ms, 1000L)
    assert_eq(check.input, @pipeline.Step(0))
    assert_eq(
      operation_execution_phase(SequenceMatch(check)),
      BeforeOperationOutput,
    )
    assert_eq(
      operation_execution_failure(SequenceMatch(check)),
      RejectOperationOutput,
    )
    assert_true(
      sequence_match_check(site, match_index, entries, states, work).0
      is Ok(Some(_)),
    )
    assert_true(
      sequence_match_check(site, match_index, entries, states, work - 1).0
      is Err(BudgetExceeded),
    )
    assert_true(
      sequence_match_check(
        { ..site, producer_visit: 3, },
        match_index,
        entries,
        states,
        1000,
      ).0
      is Err(ForeignOccurrence(_)),
    )
    if scalar is Some(scalar) {
      assert_true(physical_equal(check.within_resolution.unwrap(), scalar))
      for
        replacement in [
          OperationResolutionState::Unresolved,
          Resolved(Scalar({ ..scalar, requirement_index: scalar_index + 1, })),
          Resolved(
            Scalar({ ..scalar, site: { ..scalar.site, producer_visit: 3, }, }),
          ),
          Resolved(Scalar({ ..scalar, site: { ..scalar.site, stage: 0, }, })),
          Resolved(Scalar({ ..scalar, value: DurationMilliseconds(1000L), })),
          Resolved(Scalar({ ..scalar, value: Milliseconds(0L), })),
          Resolved(
            Scalar({ ..scalar, value: Milliseconds(9007199254740992L), }),
          ),
        ] {
        let changed = states.copy()
        changed[scalar_index] = replacement
        assert_true(
          sequence_match_check(site, match_index, entries, changed, 1000).0
          is Err(ForeignOccurrence(_)),
        )
      }
    } else {
      assert_true(check.within_resolution is None)
      assert_eq(work, 0)
    }
    for i in 0..<entries.length() {
      if entries[i].requirement
        is @pipeline.SequenceRequirement(AtomicMatchLimits) {
        assert_true(
          sequence_match_check(entries[i], i, entries, states, 1000).0
          is Ok(None),
        )
      }
    }
  }
}
