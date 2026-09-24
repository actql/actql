///|
test "resource requirements preserve field-level read and write boundaries" {
  let resource = project_describe(described(), "ActQL_Test_Record__c", limits()).unwrap()
  assert_eq(
    require_read_fields(resource, ["External_Key__c", "Read_Only__c"])
    .unwrap()
    .length(),
    2,
  )
  assert_true(
    require_read_fields(resource, ["Hidden_Field__c"])
    is Err(FieldUnconfirmed("Hidden_Field__c")),
  )
  assert_true(
    require_read_fields(resource, ["External_Key__c", "External_Key__c"])
    is Err(DuplicateRequestedField("External_Key__c")),
  )
  assert_eq(
    require_create_fields(resource, ["External_Key__c", "Optional_Value__c"])
    .unwrap()
    .length(),
    2,
  )
  assert_true(
    require_create_fields(resource, ["Read_Only__c"])
    is Err(FieldNotCreateable("Read_Only__c")),
  )
  assert_true(
    require_create_fields(resource, ["Optional_Value__c"])
    is Err(MissingRequiredCreateField("External_Key__c")),
  )
  assert_true(
    require_update_fields(resource, ["Read_Only__c"])
    is Err(FieldNotUpdateable("Read_Only__c")),
  )
  assert_eq(
    require_unique_external_id(resource, "External_Key__c").unwrap().name,
    "External_Key__c",
  )
  assert_true(
    require_unique_external_id(resource, "Optional_Value__c")
    is Err(ExternalIdNotUnique("Optional_Value__c")),
  )
  assert_eq(
    require_upsert_fields(resource, "External_Key__c", ["Optional_Value__c"])
    .unwrap()
    .length(),
    1,
  )
  assert_true(
    require_upsert_fields(resource, "Optional_Value__c", ["External_Key__c"])
    is Err(ExternalIdNotUnique("Optional_Value__c")),
  )
  assert_true(
    require_upsert_fields(resource, "External_Key__c", ["External_Key__c"])
    is Err(ExternalTargetInBody("External_Key__c")),
  )
}

///|
test "create admission rejects incomplete required-field metadata" {
  let body =
    #|{"name":"Custom__c","createable":true,"fields":[{"name":"Key__c","type":"string","nillable":false,"createable":true}]}
  let resource = project_describe(@utf8.encode(body), "Custom__c", limits()).unwrap()
  assert_true(
    require_create_fields(resource, ["Key__c"])
    is Err(FieldConstraintUnconfirmed("Key__c")),
  )
  let defaulted =
    #|{"name":"Custom__c","createable":true,"fields":[{"name":"Generated__c","type":"string","nillable":false,"defaultedOnCreate":true,"createable":true}]}
  let resource = project_describe(
    @utf8.encode(defaulted),
    "Custom__c",
    limits(),
  ).unwrap()
  assert_true(require_create_fields(resource, []) is Ok(_))
}

///|
test "missing object permission cannot be granted from field flags" {
  let body =
    #|{"name":"Account","queryable":false,"createable":false,"updateable":false,"fields":[{"name":"Name","type":"string","createable":true,"updateable":true}]}
  let resource = project_describe(@utf8.encode(body), "Account", limits()).unwrap()
  assert_true(
    require_read_fields(resource, ["Name"]) is Err(ResourceNotQueryable),
  )
  assert_true(
    require_create_fields(resource, ["Name"]) is Err(ResourceNotCreateable),
  )
  assert_true(
    require_update_fields(resource, ["Name"]) is Err(ResourceNotUpdateable),
  )
}
