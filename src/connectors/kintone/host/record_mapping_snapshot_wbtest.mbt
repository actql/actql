///|
test "UPDATE Mapping original before fields survive escaped declaration metadata mutation" {
  let catalog = update_mapping_form()
  let original = update_mapping_declaration(catalog)
  let owned = prepare_record_update_mapping(
    original,
    "inquiries",
    update_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  record_declaration(original).views[0].fields.clear()
  assert_false(
    record_update_mapping_matches_request(
      owned,
      update_mapping_request(catalog, fields=[]),
    ),
  )
}

///|
test "UPDATE Mapping exact writes survive escaped Mapping metadata mutation" {
  let catalog = update_mapping_form()
  let owned = prepare_record_update_mapping(
    update_mapping_declaration(catalog),
    "inquiries",
    update_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let exposed = record_update_mapping(owned)
  exposed.write_fields.clear()
  exposed.omittable.push("Tags")
  assert_false(
    record_update_mapping_matches_request(
      owned,
      update_mapping_request(catalog, write_tags=false),
    ),
  )
}
