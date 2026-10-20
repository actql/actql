///|
fn local_binary_normalization_program(kind : String) -> CheckedProgram raise {
  let checked : Array[CheckedProgram] = []
  let body = if kind == "append" {
    "{\"with\":\"derived\"}"
  } else {
    "{\"with\":\"derived\",\"duplicates\":\"distinct\"}"
  }
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
      checked_results=checked,
      producer_suffix=",{\"from\":\"derived\",\"" +
        kind +
        "\":" +
        body +
        ",\"as\":\"combined\"}",
      producer_result_from="combined",
      extra_step_budget=1,
    ),
  )
  checked[0]
}

///|
test "original binary audit retains both input occurrences and refuses foreign pipelines" {
  for kind in ["append", "except", "intersect"] {
    let owner = local_binary_normalization_program(kind)
    let inventory = local_program_completion_free_inventory(owner).unwrap()
    assert_true(local_completion_free_inventory_uses_set(inventory))
    assert_true(local_completion_free_inventory_matches(inventory, owner))
    let pipeline = owner.units[0].pipeline
    let operation = @pipeline.step_at(pipeline, 2).unwrap().operation
    assert_true(
      audit_local_completion_free_binary(operation, pipeline, 2, 10000)
      is Some(_),
    )
    let foreign = local_binary_normalization_program(kind)
    let other = @pipeline.step_at(foreign.units[0].pipeline, 2).unwrap().operation
    assert_false(local_completion_free_inventory_matches(inventory, foreign))
    assert_true(
      audit_local_completion_free_binary(other, pipeline, 2, 10000) is None,
    )
    assert_true(
      audit_local_completion_free_binary(operation, pipeline, 1, 10000) is None,
    )
  }
}

///|
test "original binary alignment has an exact unchanged work refusal" {
  for kind in ["append", "except", "intersect"] {
    let owner = local_binary_normalization_program(kind)
    let pipeline = owner.units[0].pipeline
    let operation = @pipeline.step_at(pipeline, 2).unwrap().operation
    let left = audit_local_completion_free_binary(operation, pipeline, 2, 10000).unwrap()
    let exact = 10000 - left
    assert_eq(
      audit_local_completion_free_binary(operation, pipeline, 2, exact),
      Some(0),
    )
    assert_true(
      audit_local_completion_free_binary(operation, pipeline, 2, exact - 1)
      is None,
    )
  }
}
