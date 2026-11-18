///|
test "common Source completion retains its actual resolver and full requirements" {
  let owner = checked_direct_program_fixture()
  let inventory = local_program_common_normalization_inventory(owner, 100000).unwrap()
  assert_true(local_common_normalization_uses_source_completion(inventory))
  assert_eq(local_common_normalization_entry_count(inventory), 1)
  assert_eq(
    local_common_normalization_entry_at(inventory, 0),
    Some(
      (
        "$.stages[0].inputs[\"remote\"].view", "actql.source.sole-view-completion",
        "null", "v",
      ),
    ),
  )
  assert_true(
    physical_equal(
      local_common_normalization_inventory_requirements(inventory),
      owner.requirements,
    ),
  )
  assert_true(local_common_normalization_inventory_matches(inventory, owner))
  assert_false(
    local_common_normalization_inventory_matches(inventory, { ..owner, }),
  )
  assert_false(
    local_common_normalization_inventory_matches(
      inventory,
      checked_direct_program_fixture(),
    ),
  )
  // This successor does not claim the old completion-free profile is valid.
  assert_true(
    local_program_sort_normalization_inventory(owner) is Err(CompletionObserved),
  )
}

///|
test "Source completion JSONPath retains an original dotted input name as one member" {
  let owner = checked_direct_program_fixture(input_name="remote.part")
  let inventory = local_program_common_normalization_inventory(owner, 100000).unwrap()
  assert_eq(
    local_common_normalization_entry_at(inventory, 0),
    Some(
      (
        "$.stages[0].inputs[\"remote.part\"].view", "actql.source.sole-view-completion",
        "null", "v",
      ),
    ),
  )
}

///|
test "explicit Source stays completion-free and the Source audit work is exact" {
  let explicit = checked_direct_program_fixture(explicit_view=true)
  let inventory = local_program_common_normalization_inventory(explicit, 100000).unwrap()
  assert_false(local_common_normalization_uses_source_completion(inventory))
  assert_eq(local_common_normalization_entry_count(inventory), 0)
  let owner = checked_direct_program_fixture()
  let inventory = local_program_common_normalization_inventory(owner, 100000).unwrap()
  let work = local_common_normalization_inventory_work(inventory)
  assert_true(
    local_program_common_normalization_inventory(owner, work) is Ok(_),
  )
  assert_true(
    local_program_common_normalization_inventory(owner, work - 1)
    is Err(BudgetExceeded),
  )
  let (extent, text, _) = local_common_normalization_retained_extent(inventory).unwrap()
  assert_eq(text, "$.stages[0].inputs[\"remote\"].view".length().to_int64())
  assert_true(extent.record_headers > 0L)
}
