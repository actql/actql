///|
test "kintone delete Mapping refuses partial before fields after declaration metadata escapes" {
  let catalog = delete_mapping_form()
  let original = delete_original_declaration(catalog)
  let owned = prepare_record_delete_mapping(
    original,
    "inquiries",
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let request = delete_original_request(catalog, fields=[])
  assert_true(!record_delete_mapping_matches_request(owned, request))
  record_declaration(original).views[0].fields.clear()
  assert_true(!record_delete_mapping_matches_request(owned, request))
  assert_true(
    record_delete_mapping_matches_request(
      owned,
      delete_original_request(catalog),
    ),
  )
}

///|
test "kintone delete Mapping takes before fields from its immutable original body" {
  let catalog = delete_mapping_form()
  let original = delete_original_declaration(catalog)
  record_declaration(original).views[0].fields.clear()
  let owned = prepare_record_delete_mapping(
    original,
    "inquiries",
    "required",
    delete_declaration_limits(),
  ).unwrap()
  assert_true(
    !record_delete_mapping_matches_request(
      owned,
      delete_original_request(catalog, fields=[]),
    ),
  )
  assert_true(
    record_delete_mapping_matches_request(
      owned,
      delete_original_request(catalog),
    ),
  )
}
