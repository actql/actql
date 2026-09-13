///|
fn numeric_import_fixture(
  supplied : @decode.Cursor?,
) -> CheckedProgram raise LocalConstructionFailure {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    second_stage=true,
    through_check=true,
    numeric_profile=Some(numeric_profile_fixture()),
    checked_results=checked,
    parameters=true,
    supplied~,
    producer_suffix=",{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"sum\",\"field\":\"value\"}}},\"as\":\"aggregated\"}",
    producer_result_from="aggregated",
    second_steps="[{\"select\":[\"id\",\"value\"],\"as\":\"selected\"}]",
    second_result_from="selected",
    extra_step_budget=3,
  )
  checked[0]
}

///|
test "imported numeric aggregate retains its producer Unit and capture demand" {
  let program = numeric_import_fixture(None)
  assert_eq(unit_group_numeric_slot_count(program, 0), Some(1))
  assert_eq(unit_group_numeric_slot_count(program, 1), Some(0))
  let slot = unit_group_numeric_slot_at(program, 0, 0).unwrap()
  assert_eq(group_numeric_slot_operation(slot).source_ordinal, 1)
  assert_eq(
    group_numeric_slot_operation(slot).unit_definition_cid,
    program.units[0].definition_cid,
  )
  let closure = @context.stage_requirement_operations(requirements(program))
  let mut captures = 0
  let mut imported = 0
  for i in 0..<@context.operation_closure_count(closure) {
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(GroupExecution(check))) &&
      check.rule is CaptureNumericObservation(demand) else {
      assert_true(numeric_slot_for_requirement(program, i) is None)
      continue
    }
    captures += 1
    assert_true(
      physical_equal(numeric_slot_for_requirement(program, i).unwrap(), slot),
    )
    assert_true(
      physical_equal(demand.call, group_numeric_slot_demand(slot).call),
    )
    assert_true(physical_equal(check.site.pipeline, program.units[0].pipeline))
    if check.site.stage == 1 {
      imported += 1
    }
  }
  assert_true(captures > 0)
  assert_true(imported > 0)
  assert_true(numeric_slot_for_requirement(program, -1) is None)
  assert_true(
    numeric_slot_for_requirement(
      program,
      @context.operation_closure_count(closure),
    )
    is None,
  )
}

///|
test "numeric occurrence indexing rejects foreign Unit owners atomically" {
  let program = numeric_import_fixture(None)
  for supplied in [None, Some(supplied_fixture("{\"n\":2}"))] {
    let other = numeric_import_fixture(supplied)
    let budget = IdentityBudget::{
      work: 1000000,
      bytes: 100000,
      nodes: 10000,
      depth: 20,
    }
    try
      prepare_program_numeric_slot_identities(
        other.units,
        requirements(program),
        budget,
      )
    catch {
      ForeignOwner => ()
      e => raise e
    } noraise {
      _ => fail("foreign Unit accepted")
    }
    assert_eq(
      (budget.work, budget.bytes, budget.nodes),
      (1000000, 100000, 10000),
    )
  }
}
