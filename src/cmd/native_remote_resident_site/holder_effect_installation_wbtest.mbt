///|
/// Projection fixtures are not signed grants or Provider authority. The real
/// installation invokes the existing signature verifier before this function.
fn holder_effect_scope_fixture() -> Array[String] {
  [
    "sha256:" + "a".repeat(64),
    "credential-issuer",
    "provider-principal-not-reviewer",
    "original-workspace",
    "preview",
    "selected-site",
    "4",
    "sha256:" + "b".repeat(64),
    "salesforce",
    "salesforce/0.1",
    "https://provider.example",
    "salesforce:record:create",
    "sha256:" + "c".repeat(64),
    "3",
    "sha256:" + "d".repeat(64),
    "2000",
    "1",
  ]
}

///|
test "Resume Provider installation preserves Provider principal separately from Reviewer and original attempt" {
  let fields = holder_effect_scope_fixture()
  let scope = holder_effect_provider_scope(
    fields,
    "original-workspace",
    "selected-site",
    4,
    "sha256:" + "b".repeat(64),
    "salesforce",
    "salesforce/0.1",
  ).unwrap()
  assert_eq(scope.principal, "provider-principal-not-reviewer")
  assert_eq(scope.run_invocation_cid, fields[12])
  assert_eq(scope.dispatch_request_cid, fields[14])
  assert_eq(scope.task_attempt, 3)
  fields[13] = "0"
  assert_eq(
    holder_effect_provider_scope(
      fields,
      "original-workspace",
      "selected-site",
      4,
      "sha256:" + "b".repeat(64),
      "salesforce",
      "salesforce/0.1",
    ).unwrap().task_attempt,
    0,
  )
}

///|
test "Resume Provider installation refuses each foreign workspace Site generation runtime Connector and read grant" {
  for index in [3, 5, 6, 7, 8, 9, 11] {
    let fields = holder_effect_scope_fixture()
    fields[index] = if index == 11 {
      "salesforce:record:observe"
    } else {
      "foreign"
    }
    assert_true(
      holder_effect_provider_scope(
        fields,
        "original-workspace",
        "selected-site",
        4,
        "sha256:" + "b".repeat(64),
        "salesforce",
        "salesforce/0.1",
      )
      is None,
    )
  }
}

///|
test "Resume Provider installation refuses incomplete and invalid attempts without opening its physical service" {
  for attempt in ["-1", "3x"] {
    let fields = holder_effect_scope_fixture()
    fields[13] = attempt
    assert_true(
      holder_effect_provider_scope(
        fields,
        "original-workspace",
        "selected-site",
        4,
        "sha256:" + "b".repeat(64),
        "salesforce",
        "salesforce/0.1",
      )
      is None,
    )
  }
  assert_true(
    holder_effect_provider_scope(
      [],
      "original-workspace",
      "selected-site",
      4,
      "sha256:" + "b".repeat(64),
      "salesforce",
      "salesforce/0.1",
    )
    is None,
  )
}

///|
test "Resume Provider installation matches only its actual selected dispatch before resource opening" {
  let fields = holder_effect_scope_fixture()
  let scope = holder_effect_provider_scope(
    fields,
    "original-workspace",
    "selected-site",
    4,
    "sha256:" + "b".repeat(64),
    "salesforce",
    "salesforce/0.1",
  ).unwrap()
  let execution = [
    "selected-site",
    "4",
    fields[7],
    "duckdb",
    "duckdb/0.1",
    "strategy",
    "source-grant",
    "source-evidence-capability",
  ]
  let route = [
    "coordinator", "selected-site", "4", "dispatch", "run", "task", "3",
  ]
  assert_true(
    holder_effect_provider_dispatch_matches(scope, execution, route, fields[14]),
  )
  // Effect grant registration is independent from the Source registration.
  for index in [0, 1, 2] {
    let foreign = execution.copy()
    foreign[index] = "foreign"
    assert_false(
      holder_effect_provider_dispatch_matches(scope, foreign, route, fields[14]),
    )
  }
  let foreign_attempt = route.copy()
  foreign_attempt[6] = "4"
  assert_false(
    holder_effect_provider_dispatch_matches(
      scope,
      execution,
      foreign_attempt,
      fields[14],
    ),
  )
  assert_false(
    holder_effect_provider_dispatch_matches(scope, execution, route, "foreign"),
  )
  assert_false(
    holder_effect_provider_dispatch_matches(scope, [], [], fields[14]),
  )
}
