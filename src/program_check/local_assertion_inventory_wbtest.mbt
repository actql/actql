///|
fn local_assertion_inventory_program(body : String) -> CheckedProgram raise {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      generated_rows=Some("[{\"id\":2},{\"id\":1}]"),
      producer_suffix=",{\"assert_rows\":" + body + ",\"as\":\"asserted\"}",
      producer_result_from="asserted",
      extra_step_budget=1,
    ),
  )
  checked[0]
}

///|
test "assertion inventory retains original operation schema obligations and owner" {
  for
    body in ["{\"where\":\"value > 0\"}", "{\"unique_by\":[\"value\",\"id\"]}"] {
    let owner = local_assertion_inventory_program(body)
    let inventory = local_program_completion_free_inventory(owner).unwrap()
    assert_true(local_completion_free_inventory_uses_assertions(inventory))
    assert_true(local_completion_free_inventory_matches(inventory, owner))
    assert_true(
      local_program_sort_normalization_inventory(owner).unwrap() is None,
    )
    let pipeline = owner.units[0].pipeline
    guard @pipeline.step_at(pipeline, 2).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("original assertion expected")
    }
    let foreign = local_assertion_inventory_program(body)
    guard @pipeline.step_at(foreign.units[0].pipeline, 2).unwrap().operation
      is @pipeline.Unary(other) else {
      fail("foreign assertion expected")
    }
    assert_false(local_completion_free_inventory_matches(inventory, foreign))
    assert_true(
      audit_local_completion_free_assertion(operation, pipeline, 2, 10000)
      is Some(_),
    )
    assert_true(
      audit_local_completion_free_assertion(other, pipeline, 2, 10000) is None,
    )
    assert_true(
      audit_local_completion_free_assertion(operation, pipeline, 1, 10000)
      is None,
    )
  }
}

///|
test "assertion inventory charges exact bounded schema predicate and key visits" {
  for
    body in ["{\"where\":\"value > 0\"}", "{\"unique_by\":[\"value\",\"id\"]}"] {
    let owner = local_assertion_inventory_program(body)
    let pipeline = owner.units[0].pipeline
    guard @pipeline.step_at(pipeline, 2).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("original assertion expected")
    }
    let left = audit_local_completion_free_assertion(
      operation, pipeline, 2, 10000,
    ).unwrap()
    let exact = 10000 - left
    assert_true(exact > 0)
    assert_eq(
      audit_local_completion_free_assertion(operation, pipeline, 2, exact),
      Some(0),
    )
    assert_true(
      audit_local_completion_free_assertion(operation, pipeline, 2, exact - 1)
      is None,
    )
    assert_true(
      audit_local_completion_free_assertion(operation, pipeline, 2, 0) is None,
    )
  }
}
