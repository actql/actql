///|
test "SourceView Event round trips preserve policy across bridge and event operations" {
  for kind in ["bridge", "mark", "drop", "dedupe", "session"] {
    let program = checked_direct_program_fixture(event_kind=kind)
    let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(
      publication_policy_carrier_step_count(policy),
      if kind == "bridge" {
        2
      } else {
        3
      },
    )
    let mut bridges = 0
    let mut operations = 0
    let mut projections = 0
    for i in 0..<publication_policy_carrier_step_count(policy) {
      let retained = publication_policy_carrier_step_at(policy, i).unwrap()
      let original = @pipeline.step_at(program.units[0].pipeline, retained.step).unwrap().operation
      match (original, retained.operation) {
        (Event(a), Event(b)) => {
          assert_true(physical_equal(a, b))
          if @event.options(b) is ToEvents {
            bridges += 1
            assert_false(retained.unknown_provenance)
          } else {
            operations += 1
            assert_eq(retained.unknown_provenance, kind != "dedupe")
          }
        }
        (Projection(a), Projection(b)) => {
          projections += 1
          assert_true(physical_equal(a, b))
          assert_false(retained.unknown_provenance)
        }
        _ => fail("Carrier operation changed")
      }
    }
    assert_eq((bridges, projections), (1, 1))
    assert_eq(operations, if kind == "bridge" { 0 } else { 1 })
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut admissions = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(EventExecution(check))) {
        admissions += 1
        let mut matched = false
        for j in 0..<publication_policy_carrier_step_count(policy) {
          let retained = publication_policy_carrier_step_at(policy, j).unwrap()
          if retained.step == check.site.step &&
            retained.operation is Event(operation) {
            assert_true(physical_equal(operation, check.operation))
            matched = true
          }
        }
        assert_true(matched)
      }
    }
    assert_true(admissions > 0)
    assert_true(publication_policy_carrier_step_at(policy, -1) is None)
    assert_true(
      publication_policy_carrier_step_at(
        policy,
        publication_policy_carrier_step_count(policy),
      )
      is None,
    )
  }
}
