///|
fn incoming_fixture(accepted? : Bool = false) -> ProgramSourceIdentity {
  let (operations, references, bindings) = program_sources_fixture(accepted~)
  identify_program_sources(
    bind_program_sources(operations, references, bindings, 10000000).unwrap(),
    identity_limits(),
  ).unwrap()
}

///|
test "incoming requirements join exact local identities and checked Result ports" {
  let completed = incoming_fixture()
  for accepted in [false, true] {
    let identity = incoming_fixture(accepted~)
    // The local source Definition excludes after; the incoming requirement
    // must preserve its meaning rather than relying on that Definition CID.
    for i in 0..<2 {
      assert_eq(
        stage_identity_definition_cid(
          program_identity_stage_at(identity, i).unwrap(),
        ),
        stage_identity_definition_cid(
          program_identity_stage_at(completed, i).unwrap(),
        ),
      )
    }
    if accepted {
      assert_not_eq(
        program_identity_definition_cid(identity),
        program_identity_definition_cid(completed),
      )
    }
    let limits : IncomingLimits = {
      max_work: 10000000,
      max_name_units: 1000,
      max_requirements: 10,
    }
    let v = collect_program_incoming(identity, limits).unwrap()
    assert_true(physical_equal(program_incoming_identity(v), identity))
    assert_eq(program_incoming_namespace(v, 0), Some(("p", "first")))
    assert_eq(program_incoming_namespace(v, 1), Some(("p", "second")))
    assert_eq(program_incoming_count(v), 2)
    for invalid in [-2147483648, -1, 2, 2147483647] {
      assert_true(program_incoming_at(v, invalid) is None)
      assert_true(program_incoming_namespace(v, invalid) is None)
    }
    let gate = program_incoming_at(v, 0).unwrap()
    assert_eq(gate.stage, 1)
    assert_true(
      physical_equal(
        gate.consumer,
        program_identity_stage_at(identity, 1).unwrap(),
      ),
    )
    match gate.requirement {
      Success(milestone, producer) => {
        assert_eq(milestone, if accepted { Accepted } else { Completed })
        assert_true(
          physical_equal(
            producer,
            program_identity_stage_at(identity, 0).unwrap(),
          ),
        )
      }
      _ => fail("missing incoming success requirement")
    }
    let input = program_incoming_at(v, 1).unwrap()
    assert_eq(input.stage, 1)
    assert_true(physical_equal(input.consumer, gate.consumer))
    let wiring = program_incoming_wiring(v)
    match input.requirement {
      Result(name, producer, port) => {
        assert_eq(name, "a")
        assert_eq(@stage_results.input_name(port), name)
        assert_true(
          physical_equal(
            producer,
            program_identity_stage_at(identity, 0).unwrap(),
          ),
        )
        let imports = @stage_results.attached_imports(
          @stage_results.wiring_imports_at(wiring, 1).unwrap(),
        )
        assert_true(
          physical_equal(port, @stage_results.import_at(imports, 0).unwrap()),
        )
        let result = @stage_results.input_port(port)
        assert_eq(@results.name(@results.port_result(result)), "out")
        assert_true(
          physical_equal(
            @results.port_input(result),
            @stage_results.input_producer(port),
          ),
        )
      }
      _ => fail("missing checked Result edge")
    }
    let (work, names) = program_incoming_usage(v)
    // Every name unit is also aggregate work, independently of the name cap.
    assert_true(work > names)
    let exact : IncomingLimits = {
      max_work: work,
      max_name_units: names,
      max_requirements: 2,
    }
    assert_true(collect_program_incoming(identity, exact) is Ok(_))
    for
      short in [
        { ..exact, max_work: work - 1, },
        { ..exact, max_name_units: names - 1, },
        { ..exact, max_requirements: 1, },
        { ..exact, max_work: 0, },
      ] {
      assert_true(
        collect_program_incoming(identity, short) is Err(BudgetExceeded),
      )
    }
    for
      invalid in [
        { ..exact, max_work: -1, },
        { ..exact, max_name_units: -1, },
        { ..exact, max_requirements: -1, },
      ] {
      assert_true(
        collect_program_incoming(identity, invalid) is Err(InvalidLimits),
      )
    }
    let foreign = incoming_fixture(accepted~)
    let other = collect_program_incoming(foreign, limits).unwrap()
    // Equal public identities are not interchangeable admission owners.
    assert_eq(
      program_identity_definition_cid(foreign),
      program_identity_definition_cid(identity),
    )
    assert_false(
      physical_equal(
        program_incoming_at(other, 0).unwrap().consumer,
        gate.consumer,
      ),
    )
    assert_false(physical_equal(program_incoming_wiring(other), wiring))
  }
}
