///|
test "selected normalization supplier reuses each original kind proof" {
  let (created, _, _) = original_effect_materials_fixture(normalized=true)
  let original_create = issue_prepared_client_effect_normalization(created).unwrap()
  let selected_create = issue_prepared_client_effect_selected_normalization(
    created,
  ).unwrap()
  assert_true(physical_equal(original_create, selected_create))
  assert_true(selected_create.inventory is MappedCreate(_))
  assert_eq(
    client_effect_normalization_catalog_cid(selected_create),
    client_effect_completion_free_catalog_cid(),
  )
  assert_true(
    issue_prepared_client_effect_local_update_normalization(created)
    is Err(Inventory(ProfileNotInstalled)),
  )
  let updated = local_update_source_normalization_fixture(true)
  let selected_update = issue_prepared_client_effect_selected_normalization(
    updated,
  ).unwrap()
  let original_update = issue_prepared_client_effect_local_update_normalization(
    updated,
  ).unwrap()
  assert_true(physical_equal(selected_update, original_update))
  assert_true(
    physical_equal(
      selected_update,
      issue_prepared_client_effect_selected_normalization(updated).unwrap(),
    ),
  )
  assert_true(selected_update.inventory is LocalUpdate(_))
  assert_eq(
    client_effect_normalization_catalog_cid(selected_update),
    client_effect_local_update_completion_free_catalog_cid(),
  )
  assert_true(
    issue_prepared_client_effect_normalization(updated)
    is Err(Inventory(ProfileNotInstalled)),
  )
}

///|
test "selected normalization supplier refuses a real implicit Source completion" {
  let completed = local_update_source_normalization_fixture(false)
  assert_true(
    issue_prepared_client_effect_selected_normalization(completed)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(completed.normalization is None)
}

///|
test "selected normalization supplier refuses copied and substituted original proof custody" {
  let original = local_update_source_normalization_fixture(true)
  let proof = issue_prepared_client_effect_selected_normalization(original).unwrap()
  let copied = { ..original, }
  assert_true(
    issue_prepared_client_effect_selected_normalization(copied)
    is Err(ForeignPreparation),
  )
  let (created, _, _) = original_effect_materials_fixture(normalized=true)
  let create_proof = issue_prepared_client_effect_normalization(created).unwrap()
  let substituted = local_update_source_normalization_fixture(true)
  substituted.normalization = Some(create_proof)
  assert_true(
    issue_prepared_client_effect_selected_normalization(substituted)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(physical_equal(substituted.normalization.unwrap(), create_proof))
  assert_true(physical_equal(original.normalization.unwrap(), proof))
  assert_true(
    physical_equal(
      issue_prepared_client_effect_selected_normalization(original).unwrap(),
      proof,
    ),
  )
}
