///|
fn analytic_numeric_import_fixture(
  supplied : @decode.Cursor?,
) -> CheckedProgram raise LocalConstructionFailure {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    second_stage=true,
    through_check=true,
    numeric_profile=Some(numeric_profile_fixture()),
    analytic_limit=Some(1000),
    checked_results=checked,
    parameters=true,
    supplied~,
    producer_suffix=",{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"total\":{\"fn\":\"sum\",\"field\":\"value\"}}}},{\"select\":[\"id\",{\"value\":\"total\"}],\"as\":\"aggregated\"}",
    producer_result_from="aggregated",
    second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"avg\",\"field\":\"value\"}}},\"as\":\"selected\"}]",
    second_result_from="selected",
    extra_step_budget=4,
  )
  checked[0]
}

///|
test "imported analytic numeric aggregate retains its producer Unit and capture demand" {
  let program = analytic_numeric_import_fixture(None)
  assert_eq(unit_analytic_numeric_slot_count(program, 0), Some(1))
  assert_eq(unit_analytic_numeric_slot_count(program, 1), Some(0))
  let slot = unit_analytic_numeric_slot_at(program, 0, 0).unwrap()
  assert_eq(analytic_numeric_slot_name(slot), "total")
  assert_eq(analytic_numeric_slot_reduction(slot), Some(@numeric.Sum))
  assert_eq(unit_group_numeric_slot_count(program, 0), Some(0))
  assert_eq(unit_group_numeric_slot_count(program, 1), Some(1))
  let expected = "{\"output_name\":\"total\",\"reduction_profile_cid\":\"" +
    @numeric.cid(analytic_numeric_slot_demand(slot).profile) +
    "\",\"source_ordinal\":1,\"unit_definition_cid\":\"" +
    program.units[0].definition_cid +
    "\",\"version\":\"actql-analytic-numeric-slot/0.1\"}"
  assert_eq(
    analytic_numeric_slot_cid(slot),
    "sha256:" + @sha.text_hex(expected).unwrap(),
  )
  let writer = @encode.writer(10000, 1000, 100)
  emit_analytic_numeric_slot(slot, writer)
  assert_eq(@encode.finish(writer), expected)
  for stage in 0..<2 {
    let mut has_analytic = false
    let mut has_group = false
    for i in 0..<unit_contract_count(program, stage).unwrap() {
      let (cid, _) = unit_contract_at(program, stage, i).unwrap()
      if cid ==
        "sha256:6d88bdc63c0a7eb77ee1dc976003fcec1ace74ca46ce61af5a956d2e89b30a43" {
        has_analytic = true
      }
      if cid ==
        "sha256:3bbd17b81b40403cea2b43db3324a9c2b2185bc8c86a994d58f009e317b1a73d" {
        has_group = true
      }
    }
    assert_eq(has_analytic, stage == 0)
    assert_eq(has_group, stage == 1)
  }
  assert_eq(analytic_numeric_slot_operation(slot).source_ordinal, 1)
  assert_eq(
    analytic_numeric_slot_operation(slot).unit_definition_cid,
    program.units[0].definition_cid,
  )
  let closure = @context.stage_requirement_operations(requirements(program))
  let mut captures = 0
  let mut imported = 0
  for i in 0..<@context.operation_closure_count(closure) {
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(AnalyticExecution(check))) &&
      check.rule is CaptureNumericObservation(demand) else {
      assert_true(analytic_numeric_slot_for_requirement(program, i) is None)
      continue
    }
    captures += 1
    assert_true(
      physical_equal(
        analytic_numeric_slot_for_requirement(program, i).unwrap(),
        slot,
      ),
    )
    assert_true(
      physical_equal(demand.call, analytic_numeric_slot_demand(slot).call),
    )
    assert_true(physical_equal(check.site.pipeline, program.units[0].pipeline))
    if check.site.stage == 1 {
      imported += 1
    }
  }
  assert_true(captures > 0)
  assert_true(imported > 0)
  assert_true(analytic_numeric_slot_for_requirement(program, -1) is None)
  assert_true(
    analytic_numeric_slot_for_requirement(
      program,
      @context.operation_closure_count(closure),
    )
    is None,
  )
}

///|
test "analytic numeric occurrence indexing rejects foreign Unit owners atomically" {
  let program = analytic_numeric_import_fixture(None)
  for supplied in [None, Some(supplied_fixture("{\"n\":2}"))] {
    let other = analytic_numeric_import_fixture(supplied)
    let budget = IdentityBudget::{
      work: 1000000,
      bytes: 100000,
      nodes: 10000,
      depth: 20,
    }
    try
      prepare_program_analytic_numeric_slot_identities(
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
