///|
/// Caller projections only; no fake positive nominal proof supplies a GET.
/// Physical consumer/Journal/Resource integration remains separate acceptance.
test "missing Catalog use without original funded readiness cannot select initial GET" {
  for
    issue in [
      @journal.StateCollision,
      @journal.StaleSiteBinding,
      @journal.Physical(@sqlite.NotFound),
      @journal.Closed,
    ] {
    let checks = Ref(0)
    assert_false(
      holder_catalog_initial_read_ready(
        Original(@journal.Physical(@sqlite.NotFound)),
        () => {
          checks.val += 1
          Err(issue)
        },
      ),
    )
    assert_eq(checks.val, 1)
  }
}

///|
test "replacement Resource DB or changed original Catalog binding never reaches initial readiness" {
  for
    issue in [
      Resource(@effect_resource.Journal(@sqlite.NotFound)),
      Resource(@effect_resource.AccessDenied),
      Original(@journal.StaleSiteBinding),
      Original(@journal.StateCollision),
      Changed,
    ] {
    let checks = Ref(0)
    assert_false(
      holder_catalog_initial_read_ready(issue, () => {
        checks.val += 1
        Err(@journal.StateCollision)
      }),
    )
    assert_eq(checks.val, 0)
  }
}

///|
test "initial Catalog hook matches every installed original scope field" {
  let original : @effect_resource.NativeCredentialScope = {
    principal: "provider-principal",
    namespace_id: "original-workspace",
    environment: "preview",
    site_key: "selected-site",
    site_generation: 4,
    runtime_bundle_cid: "sha256:" + "a".repeat(64),
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://provider.invalid",
    operation: "salesforce:catalog:describe",
    run_invocation_cid: "sha256:" + "b".repeat(64),
    task_attempt: 7,
    dispatch_request_cid: "sha256:" + "c".repeat(64),
  }
  assert_true(holder_catalog_initial_scope_matches(original, original))
  for
    foreign in [
      { ..original, principal: "foreign", },
      { ..original, namespace_id: "foreign", },
      { ..original, environment: "foreign", },
      { ..original, site_key: "foreign", },
      { ..original, site_generation: 5, },
      { ..original, runtime_bundle_cid: "sha256:" + "d".repeat(64), },
      { ..original, connector_registration: "foreign", },
      { ..original, connector_revision: "foreign", },
      { ..original, resource_origin: "https://foreign.invalid", },
      { ..original, operation: "foreign", },
      { ..original, run_invocation_cid: "sha256:" + "d".repeat(64), },
      { ..original, task_attempt: 8, },
      { ..original, dispatch_request_cid: "sha256:" + "d".repeat(64), },
    ] {
    assert_false(holder_catalog_initial_scope_matches(original, foreign))
  }
}

///|
fn holder_catalog_initial_scope_matches(
  expected : @effect_resource.NativeCredentialScope,
  proposed : @effect_resource.NativeCredentialScope,
) -> Bool {
  expected.principal == proposed.principal &&
  expected.namespace_id == proposed.namespace_id &&
  expected.environment == proposed.environment &&
  expected.site_key == proposed.site_key &&
  expected.site_generation == proposed.site_generation &&
  expected.runtime_bundle_cid == proposed.runtime_bundle_cid &&
  expected.connector_registration == proposed.connector_registration &&
  expected.connector_revision == proposed.connector_revision &&
  expected.resource_origin == proposed.resource_origin &&
  expected.operation == proposed.operation &&
  expected.run_invocation_cid == proposed.run_invocation_cid &&
  expected.task_attempt == proposed.task_attempt &&
  expected.dispatch_request_cid == proposed.dispatch_request_cid
}

///|
/// This restoration error alone is never unsent evidence. Only a successful
/// read of the original funded eligibility can select the separate first-use
/// path; the actual Resource hook must still claim it transactionally.
fn holder_catalog_initial_read_ready(
  issue : HolderCatalogUseObservationIssue,
  read_ready : () -> Result[Unit, @journal.NativeRemoteJournalIssue],
) -> Bool {
  match issue {
    Original(@journal.Physical(@sqlite.NotFound)) => read_ready() is Ok(_)
    _ => false
  }
}
