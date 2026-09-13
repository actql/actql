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
}
