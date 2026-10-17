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
  ignore(exposed.write_fields.pop())
  exposed.omittable.push("Tags")
  assert_false(
    record_update_mapping_matches_request(
      owned,
      update_mapping_request(catalog, write_tags=false),
    ),
  )
}

///|
test "UPDATE Mapping schema names come from the checked body before any escaped view metadata" {
  let catalog = update_mapping_form()
  let original = update_mapping_declaration(catalog)
  record_declaration(original).views[0].fields.clear()
  let owned = prepare_record_update_mapping(
    original,
    "inquiries",
    update_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  assert_false(
    record_update_mapping_matches_request(
      owned,
      update_mapping_request(catalog, fields=[]),
    ),
  )
  assert_true(
    record_update_mapping_matches_request(
      owned,
      update_mapping_request(catalog),
    ),
  )
}
