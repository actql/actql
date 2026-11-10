///|
test "kintone UPDATE Mapping refuses copied DATA with the same retained declaration" {
  let catalog = update_mapping_form()
  let original = update_mapping_declaration(catalog)
  let mapping = prepare_record_update_mapping(
    original,
    "inquiries",
    update_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let copied : RecordUpdateMapping = { ..mapping, }
  let request = update_mapping_request(catalog)
  assert_true(record_update_mapping_matches_declaration(mapping, original))
  assert_true(record_update_mapping_matches_request(mapping, request))
  assert_false(record_update_mapping_matches_declaration(copied, original))
  assert_false(record_update_mapping_matches_request(copied, request))
}
