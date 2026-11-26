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

///|
test "revisited Source originals reuse one completion entry under the same work limit" {
  let owner = checked_direct_program_fixture()
  let original = owner.units[0].source_execution[0]
  let inventory = local_program_common_normalization_inventory(owner, 10000).unwrap()
  let work = local_common_normalization_inventory_work(inventory)
  let visits = 24
  let units = owner.units.copy()
  // This reuses the checked owner's actual Source execution, as a shared
  // producer does when several consumers visit the same retained occurrence.
  units[0] = { ..units[0], source_execution: Array::make(visits, original), }
  let shared = { ..owner, units, }
  // Each later visit needs at most the execution entry and one nominal
  // comparison. The old reconstruction cannot fit this independent bound.
  let upper = work + 2 * (visits - 1)
  let reused = local_program_common_normalization_inventory(shared, upper).unwrap()
  let exact = local_common_normalization_inventory_work(reused)
  assert_true(exact <= upper)
  assert_true(
    local_program_common_normalization_inventory(shared, exact) is Ok(_),
  )
  assert_eq(local_common_normalization_entry_count(reused), 1)
  assert_eq(
    local_common_normalization_entry_at(reused, 0),
    local_common_normalization_entry_at(inventory, 0),
  )
  assert_true(
    local_program_common_normalization_inventory(shared, exact - 1)
    is Err(BudgetExceeded),
  )
  let other = checked_direct_program_fixture().units[0].source_execution[0]
  let foreign = {
    ..original,
    subject: { ..original.subject, source: other.subject.source, },
  }
  let units = owner.units.copy()
  units[0] = { ..units[0], source_execution: [original, foreign], }
  let substituted = { ..owner, units, }
  assert_true(
    local_program_common_normalization_inventory(substituted, 10000)
    is Err(ForeignOriginal),
  )
}
