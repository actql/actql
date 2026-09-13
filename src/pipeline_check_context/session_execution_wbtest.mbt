///|
test "session gap linkage rejects missing and foreign resolutions without partial success" {
  let declarations = @parameter.read_declarations(
    Some(asof_test_cursor("{\"gap\":{\"type\":\"number\",\"default\":1000}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let bound = @parameter.bind(declarations, None, {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
  guard bound is @parameter.Ready(values) else { fail("ready") }
  let parameter = @parameter.bound_value_at(values, 0).unwrap()
  let pipeline = @pipeline.check_with_evidence(
    asof_test_cursor(
      (
        #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[]},"as":"seed"},{"to_events":{"id":"id","time":"id"}},{"session":{"by":[],"gap":{"$param":"gap"}}}]
      ),
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 3,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let step = @pipeline.step_at(pipeline, 2).unwrap()
  let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  let entries : Array[OperationRequirementSite] = []
  let mut scalar_index = -1
  let checks : Array[Int] = []
  for index in 0..<@pipeline.operation_obligations_count(obligations) {
    let requirement = @pipeline.operation_obligations_at(obligations, index).unwrap()
    entries.push({
      stage: 1,
      producer_visit: 2,
      step: 2,
      group: 0,
      index,
      pipeline,
      obligations,
      requirement,
    })
    match requirement {
      @pipeline.EventRequirement(BindGap(_)) => scalar_index = index
      @pipeline.EventRequirement(SessionArithmetic | SessionIdentity) =>
        checks.push(index)
      _ => ()
    }
  }
  assert_true(scalar_index >= 0)
  assert_eq(checks.length(), 2)
  let scalar : OperationScalarResolution = {
    requirement_index: scalar_index,
    site: entries[scalar_index],
    parameter,
    value: Milliseconds(1000L),
  }
  let states : Array[OperationResolutionState] = Array::make(
    entries.length(),
    Unresolved,
  )
  states[scalar_index] = Resolved(Scalar(scalar))
  for index in checks {
    let site = entries[index]
    let (result, work) = session_execution_check(
      site, index, entries, states, 1000,
    )
    guard result is Ok(Some(SessionExecution(check))) else {
      fail("session check")
    }
    assert_eq(check.gap_ms, 1000L)
    assert_true(physical_equal(check.gap_resolution.unwrap(), scalar))
    assert_eq(check.input, @pipeline.Step(1))
    assert_true(work > entries.length())
    assert_true(
      session_execution_check(site, index, entries, states, work).0
      is Ok(Some(_)),
    )
    assert_true(
      session_execution_check(site, index, entries, states, work - 1).0
      is Err(BudgetExceeded),
    )
    assert_true(
      session_execution_check(
        { ..site, producer_visit: 3, },
        index,
        entries,
        states,
        1000,
      ).0
      is Err(ForeignOccurrence(_)),
    )
    for
      replacement in [
        OperationResolutionState::Unresolved,
        Resolved(Scalar({ ..scalar, requirement_index: scalar_index + 1, })),
        Resolved(
          Scalar({ ..scalar, site: { ..scalar.site, producer_visit: 3, }, }),
        ),
        Resolved(Scalar({ ..scalar, site: { ..scalar.site, stage: 0, }, })),
        Resolved(Scalar({ ..scalar, value: DurationMilliseconds(1000L), })),
      ] {
      let changed = states.copy()
      changed[scalar_index] = replacement
      assert_true(
        session_execution_check(site, index, entries, changed, 1000).0
        is Err(ForeignOccurrence(_)),
      )
      assert_true(states[scalar_index] is Resolved(Scalar(_)))
    }
  }
}
