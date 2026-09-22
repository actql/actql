///|
test "formal coverage reads retain Unit ownership and Result import projection" {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    through_check=true,
    second_stage=true,
    checked_results=checked,
  )
  let p = checked[0]
  let first = unit_completeness_requirement(p, 0, Step(0)).unwrap()
  let second = unit_completeness_requirement(p, 1, Input(0)).unwrap()
  assert_eq(first.unit_definition_cid, unit_definition_cid(p, 0).unwrap())
  assert_eq(second.unit_definition_cid, unit_definition_cid(p, 1).unwrap())
  assert_true(first.unit_definition_cid != second.unit_definition_cid)
  let imported = @pipeline.completeness_dependency_at(second.requirement, 0).unwrap()
  assert_eq(imported.role, ImportedProducer)
  assert_true(imported.projection is Some(_))
  assert_true(
    @pipeline.completeness_belongs_to(
      imported.requirement,
      unit_pipeline(p, 0).unwrap(),
      Step(0),
    ),
  )
  assert_true(
    !@pipeline.completeness_belongs_to(
      imported.requirement,
      unit_pipeline(p, 1).unwrap(),
      Step(0),
    ),
  )
  assert_true(unit_completeness_requirement(p, 2, Input(0)) is None)
  assert_true(unit_completeness_requirement(p, 0, Step(-1)) is None)
  let local_binding = unit_input_completeness(p, 0, 0).unwrap()
  assert_true(input_completeness_is_supplied(local_binding))
  guard local_binding.binding is Local(subject) else {
    fail("local coverage owner")
  }
  assert_true(physical_equal(subject.pipeline, unit_pipeline(p, 0).unwrap()))
  assert_eq(subject.target, Input(0))
  let imported_binding = unit_input_completeness(p, 1, 0).unwrap()
  assert_false(input_completeness_is_supplied(imported_binding))
  guard imported_binding.binding is Imported(interface, producer) else {
    fail("import coverage owner")
  }
  assert_eq(interface.producer_unit_definition_cid, first.unit_definition_cid)
  assert_true(
    physical_equal(
      @pipeline.producer_pipeline(producer),
      unit_pipeline(p, 0).unwrap(),
    ),
  )
}

///|
test "coverage binding includes unused sources and uses pipeline input names" {
  let p = checked_direct_program_fixture(unused_source=true)
  let pipeline = unit_pipeline(p, 0).unwrap()
  assert_eq(@pipeline.input_count(pipeline), 2)
  for index in 0..<@pipeline.input_count(pipeline) {
    let binding = unit_input_completeness(p, 0, index).unwrap()
    assert_false(input_completeness_is_supplied(binding))
    guard binding.binding is Source(execution) else {
      fail("source coverage owner")
    }
    assert_true(execution.kind is CarrierResponse)
    assert_true(execution.phase is BeforeSourceOutputUse)
    assert_true(execution.failure is RejectSourceOutput)
    assert_eq(
      @sourceviews.declaration(execution.subject.source).input_name,
      @pipeline.input_at(pipeline, index).unwrap().0,
    )
    assert_true(physical_equal(execution.subject.owner, p.identity))
    assert_true(
      @pipeline.completeness_belongs_to(
        binding.unit.requirement,
        pipeline,
        Input(index),
      ),
    )
  }
  let budget : IdentityBudget = {
    work: 1000000,
    bytes: 1000000,
    nodes: 1000,
    depth: 100,
  }
  let _ = prepare_input_completeness(p.units, budget)
  let used = 1000000 - budget.work
  let foreign = checked_direct_program_fixture(unused_source=true)
  let swapped : Array[BuiltUnit] = [
    { ..p.units[0], source_execution: foreign.units[0].source_execution, },
  ]
  let rejected = try {
    let _ = prepare_input_completeness(swapped, { ..budget, work: 1000000, })
    false
  } catch {
    UnitBuildFailure::ForeignOwner => true
    _ => false
  }
  assert_true(rejected)
  let exact : IdentityBudget = { ..budget, work: used, }
  assert_eq(prepare_input_completeness(p.units, exact).length(), 1)
  let _ = prepare_input_completeness(p.units, { ..budget, work: used - 1, }) catch {
    UnitBuildFailure::BudgetExceeded => return
    _ => fail("expected cumulative completeness budget failure")
  }
  fail("partial input coverage must not escape the budget")
}
