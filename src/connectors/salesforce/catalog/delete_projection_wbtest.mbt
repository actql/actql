///|
fn delete_test_description(
  permission? : String = "true",
  identity? : String = "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}",
) -> String {
  "{\"name\":\"Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true," +
  (if permission.is_empty() { "" } else { "\"deletable\":" + permission + "," }) +
  "\"fields\":[" +
  (if identity.is_empty() { "" } else { identity + "," }) +
  "{\"name\":\"Name\",\"type\":\"string\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}]}"
}

///|
fn delete_test_observation(
  description : String,
  binding : CatalogObservationBinding,
) -> CatalogObservation {
  let bytes = @utf8.encode(description)
  let sync = begin_named_catalog_sync(["Record__c"]).unwrap()
  catalog_sync_describe(sync, "Record__c", bytes, limits()).unwrap()
  finish_catalog_sync(sync).unwrap()
  prepare_catalog_observation(
    sync,
    binding,
    "",
    [Some("sha256:" + "d".repeat(64))],
    [Some(catalog_response_sha256(bytes))],
    8192,
  ).unwrap()
}

///|
test "delete metadata requires the original positive Describe proof and native record identity" {
  let (observation, binding) = declared_observation(delete_test_description())
  let projection = prepare_delete_projection(observation, binding, "Record__c").unwrap()
  assert_eq(delete_projection_resource(projection), "Record__c")
  assert_eq(
    delete_projection_observation(projection),
    catalog_observation_identity(observation),
  )
  assert_true(delete_projection_matches_binding(projection, binding))
  recheck_delete_projection(projection, observation).unwrap()
  assert_true(
    prepare_delete_projection(observation, binding, "Other__c")
    is Err(Observation(_)),
  )
}

///|
test "delete metadata refuses missing false and malformed proof without removing independent read fields" {
  for permission in ["", "false", "null", "1", "\"true\"", "[]", "{}"] {
    let description = delete_test_description(permission~)
    let resource = project_describe(
      @utf8.encode(description),
      "Record__c",
      limits(),
    ).unwrap()
    assert_eq(resource.fields.length(), 2)
    assert_true(resource.queryable)
    assert_eq(
      resource.deletable,
      if permission == "false" {
        Some(false)
      } else {
        None
      },
    )
    let (observation, binding) = declared_observation(description)
    assert_true(
      prepare_delete_projection(observation, binding, "Record__c")
      is Err(DeletionNotProved),
    )
    let read = prepare_read_projection(
      observation,
      binding,
      "Record__c",
      ["Id"],
      100,
    ).unwrap()
    assert_eq(read_projection_fields(read), ["Id"])
  }
}

///|
test "delete metadata does not infer record identity from a name nullable value or another native type" {
  for
    identity in [
      "", "{\"name\":\"Id\",\"type\":\"string\",\"nillable\":false}", "{\"name\":\"Id\",\"type\":\"id\",\"nillable\":true}",
      "{\"name\":\"Id\",\"type\":\"id\"}",
    ] {
    let (observation, binding) = declared_observation(
      delete_test_description(identity~),
    )
    assert_true(
      prepare_delete_projection(observation, binding, "Record__c")
      is Err(NoRecordIdentity),
    )
  }
}

///|
test "delete metadata retains exact Site and Run binding before accepting a refreshed observation" {
  let (observation, binding) = declared_observation(delete_test_description())
  let projection = prepare_delete_projection(observation, binding, "Record__c").unwrap()
  for
    foreign in [
      { ..binding, org_id: "00D000000000002EAA", },
      { ..binding, connection_revision: "other-revision", },
      { ..binding, site_generation: binding.site_generation + 1, },
      { ..binding, namespace_id: "other-namespace", },
      { ..binding, run_invocation_cid: "sha256:" + "f".repeat(64), },
    ] {
    assert_true(
      prepare_delete_projection(observation, foreign, "Record__c")
      is Err(Observation(_)),
    )
    assert_false(delete_projection_matches_binding(projection, foreign))
    let current = delete_test_observation(delete_test_description(), foreign)
    assert_true(
      recheck_delete_projection(projection, current)
      is Err(ForeignCurrentObservation),
    )
  }
  let refreshed_binding = {
    ..binding,
    dispatch_request_cid: "sha256:" + "e".repeat(64),
    sync_occurrence: "fresh-occurrence",
  }
  let refreshed = delete_test_observation(
    delete_test_description(),
    refreshed_binding,
  )
  recheck_delete_projection(projection, refreshed).unwrap()
  assert_false(delete_projection_matches_binding(projection, refreshed_binding))
}

///|
test "delete metadata current recheck retains proof and record identity requirements" {
  let (observation, binding) = declared_observation(delete_test_description())
  let projection = prepare_delete_projection(observation, binding, "Record__c").unwrap()
  for permission in ["false", "", "null"] {
    let (changed, _) = declared_observation(
      delete_test_description(permission~),
    )
    assert_true(
      recheck_delete_projection(projection, changed) is Err(DeletionNotProved),
    )
  }
  let (changed, _) = declared_observation(delete_test_description(identity=""))
  assert_true(
    recheck_delete_projection(projection, changed) is Err(NoRecordIdentity),
  )
  recheck_delete_projection(projection, observation).unwrap()
}

///|
test "delete metadata keeps the original Local binding without filling Site fields" {
  let description = @utf8.encode(delete_test_description())
  let sync = begin_named_catalog_sync(["Record__c"]).unwrap()
  catalog_sync_describe(sync, "Record__c", description, limits()).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = local_catalog_test_binding()
  let observation = prepare_local_catalog_observation(
    sync,
    binding,
    "",
    [Some("sha256:" + "d".repeat(64))],
    [Some(catalog_response_sha256(description))],
    8192,
  ).unwrap()
  let projection = prepare_local_delete_projection(
    observation, binding, "Record__c",
  ).unwrap()
  assert_true(delete_projection_matches_local_binding(projection, binding))
  assert_false(
    delete_projection_matches_binding(projection, observation_test_binding()),
  )
  recheck_delete_projection(projection, observation).unwrap()
  assert_true(
    prepare_delete_projection(
      observation,
      observation_test_binding(),
      "Record__c",
    )
    is Err(Observation(_)),
  )
  let foreign = { ..binding, authority_scope_cid: local_catalog_test_cid("9"), }
  assert_true(
    prepare_local_delete_projection(observation, foreign, "Record__c")
    is Err(Observation(_)),
  )
}

///|
test "delete proof projection does not relabel existing Catalog contracts or advertise an executable write" {
  let missing = delete_test_description(permission="")
  let before = declared_for(missing)
  for permission in ["true", "false", "null", "\"true\""] {
    let description = delete_test_description(permission~)
    let after = declared_for(description)
    assert_eq(after.catalog, before.catalog)
    assert_eq(after.catalog_cid, before.catalog_cid)
    assert_eq(after.contracts, before.contracts)
    assert_eq(after.view_bodies, before.view_bodies)
    assert_eq(after.manifest_entry, before.manifest_entry)
    assert_eq(after.manifest_entry_cid, before.manifest_entry_cid)
    // Observation identity still hashes the exact different provider bytes.
    assert_not_eq(after.observation_cid, before.observation_cid)
  }
}
