///|
fn write_test_observation_with(
  description : Bytes,
  binding : CatalogObservationBinding,
) -> CatalogObservation {
  let listing = project_resource_listing(
    @utf8.encode(
      (
        #|{"sobjects":[{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true}]}
      ),
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = begin_catalog_sync(listing)
  catalog_sync_describe(sync, "ActQL_Test_Record__c", description, limits()).unwrap()
  finish_catalog_sync(sync).unwrap()
  prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(@sha.hex(description))],
    4096,
  ).unwrap()
}

///|
fn write_test_observation() -> (CatalogObservation, CatalogObservationBinding) {
  let binding = observation_test_binding()
  (write_test_observation_with(described(), binding), binding)
}

///|
test "write projection keeps create update and upsert boundaries distinct" {
  let (observation, binding) = write_test_observation()
  let created = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteCreate,
    ["External_Key__c", "Optional_Value__c"],
    2,
  ).unwrap()
  assert_eq(
    write_projection_observation(created),
    catalog_observation_identity(observation),
  )
  assert_eq(write_projection_resource(created), "ActQL_Test_Record__c")
  assert_eq(write_projection_operation(created), WriteCreate)
  assert_eq(write_projection_fields(created), [
    "External_Key__c", "Optional_Value__c",
  ])
  assert_true(write_projection_matches_binding(created, binding))
  assert_false(
    write_projection_matches_binding(created, {
      ..binding,
      site_generation: binding.site_generation + 1,
    }),
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "ActQL_Test_Record__c",
      WriteCreate,
      ["Optional_Value__c"],
      2,
    )
    is Err(Requirement(MissingRequiredCreateField("External_Key__c"))),
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "ActQL_Test_Record__c",
      WriteUpdateById,
      ["Optional_Value__c"],
      2,
    )
    is Ok(_),
  )
  let upsert = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteUpsertByExternalId("External_Key__c"),
    ["Optional_Value__c"],
    2,
  ).unwrap()
  assert_eq(
    write_projection_operation(upsert),
    WriteUpsertByExternalId("External_Key__c"),
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "ActQL_Test_Record__c",
      WriteUpsertByExternalId("External_Key__c"),
      ["External_Key__c"],
      2,
    )
    is Err(TargetFieldInBody("External_Key__c")),
  )
}

///|
test "write candidates reject foreign views and incomplete field authority" {
  let (observation, binding) = write_test_observation()
  assert_true(
    prepare_write_projection(
      observation,
      { ..binding, connection_revision: "next", },
      "ActQL_Test_Record__c",
      WriteCreate,
      ["External_Key__c"],
      1,
    )
    is Err(Observation(ForeignBinding)),
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "ActQL_Test_Record__c",
      WriteUpdateById,
      ["Hidden_Field__c"],
      1,
    )
    is Err(Requirement(FieldUnconfirmed("Hidden_Field__c"))),
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "ActQL_Test_Record__c",
      WriteUpdateById,
      ["Optional_Value__c"],
      0,
    )
    is Err(FieldLimit),
  )
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "ActQL_Test_Record__c",
      WriteUpdateById,
      [],
      1,
    )
    is Err(EmptyUpdate),
  )
}

///|
test "write candidates reject unconfirmed nullability and unmodeled types" {
  let binding = observation_test_binding()
  let without_nullability = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"Value__c","type":"string","createable":true,"updateable":true}]}
    ),
  )
  let observation = write_test_observation_with(without_nullability, binding)
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "ActQL_Test_Record__c",
      WriteUpdateById,
      ["Value__c"],
      1,
    )
    is Err(UnconfirmedNullability("Value__c")),
  )
  let unmodeled = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"Value__c","type":"multipicklist","nillable":true,"createable":true,"updateable":true}]}
    ),
  )
  let observation = write_test_observation_with(unmodeled, binding)
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "ActQL_Test_Record__c",
      WriteUpdateById,
      ["Value__c"],
      1,
    )
    is Err(UnsupportedWriteType("Value__c")),
  )
}

///|
test "write recheck accepts a new sync but rejects authority and schema drift" {
  let (observation, binding) = write_test_observation()
  let created = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteCreate,
    ["External_Key__c", "Optional_Value__c"],
    2,
  ).unwrap()
  let upsert = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteUpsertByExternalId("External_Key__c"),
    ["Optional_Value__c"],
    2,
  ).unwrap()
  let refreshed = {
    ..binding,
    dispatch_request_cid: "sha256:" + "e".repeat(64),
    sync_occurrence: "new-sync",
  }
  assert_true(
    recheck_write_projection(
      created,
      write_test_observation_with(described(), refreshed),
    )
    is Ok(_),
  )
  assert_true(
    recheck_write_projection(
      created,
      write_test_observation_with(described(), {
        ..refreshed,
        site_generation: refreshed.site_generation + 1,
      }),
    )
    is Err(ForeignCurrentObservation),
  )
  let changed_type = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"External_Key__c","type":"string","nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true,"sortable":true,"externalId":true,"unique":true,"caseSensitive":true},{"name":"Optional_Value__c","type":"int","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true}]}
    ),
  )
  assert_true(
    recheck_write_projection(
      created,
      write_test_observation_with(changed_type, refreshed),
    )
    is Err(SchemaChanged("Optional_Value__c")),
  )
  let changed_external_id = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"External_Key__c","type":"string","nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true,"sortable":true,"externalId":true,"unique":false},{"name":"Optional_Value__c","type":"string","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true}]}
    ),
  )
  assert_true(
    recheck_write_projection(
      upsert,
      write_test_observation_with(changed_external_id, refreshed),
    )
    is Err(Requirement(ExternalIdNotUnique("External_Key__c"))),
  )
  let changed_case = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"External_Key__c","type":"string","nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true,"sortable":true,"externalId":true,"unique":true,"caseSensitive":false},{"name":"Optional_Value__c","type":"string","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true}]}
    ),
  )
  assert_true(
    recheck_write_projection(
      upsert,
      write_test_observation_with(changed_case, refreshed),
    )
    is Err(SchemaChanged("External_Key__c")),
  )
  let new_required = @utf8.encode(
    (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"External_Key__c","type":"string","nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true,"sortable":true,"externalId":true,"unique":true,"caseSensitive":true},{"name":"Optional_Value__c","type":"string","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true},{"name":"Required_New__c","type":"string","nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true}]}
    ),
  )
  assert_true(
    recheck_write_projection(
      created,
      write_test_observation_with(new_required, refreshed),
    )
    is Err(Requirement(MissingRequiredCreateField("Required_New__c"))),
  )
}
