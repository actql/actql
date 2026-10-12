///|
fn holder_catalog_scope_configuration() -> HolderEffectCatalogScope {
  {
    workspace: "original-workspace",
    principal: "provider-principal-not-reviewer",
    environment: "preview",
    registration: "salesforce",
    revision: "salesforce/0.1",
    origin: "https://provider.example",
  }
}

///|
fn holder_catalog_projected_scope(
  fields : Array[String],
) -> @effect_resource.NativeCredentialScope? {
  holder_effect_catalog_grant_scope(
    fields,
    holder_catalog_scope_configuration(),
    "sha256:" + "c".repeat(64),
    ["selected-site", "4", "sha256:" + "b".repeat(64)],
    ["coordinator", "selected-site", "4", "dispatch", "run", "task", "3"],
    "sha256:" + "d".repeat(64),
  )
}

///|
test "Catalog installation selects the existing bodyless GET operation" {
  let fields = holder_effect_scope_fixture()
  fields[11] = "salesforce:catalog:describe"
  let scope = holder_catalog_projected_scope(fields).unwrap()
  let operation = holder_effect_catalog_operation(
    scope, "Account", "v61.0", "/private/provider-token",
  )
  assert_eq(operation.resource_origin, "https://provider.example")
  assert_eq(operation.operation, "salesforce:catalog:describe")
  assert_eq(operation.path, "/services/data/v61.0/sobjects/Account/describe")
  assert_eq(operation.secret_path, "/private/provider-token")
  assert_true(operation.verb is @http.Get)
  assert_eq(operation.max_request_bytes, 0)
}

///|
/// These projection cases do not prove signatures, physical I/O or approval.
test "Catalog grant preserves original invocation and exact consumer routing" {
  let fields = holder_effect_scope_fixture()
  fields[11] = "salesforce:catalog:describe"
  let scope = holder_catalog_projected_scope(fields).unwrap()
  assert_eq(scope.run_invocation_cid, fields[12])
  assert_eq(scope.dispatch_request_cid, fields[14])
  assert_eq(scope.task_attempt, 3)
  assert_eq(scope.principal, "provider-principal-not-reviewer")
  assert_eq(scope.operation, "salesforce:catalog:describe")
}

///|
test "Catalog grant rejects each foreign original or independently installed scope field before service open" {
  for index in 2..<15 {
    let fields = holder_effect_scope_fixture()
    fields[11] = "salesforce:catalog:describe"
    fields[index] = "foreign"
    assert_true(holder_catalog_projected_scope(fields) is None)
  }
}

///|
test "Catalog grant does not accept Source read Effect write or Reviewer authority" {
  for
    operation in [
      "salesforce:record:create", "salesforce:record:observe", "duckdb:read", "reviewer:approve",
    ] {
    let fields = holder_effect_scope_fixture()
    fields[11] = operation
    assert_true(holder_catalog_projected_scope(fields) is None)
  }
  assert_true(holder_catalog_projected_scope([]) is None)
  let fields = holder_effect_scope_fixture()
  fields[11] = "salesforce:catalog:describe"
  assert_true(
    holder_effect_catalog_grant_scope(
      fields,
      holder_catalog_scope_configuration(),
      fields[12],
      [],
      [],
      fields[14],
    )
    is None,
  )
}
