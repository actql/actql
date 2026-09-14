///|
test "public expression bindings retain exact requirement ownership and policy" {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    second_stage=true,
    through_check=true,
    checked_results=checked,
    producer_expression="if(FALSE, regex_extract('x', '(.)', 1), 'x')",
    text_time=true,
    text_policy=true,
  )
  let program = checked[0]
  assert_true(expression_bound_count(program) > 0)
  for index in 0..<expression_bound_count(program) {
    let execution = expression_execution_at(program, index).unwrap()
    let owner = expression_execution_owner(execution)
    assert_true(
      physical_equal(
        @context.expression_closure_identity(owner),
        source_identity(program),
      ),
    )
    let requirement = @context.expression_closure_at(
      owner,
      expression_execution_requirement_index(execution),
    ).unwrap()
    guard requirement.resolution is Envelope(original) else {
      fail("runtime binding does not refer to an envelope requirement")
    }
    let bound = expression_execution_bound(execution)
    assert_true(physical_equal(bound, original))
    assert_true(
      physical_equal(bound, expression_bound_at(program, index).unwrap()),
    )
    assert_true(
      physical_equal(
        @context.text_bound_policy(bound),
        @context.text_bound_policy(original),
      ),
    )
    assert_true(
      physical_equal(
        @context.text_bound_demands(bound),
        @context.text_bound_demands(original),
      ),
    )
    assert_eq(
      @context.validation_site_location(@context.text_bound_site(bound)),
      @context.validation_site_location(requirement.site),
    )
  }
  assert_true(expression_execution_at(program, -1) is None)
  assert_true(
    expression_execution_at(program, expression_bound_count(program)) is None,
  )
}

///|
test "checked Program publication consumer uses only indexed public reads" {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    second_stage=true,
    through_check=true,
    checked_results=checked,
  )
  let program = checked[0]
  assert_eq(unit_count(program), 2)
  assert_eq(unit_result_import_count(program, 0), Some(0))
  assert_eq(unit_result_import_count(program, 1), Some(2))
  for index in 0..<2 {
    let imported = unit_result_import_at(program, 1, index).unwrap()
    assert_eq(
      imported.producer_unit_definition_cid,
      unit_definition_cid(program, 0).unwrap(),
    )
    // The interface includes producer and consumer coordinates; its identity
    // is not the identity of the row type alone.
    assert_true(imported.cid != @context.result_import_type_cid(imported.row))
    let _ = @context.result_import_type_contract(imported.row)
    assert_eq(imported.result_name, "out")
    assert_true(imported.input_name == "rows" || imported.input_name == "again")
  }
  assert_true(unit_result_import_at(program, 1, -1) is None)
  assert_true(unit_result_import_at(program, 1, 2) is None)
  assert_eq(@context.program_identity_stage_count(source_identity(program)), 2)
  for unit in 0..<unit_count(program) {
    let count = unit_contract_count(program, unit).unwrap()
    assert_true(count > 0)
    for index in 0..<count {
      let (cid, body) = unit_contract_at(program, unit, index).unwrap()
      assert_eq(cid, @context.core_contract_cid(body))
    }
    assert_true(unit_contract_at(program, unit, count) is None)
    assert_true(unit_definition_cid(program, unit) is Some(_))
    assert_true(unit_contracts_cid(program, unit) is Some(_))
    assert_true(unit_pipeline(program, unit) is Some(_))
    assert_eq(unit_publication_count(program, unit), Some(1))
    let publication = unit_publication_at(program, unit, 0).unwrap()
    assert_true(publication_phase(publication) is BeforeResultPublication)
    assert_true(publication_failure(publication) is PreventResultPublication)
    let _ = publication_rows(publication)
    let _ = publication_bytes(publication)
    let _ = publication_selection(publication)
    assert_true(unit_publication_at(program, unit, -1) is None)
    assert_true(unit_publication_at(program, unit, 1) is None)
  }
  assert_true(unit_publication_at(program, -1, 0) is None)
  assert_true(unit_publication_count(program, 2) is None)
}

///|
test "check constructs Local and two-stage Result-import Programs from source" {
  for second_stage in [false, true] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (identity, closed, _, _, units) = local_construction_fixture(
      budget,
      second_stage~,
      through_check=true,
    )
    assert_eq(units.length(), if second_stage { 2 } else { 1 })
    assert_eq(@context.program_identity_stage_count(identity), units.length())
    assert_eq(
      @context.local_input_closure_count(
        @context.stage_requirement_inputs(closed),
      ),
      3,
    )
    for unit in units {
      assert_eq(unit.publications.length(), 1)
      assert_true(unit.publications[0].phase is BeforeResultPublication)
      assert_true(unit.publications[0].failure is PreventResultPublication)
    }
    if second_stage {
      assert_eq(units[1].interfaces.length(), 2)
    }
  }
}

///|
test "check rejects unsupported or malformed later steps without a partial result" {
  for
    (steps, source_error) in [
      ("[{\"asof_join\":{}}]", true),
      ("[{\"sequence\":{}}]", true),
      ("[{\"normalize_graph\":{}}]", true),
      ("[{\"subgraph\":{}}]", true),
      ("[{\"traverse\":{}}]", true),
      ("[{\"reach\":{}}]", true),
      ("[{\"shortest_path\":{}}]", true),
      ("[{\"graft_graph\":{}}]", true),
      ("[{\"union_graphs\":{}}]", true),
      ("[{\"subtract_graphs\":{}}]", true),
      ("[null]", false),
    ] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    try
      local_construction_fixture(
        budget,
        second_stage=true,
        second_steps=steps,
        through_check=true,
      )
    catch {
      LocalConstructionFailure::Units(
        UnitBuildFailure::UnsupportedStaticPath(_)
      ) => assert_false(source_error)
      LocalConstructionFailure::Source(_) => assert_true(source_error)
      e => raise e
    } noraise {
      _ => fail("unsupported check path returned success")
    }
  }
}
