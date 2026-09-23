///|
fn limits() -> DescribeLimits {
  {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
    max_fields: 20,
    max_name_units: 1000,
  }
}

///|
fn described() -> Bytes {
  let body =
    #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"External_Key__c","type":"string","nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true,"sortable":true,"externalId":true,"unique":true,"caseSensitive":true},{"name":"Optional_Value__c","type":"string","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true,"filterable":true},{"name":"Read_Only__c","type":"datetime","nillable":false,"createable":false,"updateable":false,"filterable":true,"referenceTo":[]}]}
  @utf8.encode(body)
}

///|
test "describe projection retains exact field permissions and unique external ID" {
  let resource = project_describe(described(), "ActQL_Test_Record__c", limits()).unwrap()
  assert_eq(resource.name, "ActQL_Test_Record__c")
  assert_true(resource.queryable && resource.createable && resource.updateable)
  assert_eq(resource.fields.length(), 3)
  let key = described_field(resource, "External_Key__c").unwrap()
  assert_true(key.external_id && key.unique && !key.nullable)
  assert_eq(key.case_sensitive, Some(true))
  assert_true(key.nullability_confirmed && key.default_on_create_confirmed)
  assert_false(key.defaulted_on_create)
  assert_true(
    key.createable && key.updateable && key.filterable && key.sortable,
  )
  let read_only = described_field(resource, "Read_Only__c").unwrap()
  assert_false(read_only.createable || read_only.updateable)
  assert_true(read_only.filterable)
  assert_true(described_field(resource, "Hidden_Field__c") is None)
}

///|
test "describe projection rejects identity mismatch and duplicate fields" {
  assert_true(
    project_describe(described(), "Account", limits()) is Err(ResourceMismatch),
  )
  let duplicate_body =
    #|{"name":"Account","fields":[{"name":"Id","type":"id"},{"name":"Id","type":"id"}]}
  let duplicate = @utf8.encode(duplicate_body)
  assert_true(
    project_describe(duplicate, "Account", limits())
    is Err(DuplicateField("Id")),
  )
  assert_true(
    project_describe(described(), "1Account", limits()) is Err(InvalidResponse),
  )
}

///|
test "missing capability flags cannot grant write or pushdown authority" {
  let incomplete_body =
    #|{"name":"Account","fields":[{"name":"Name","type":"string"}]}
  let incomplete = @utf8.encode(incomplete_body)
  let resource = project_describe(incomplete, "Account", limits()).unwrap()
  assert_false(resource.queryable || resource.createable || resource.updateable)
  let field = described_field(resource, "Name").unwrap()
  assert_true(field.nullable)
  assert_false(field.nullability_confirmed)
  assert_false(field.default_on_create_confirmed)
  assert_false(
    field.createable ||
    field.updateable ||
    field.filterable ||
    field.sortable ||
    field.external_id ||
    field.unique,
  )
}

///|
test "describe projection enforces byte and field budgets before publication" {
  assert_true(
    project_describe(described(), "ActQL_Test_Record__c", {
      ..limits(),
      max_bytes: 32,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_describe(described(), "ActQL_Test_Record__c", {
      ..limits(),
      max_fields: 2,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_describe(described(), "ActQL_Test_Record__c", {
      ..limits(),
      max_name_units: 5,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_describe(described(), "ActQL_Test_Record__c", {
      ..limits(),
      max_nodes: -1,
    })
    is Err(InvalidLimits),
  )
}

///|
test "malformed permission and reference metadata fail closed" {
  let malformed_body =
    #|{"name":"Account","fields":[{"name":"Name","type":"string","createable":"yes"}]}
  let malformed = @utf8.encode(malformed_body)
  assert_true(
    project_describe(malformed, "Account", limits())
    is Err(InvalidField("Name")),
  )
  let reference_body =
    #|{"name":"Account","fields":[{"name":"OwnerId","type":"reference","referenceTo":["User","User"]}]}
  let reference = @utf8.encode(reference_body)
  assert_true(
    project_describe(reference, "Account", limits())
    is Err(InvalidField("OwnerId")),
  )
}
