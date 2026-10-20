///|
fn local_distinct_normalization_program(body : String) -> CheckedProgram raise {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      generated_rows=Some("[{\"id\":2},{\"id\":2},{\"id\":1}]"),
      producer_suffix=",{\"distinct\":" + body + ",\"as\":\"deduped\"}",
      producer_result_from="deduped",
      extra_step_budget=1,
    ),
  )
  checked[0]
}

///|
test "whole-row and reordered keyed DISTINCT retain only their original audited occurrence" {
  for body in ["true", "[\"value\",\"id\"]"] {
    let owner = local_distinct_normalization_program(body)
    let inventory = local_program_completion_free_inventory(owner).unwrap()
    assert_true(local_completion_free_inventory_uses_distinct(inventory))
    assert_true(local_completion_free_inventory_matches(inventory, owner))
    assert_true(
      local_program_sort_normalization_inventory(owner).unwrap() is None,
    )
    let pipeline = owner.units[0].pipeline
    guard @pipeline.step_at(pipeline, 2).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("original DISTINCT expected")
    }
    assert_true(
      audit_local_completion_free_distinct(operation, pipeline, 2, 10000)
      is Some(_),
    )
    let foreign = local_distinct_normalization_program(body)
    guard @pipeline.step_at(foreign.units[0].pipeline, 2).unwrap().operation
      is @pipeline.Unary(foreign_operation) else {
      fail("foreign original DISTINCT expected")
    }
    assert_false(local_completion_free_inventory_matches(inventory, foreign))
    assert_true(
      audit_local_completion_free_distinct(
        foreign_operation, pipeline, 2, 10000,
      )
      is None,
    )
    assert_true(
      audit_local_completion_free_distinct(operation, pipeline, 1, 10000)
      is None,
    )
  }
}

///|
test "DISTINCT metadata traversal keeps exact work refusal" {
  for body in ["true", "[\"value\",\"id\"]"] {
    let owner = local_distinct_normalization_program(body)
    let pipeline = owner.units[0].pipeline
    guard @pipeline.step_at(pipeline, 2).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("original DISTINCT expected")
    }
    let left = audit_local_completion_free_distinct(
      operation, pipeline, 2, 10000,
    ).unwrap()
    let exact = 10000 - left
    assert_true(exact > 0)
    assert_eq(
      audit_local_completion_free_distinct(operation, pipeline, 2, exact),
      Some(0),
    )
    assert_true(
      audit_local_completion_free_distinct(operation, pipeline, 2, exact - 1)
      is None,
    )
  }
}
