///|
/// An independent Catalog response fixture. These are admitted physical
/// requests, not a Native execution or a substitute approval/dispatch claim.
fn resident_write_method_request(
  operation : @catalog.WriteOperation,
) -> @catalog.SingleWriteRequest raise {
  let cid = "sha256:" + "a".repeat(64)
  let binding : @catalog.CatalogObservationBinding = {
    namespace_id: "method-test",
    principal: "principal",
    environment: "test",
    connection_revision: "connection/1",
    org_id: "00D000000000001EAA",
    site_key: "site",
    site_generation: 1,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://example.invalid",
    run_invocation_cid: cid,
    dispatch_request_cid: cid,
    sync_occurrence: "sync",
  }
  let listing = @catalog.project_resource_listing(
    @utf8.encode(
      "{\"sobjects\":[{\"name\":\"ActQL_Test_Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true}]}",
    ),
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 1,
      max_selected: 1,
      max_name_units: 100,
    },
  ).unwrap()
  let description = @utf8.encode(
    "{\"name\":\"ActQL_Test_Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"createable\":false,\"updateable\":false},{\"name\":\"Count__c\",\"type\":\"int\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}]}",
  )
  let sync = @catalog.begin_catalog_sync(listing)
  @catalog.catalog_sync_describe(sync, "ActQL_Test_Record__c", description, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 2,
    max_name_units: 100,
  }).unwrap()
  @catalog.finish_catalog_sync(sync).unwrap()
  let observed = @catalog.prepare_catalog_observation(
    sync,
    binding,
    cid,
    [Some(cid)],
    [Some(@sha.hex(description))],
    8192,
  ).unwrap()
  let projection = @catalog.prepare_write_projection(
    observed,
    binding,
    "ActQL_Test_Record__c",
    operation,
    ["Count__c"],
    1,
  ).unwrap()
  @catalog.recover_single_write_request(
    projection,
    "{\"Count__c\":3}",
    if operation is @catalog.WriteCreate {
      "null"
    } else {
      "\"001000000000001AAA\""
    },
    "v66.0",
    { max_bytes: 4096, max_nodes: 100, max_depth: 10, },
    { max_path_bytes: 1024, max_target_bytes: 128, max_body_bytes: 4096, },
  ).unwrap()
}

///|
test "mapped create uses POST without adopting an observed update guard" {
  let request = resident_write_method_request(@catalog.WriteCreate)
  assert_eq(
    @catalog.single_write_request_grant_operation(request),
    "salesforce:record:create",
  )
  assert_true(
    native_resident_effect_row_method(request, None, None) is Ok(@http.Post),
  )
  let version = Some("sha256:" + "b".repeat(64))
  assert_true(
    native_resident_effect_row_method(request, version, None)
    is Err(ForeignRequest),
  )
  assert_true(
    native_resident_effect_row_method(request, None, version)
    is Err(ForeignRequest),
  )
  assert_true(
    native_resident_effect_row_method(request, version, version)
    is Err(ForeignRequest),
  )
}

///|
test "update requires its observed guard and never selects create POST" {
  let request = resident_write_method_request(@catalog.WriteUpdateById)
  let version = Some("sha256:" + "b".repeat(64))
  assert_eq(
    @catalog.single_write_request_grant_operation(request),
    "salesforce:record:update",
  )
  assert_true(
    native_resident_effect_row_method(request, version, version)
    is Ok(@http.Patch),
  )
  assert_true(
    native_resident_effect_row_method(request, None, None)
    is Err(ForeignRequest),
  )
  assert_true(
    native_resident_effect_row_method(request, version, None)
    is Err(ForeignRequest),
  )
  assert_true(
    native_resident_effect_row_method(
      request,
      version,
      Some("sha256:" + "c".repeat(64)),
    )
    is Err(ForeignRequest),
  )
}
