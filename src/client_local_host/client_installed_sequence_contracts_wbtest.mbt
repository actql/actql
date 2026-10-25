///|
test "installed sequence contracts are directly admitted independent originals" {
  let assets=@publication_host.client_local_product_assets()
  let original=prepare_installed_sequence_contracts(assets.registry,assets.values,Some(assets.fragment),assets.ordered).unwrap()
  let other=prepare_installed_sequence_contracts(assets.registry,assets.values,Some(assets.fragment),assets.ordered).unwrap()
  assert_false(physical_equal(original,other))
  assert_true(prepare_installed_sequence_contracts("{}","{}",None,None) is Err(Unsupported))
  let before=original.original.value
  let after=original.original.value
  assert_true(physical_equal(before,after))
  assert_false(client_local_sequence_selection_matches(original,assets.values+" ",Some(assets.fragment),assets.ordered))
  assert_true(client_local_sequence_selection_matches(original,assets.values,None,assets.ordered))
  assert_false(client_local_sequence_selection_matches(original,assets.values,Some(assets.fragment),Some("{}")))
}

///|
test "required sequence preparation retains exact installed nominal owner" {
  let prepared=result_envelope_fixture()
  let assets=@publication_host.client_local_product_assets()
  let original=prepare_installed_sequence_contracts(assets.registry,assets.values,Some(assets.fragment),assets.ordered).unwrap()
  let other=prepare_installed_sequence_contracts(assets.registry,assets.values,Some(assets.fragment),assets.ordered).unwrap()
  let sequence=prepare_installed_managed_source_free_with_contracts(prepared,original,assets.values,Some(assets.fragment),assets.ordered).unwrap()
  assert_true(physical_equal(sequence.installed_contracts,original))
  assert_true(installed_source_free_preparation_matches(sequence,Pure(prepared),original,assets.values,Some(assets.fragment),assets.ordered))
  assert_false(installed_source_free_preparation_matches(sequence,Pure(prepared),other,assets.values,Some(assets.fragment),assets.ordered))
  assert_true(prepare_installed_managed_source_free_with_contracts(prepared,original,assets.values+" ",Some(assets.fragment),assets.ordered) is Err(Unsupported))
}

///|
test "optional prefix capabilities are selected from the same installed bundle" {
  let assets=@publication_host.client_local_product_assets()
  let original=prepare_installed_sequence_contracts(assets.registry,assets.values,Some(assets.fragment),assets.ordered).unwrap()
  assert_true(client_local_sequence_selection_matches(original,assets.values,None,None))
  assert_false(client_local_sequence_selection_matches(original,assets.values,Some("{}"),None))
  assert_false(client_local_sequence_selection_matches(original,assets.values,None,Some("{}")))
  let prepared=result_envelope_fixture()
  assert_true(prepare_client_local_sequences_owned(Pure(prepared),original,assets.values,None,None) is Some(_))
}
