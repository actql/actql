///|
test "installed identity row codec binds only the same original response declaration" {
  // resource-case-id: installed_row_profile_original
  let original = declared_file_profile_test_declaration()
  let view = original.views
    .iter()
    .find_first(view => view.resource == "contents")
    .unwrap()
  let quote = installed_row_read_profile_construction_inventory(original).unwrap()
  assert_true(@execution.preparation_representation_cost(quote).unwrap() > 0L)
  let bound = bind_installed_row_read_profile(original, view.source_ref).unwrap()
  assert_true(physical_equal(bound.views[0], original.views[0]))
  assert_eq(bound.catalog, original.catalog)
  let profile = row_declaration_file_read_profile(bound, view.source_ref).unwrap()
  assert_eq(
    @publication.publication_contract_name(profile),
    "installed_row_source_read",
  )
  let (request, response) = row_declaration_keyed_read_schema_identities(
    original,
    view.source_ref,
  ).unwrap()
  assert_eq(
    @publication.file_read_profile_contract_bindings(profile),
    Some((view.view_cid, request, response)),
  )
  assert_true(
    row_declaration_file_read_profile(original, view.source_ref) is None,
  )
  assert_true(
    bind_installed_row_read_profile(bound, view.source_ref)
    is Err(InvalidSpecification),
  )
  assert_true(
    bind_installed_row_read_profile(original, "foreign")
    is Err(InvalidSpecification),
  )
  assert_true(
    row_declaration_file_read_profile_matches(
      bound,
      view.source_ref,
      original,
      "records",
      declared_file_profile_test_fields(),
    ) ==
    false,
  )
  assert_true(
    row_declaration_file_read_physical_source(original, profile) is None,
  )
  let foreign = bind_installed_row_read_profile(original, view.source_ref).unwrap()
  let foreign_profile = row_declaration_file_read_profile(
    foreign,
    view.source_ref,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(foreign_profile),
    @publication.publication_contract_identity(profile),
  )
  assert_true(
    row_declaration_file_read_physical_source(bound, foreign_profile) is None,
  )
  let selected = row_declaration_file_read_physical_source(bound, profile).unwrap()
  assert_eq(selected.0, view.view_cid)
  assert_eq(
    selected.1,
    original.view_bodies[original.views
    .search_by(item => physical_equal(item, view))
    .unwrap()],
  )
}

///|
test "installed row descriptor wire cannot grant a physical declared-file projection" {
  // resource-case-id: installed_row_profile_wrong_kind
  let original = declared_file_profile_test_declaration()
  let view = original.views
    .iter()
    .find_first(view => view.resource == "contents")
    .unwrap()
  let bound = bind_installed_row_read_profile(original, view.source_ref).unwrap()
  let profile = row_declaration_file_read_profile(bound, view.source_ref).unwrap()
  let wire = @publication.publication_contract_json(profile)
  assert_true(
    @publication.admit_file_read_profile_contract(wire, 2048, 32, 2) is Ok(_),
  )
  assert_true(
    @publication.admit_file_read_profile_contract(
      wire.replace(old="typed_json_row_array", new="utf8"),
      2048,
      32,
      2,
    )
    is Err(_),
  )
  assert_true(
    @publication.admit_publication_contract(
      "declared_file_content_read", wire, 2048, 32, 2,
    )
    is Err(_),
  )
}
