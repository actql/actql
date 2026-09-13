///|
test "coverage requirements retain selection and both membership operands" {
  for
    operation in [
      "\"append\":{\"with\":\"right\"}", "\"except\":{\"with\":\"right\",\"duplicates\":\"all\"}",
      "\"intersect\":{\"with\":\"right\",\"duplicates\":\"all\"}", "\"join\":{\"with\":\"right\",\"kind\":\"anti\",\"on\":\"id\"}",
      "\"join\":{\"with\":\"right\",\"kind\":\"semi\",\"on\":\"id\"}",
    ] {
    let source = cursor("[{\"from\":\"left\",\"take\":1},{" + operation + "}]")
    let p = @pipeline_typing.check(
      source,
      [("left", schema()), ("right", schema())],
      None,
      None,
      limits(),
    ).unwrap()
    let result = @pipeline_typing.completeness_requirement(p, Step(1)).unwrap()
    assert_eq(@pipeline_typing.completeness_scope(result), OperationResult)
    assert_eq(@pipeline_typing.completeness_dependency_count(result), 2)
    for
      (index, role, target) in [
        (0, @pipeline_typing.Left, @pipeline_typing.Step(0)),
        (1, @pipeline_typing.Right, @pipeline_typing.Input(1)),
      ] {
      let dep = @pipeline_typing.completeness_dependency_at(result, index).unwrap()
      assert_eq(dep.role, Operand(role))
      assert_true(
        @pipeline_typing.completeness_belongs_to(dep.requirement, p, target),
      )
    }
    let bounded = @pipeline_typing.completeness_dependency_at(result, 0).unwrap().requirement
    assert_eq(@pipeline_typing.completeness_scope(bounded), BoundedQuery)
    let input = @pipeline_typing.completeness_dependency_at(bounded, 0).unwrap().requirement
    assert_eq(@pipeline_typing.completeness_scope(input), InputExtent)
    assert_true(@pipeline_typing.completeness_belongs_to(input, p, Input(0)))
    assert_eq(@pipeline_typing.completeness_dependency_count(input), 0)
    assert_true(@pipeline_typing.completeness_dependency_at(result, -1) is None)
    assert_true(@pipeline_typing.completeness_dependency_at(result, 2) is None)
    assert_true(@pipeline_typing.completeness_requirement(p, Step(2)) is None)
    let other = @pipeline_typing.check(
      source,
      [("left", schema()), ("right", schema())],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(
      !@pipeline_typing.completeness_belongs_to(result, other, Step(1)),
    )
    assert_true(!@pipeline_typing.completeness_belongs_to(result, p, Step(0)))
  }
}

///|
test "coverage imports retain producer and projection without flattening input extents" {
  let p = @pipeline_typing.check(
    cursor(
      "[{\"filter\":\"amount > 0\"},{\"derive\":{\"saved\":\"id\"}},{\"select\":[\"saved\"]}]",
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let producer = @pipeline_typing.produced_input(p, Step(2)).unwrap()
  let q = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [("rows", @pipeline_typing.ProducedInput(producer))],
    None,
    None,
    limits(),
  ).unwrap()
  let imported = @pipeline_typing.completeness_requirement(q, Input(0)).unwrap()
  assert_eq(@pipeline_typing.completeness_scope(imported), InputExtent)
  assert_eq(@pipeline_typing.completeness_dependency_count(imported), 1)
  let edge = @pipeline_typing.completeness_dependency_at(imported, 0).unwrap()
  assert_eq(edge.role, ImportedProducer)
  assert_true(
    @pipeline_typing.completeness_belongs_to(edge.requirement, p, Step(2)),
  )
  let mut at = edge.requirement
  for i = 2; i >= 0; i = i - 1 {
    assert_true(@pipeline_typing.completeness_belongs_to(at, p, Step(i)))
    assert_eq(@pipeline_typing.completeness_scope(at), OperationResult)
    assert_eq(@pipeline_typing.completeness_dependency_count(at), 1)
    at = @pipeline_typing.completeness_dependency_at(at, 0).unwrap().requirement
  }
  assert_true(@pipeline_typing.completeness_belongs_to(at, p, Input(0)))
  assert_eq(@pipeline_typing.completeness_scope(at), InputExtent)
}
