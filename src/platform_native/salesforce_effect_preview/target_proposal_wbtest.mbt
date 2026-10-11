///|
// Pure fixtures for the common checked-request seam. No Provider, issuer,
// opaque Work or actual capture authority is supplied by these materials.
fn target_proposal_test_mapping(
  host_adoption_cid? : String = local_target_test_cid("5"),
) -> (@catalog.ExecutionMapping, @catalog.WriteProjection) {
  let (target, _) = local_target_test_materials()
  let binding = {
    ..@catalog.local_target_read_request_binding(target),
    host_adoption_cid,
  }
  let description = b"{\"name\":\"Account\",\"queryable\":true,\"updateable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"sortable\":true},{\"name\":\"Name\",\"type\":\"string\",\"nillable\":false,\"defaultedOnCreate\":false,\"updateable\":true}]}"
  let sync = @catalog.begin_named_catalog_sync(["Account"]).unwrap()
  @catalog.catalog_sync_describe(sync, "Account", description, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  @catalog.finish_catalog_sync(sync).unwrap()
  let observation = @catalog.prepare_local_catalog_observation(
    sync,
    binding,
    "",
    [Some(local_target_test_cid("7"))],
    [Some("3dbc19793840e93f26d2da63a0333e72af8f1c6d9f5f79548c71f614fbb2ff9e")],
    8192,
  ).unwrap()
  let limits : @catalog.DeclarationLimits = {
    max_bytes: 200000,
    max_nodes: 20000,
    max_depth: 32,
  }
  let declaration = @catalog.generate_local_static_declaration(
    observation,
    binding,
    @catalog.salesforce_implementation("salesforce/0.1").unwrap(),
    "crm-local",
    ["Account"],
    limits,
  ).unwrap()
  let mapping = @catalog.prepare_execution_mapping(
    declaration,
    "Account",
    @catalog.UpdateById(["Name"]),
    limits,
  ).unwrap()
  let projection = @catalog.prepare_local_write_projection(
    observation,
    binding,
    "Account",
    @catalog.WriteUpdateById,
    ["Name"],
    1,
  ).unwrap()
  (mapping, projection)
}

///|
test "Target proposal request preserves original Unicode and line endings" {
  let (mapping, projection) = target_proposal_test_mapping()
  let request = native_effect_target_request_from_proposal(
    mapping,
    projection,
    "\"001000000000001\"",
    "{\"state\":\"present\",\"value\":{\"Name\":\"e\\u0301/é\\r/\\n/\\r\\n\"}}",
    "v66.0",
    { max_bytes: 1024, max_nodes: 100, max_depth: 10, },
    { max_path_bytes: 1024, max_target_bytes: 128, max_body_bytes: 1024, },
  ).unwrap()
  assert_eq(
    @catalog.single_write_request_body(request),
    "{\"Name\":\"e\u{0301}/é\\r/\\n/\\r\\n\"}",
  )
  assert_eq(
    @catalog.single_write_request_path(request),
    "/services/data/v66.0/sobjects/Account/001000000000001",
  )
}

///|
test "Target proposal request refuses absent null malformed or extra changes" {
  let (mapping, projection) = target_proposal_test_mapping()
  for
    changes in [
      "{\"state\":\"missing\"}", "{\"state\":\"present\",\"value\":null}", "{\"state\":\"present\",\"value\":{\"Name\":null}}",
      "{\"state\":\"present\",\"value\":{\"Foreign\":\"x\"}}", "{\"state\":\"present\",\"value\":{\"Name\":\"x\"},\"extra\":true}",
      "{",
    ] {
    assert_true(
      native_effect_target_request_from_proposal(
        mapping,
        projection,
        "\"001000000000001\"",
        changes,
        "v66.0",
        { max_bytes: 1024, max_nodes: 100, max_depth: 10, },
        { max_path_bytes: 1024, max_target_bytes: 128, max_body_bytes: 1024, },
      )
      is Err(_),
    )
  }
}

///|
test "Target proposal request refuses foreign installation target and finite budget" {
  let (mapping, projection) = target_proposal_test_mapping()
  let (_, foreign) = target_proposal_test_mapping(
    host_adoption_cid=local_target_test_cid("9"),
  )
  assert_true(
    native_effect_target_request_from_proposal(
      mapping,
      foreign,
      "\"001000000000001\"",
      "{\"state\":\"present\",\"value\":{\"Name\":\"x\"}}",
      "v66.0",
      { max_bytes: 1024, max_nodes: 100, max_depth: 10, },
      { max_path_bytes: 1024, max_target_bytes: 128, max_body_bytes: 1024, },
    )
    is Err(Mapping(@catalog.ForeignDeclaration)),
  )
  for
    (selector, max_bytes) in [("\"foreign\"", 1024), ("\"001000000000001\"", 1)] {
    assert_true(
      native_effect_target_request_from_proposal(
        mapping,
        projection,
        selector,
        "{\"state\":\"present\",\"value\":{\"Name\":\"x\"}}",
        "v66.0",
        { max_bytes, max_nodes: 100, max_depth: 10, },
        { max_path_bytes: 1024, max_target_bytes: 128, max_body_bytes: 1024, },
      )
      is Err(_),
    )
  }
}
