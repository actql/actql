///|
fn local_sort_normalization_program(body : String) -> CheckedProgram raise {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      generated_rows=Some("[{\"id\":2},{\"id\":1}]"),
      producer_suffix=",{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"count\"}}}},{\"sort\":" +
        body +
        ",\"as\":\"ordered\"}",
      producer_result_from="ordered",
      extra_step_budget=2,
    ),
  )
  checked[0]
}

///|
test "actual original Sort completion has its own inventory and cannot become completion-free" {
  let owner = local_sort_normalization_program("[{\"value\":\"asc\"}]")
  let pipeline = owner.units[0].pipeline
  let step = 3
  guard @pipeline.step_at(pipeline, step).unwrap().operation
    is @pipeline.Unary(operation) else {
    fail("original Sort expected")
  }
  assert_true(
    local_program_completion_free_inventory(owner) is Err(CompletionObserved),
  )
  let inventory = local_program_sort_normalization_inventory(owner)
    .unwrap()
    .unwrap()
  assert_true(local_sort_normalization_inventory_matches(inventory, owner))
  assert_eq(local_sort_normalization_entry_count(inventory), 1)
  let entry = inventory.entries[0]
  assert_true(physical_equal(entry.operation, operation))
  guard entry.order is Some(original_order) else {
    fail("actual Sort completion must retain its original order witness")
  }
  assert_true(
    physical_equal(@pipeline.sort_order_pipeline(original_order), pipeline),
  )
  assert_eq(@pipeline.sort_order_step(original_order), step)
  let (path, authored, canonical) = local_sort_normalization_entry_at(
    inventory, 0,
  ).unwrap()
  assert_eq(path, "$.stages[0].steps[3].sort")
  assert_eq(authored, "[{\"value\":\"asc\"}]")
  assert_eq(
    canonical, "[{\"dir\":\"asc\",\"field\":\"value\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"last\"}]",
  )
  let foreign = local_sort_normalization_program("[{\"value\":\"asc\"}]")
  assert_false(local_sort_normalization_inventory_matches(inventory, foreign))
  assert_true(local_sort_normalization_entry_at(inventory, -1) is None)
  assert_true(local_sort_normalization_entry_at(inventory, 1) is None)
}

///|
test "zero-append and empty original Sort keep the strict prior inventory" {
  for text in ["[{\"id\":\"asc\"}]", "[]"] {
    let owner = local_sort_normalization_program(text)
    assert_true(local_program_sort_normalization_inventory(owner) is Ok(None))
    assert_true(local_program_completion_free_inventory(owner) is Ok(_))
  }
}

///|
test "Sort completion emission keeps exact work and exposes no partial entry on refusal" {
  let owner = local_sort_normalization_program("[{\"value\":\"asc\"}]")
  let pipeline = owner.units[0].pipeline
  guard @pipeline.step_at(pipeline, 3).unwrap().operation
    is @pipeline.Unary(operation) else {
    fail("original Sort expected")
  }
  let entries : Array[LocalSortNormalizationEntry] = []
  let left = audit_local_sort(operation, pipeline, 3, 10000, Some(entries)).unwrap()
  let exact = 10000 - left
  assert_true(exact > 4)
  assert_eq(entries.length(), 1)
  let exact_entries : Array[LocalSortNormalizationEntry] = []
  assert_true(
    audit_local_sort(operation, pipeline, 3, exact, Some(exact_entries))
    is Ok(0),
  )
  assert_eq(exact_entries.length(), 1)
  let refused_entries : Array[LocalSortNormalizationEntry] = []
  assert_true(
    audit_local_sort(operation, pipeline, 3, exact - 1, Some(refused_entries))
    is Err(ProfileNotInstalled),
  )
  assert_eq(refused_entries.length(), 0)
  assert_true(
    audit_local_completion_free_sort(operation, pipeline, 3, 10000)
    is Err(CompletionObserved),
  )
}
