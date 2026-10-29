///|
/// Installation configuration is selected by the operator, independently of
/// grant wire, Source permission and Reviewer authority. Original invocation
/// and consumer routing are supplied by the retained preparation Owners.
priv struct HolderEffectCatalogScope {
  workspace : String
  principal : String
  environment : String
  registration : String
  revision : String
  origin : String
}

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

///|
/// Projection is not signature verification. The installation calls the
/// existing credential verifier before this exact original-scope comparison.
fn holder_effect_catalog_grant_scope(
  fields : Array[String],
  configured : HolderEffectCatalogScope,
  invocation_cid : String,
  execution : Array[String],
  route : Array[String],
  dispatch_cid : String,
) -> @effect_resource.NativeCredentialScope? {
  guard fields.length() == 17 &&
    execution.length() >= 3 &&
    route.length() >= 7 &&
    fields[2] == configured.principal &&
    fields[3] == configured.workspace &&
    fields[4] == configured.environment &&
    fields[5] == execution[0] &&
    fields[6] == execution[1] &&
    fields[7] == execution[2] &&
    fields[8] == configured.registration &&
    fields[9] == configured.revision &&
    fields[10] == configured.origin &&
    fields[11] == "salesforce:catalog:describe" &&
    fields[12] == invocation_cid &&
    fields[13] == route[6] &&
    fields[14] == dispatch_cid else {
    return None
  }
  let generation : Int = @string.from_str(execution[1]) catch {
    _ => return None
  }
  let attempt : Int = @string.from_str(route[6]) catch { _ => return None }
  guard generation >= 0 && attempt >= 0 else { return None }
  Some({
    principal: configured.principal,
    namespace_id: configured.workspace,
    environment: configured.environment,
    site_key: execution[0],
    site_generation: generation,
    runtime_bundle_cid: execution[2],
    connector_registration: configured.registration,
    connector_revision: configured.revision,
    resource_origin: configured.origin,
    operation: "salesforce:catalog:describe",
    run_invocation_cid: invocation_cid,
    task_attempt: attempt,
    dispatch_request_cid: dispatch_cid,
  })
}

///|
/// Catalog describe is a bodyless GET. The existing Resource Owner rejects
/// GET operations with a nonzero request-body allowance.
fn holder_effect_catalog_operation(
  scope : @effect_resource.NativeCredentialScope,
  resource : String,
  api_version : String,
  secret_path : String,
) -> @effect_resource.NativeCredentialOperation {
  {
    resource_origin: scope.resource_origin,
    operation: scope.operation,
    path: "/services/data/" +
    api_version +
    "/sobjects/" +
    resource +
    "/describe",
    secret_path,
    verb: @http.Get,
    max_request_bytes: 0,
  }
}
