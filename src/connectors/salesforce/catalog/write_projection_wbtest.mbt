///|
fn write_test_observation() -> (CatalogObservation, CatalogObservationBinding) {
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
  let description = described()
  catalog_sync_describe(sync, "ActQL_Test_Record__c", description, limits()).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(@sha.hex(description))],
    4096,
  ).unwrap()
  (observation, binding)
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
