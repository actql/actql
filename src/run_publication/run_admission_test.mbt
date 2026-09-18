///|
fn admission_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn admission_test_template() -> RunEvidenceValue {
  seal_run_evidence_value(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    admission_test_cid("1") +
    "\",\"parameter_values_cid\":\"" +
    admission_test_cid("2") +
    "\",\"invocation_bindings_cid\":\"" +
    admission_test_cid("3") +
    "\",\"check_environment_cid\":\"" +
    admission_test_cid("4") +
    "\",\"grammar_manifest_cid\":\"" +
    admission_test_cid("5") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    admission_test_cid("6") +
    "\",\"source_evidence\":\"unbound\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
fn admission_test_prepared(
  template : RunEvidenceValue,
  decision : String,
) -> RunEvidenceValue {
  seal_run_evidence_value(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    admission_test_cid("7") +
    "\",\"execution_context_cid\":\"" +
    admission_test_cid("8") +
    "\",\"host_policy_cid\":\"" +
    admission_test_cid("9") +
    "\",\"policy_decision\":\"" +
    decision +
    "\",\"expires_at\":\"2026-09-18T03:00:00.000Z\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
fn admission_test_authorization(
  prepared : RunEvidenceValue,
  decision : String,
  approval : Bool,
) -> RunEvidenceValue {
  let approval_field = if approval {
    ",\"run_scope_approval_cid\":\"" + admission_test_cid("a") + "\""
  } else {
    ""
  }
  seal_run_evidence_value(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\"," +
    "\"prepared_invocation_cid\":\"" +
    run_evidence_value_identity(prepared) +
    "\",\"execution_context_cid\":\"" +
    admission_test_cid("8") +
    "\",\"host_policy_cid\":\"" +
    admission_test_cid("9") +
    "\",\"decision\":\"" +
    decision +
    "\"" +
    approval_field +
    "}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
test "Run Definition is issued only from exact admitted allow authority" {
  let template = admission_test_template()
  let prepared = admission_test_prepared(template, "allow")
  let authorization = admission_test_authorization(prepared, "allowed", false)
  let admission = admit_run_publication(template, prepared, authorization).unwrap()
  let definition = issue_run_definition(
    admission,
    "scope",
    "run",
    admission_test_cid("b"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T02:00:00.000Z",
    16384,
    128,
    8,
  ).unwrap()
  assert_eq(publication_contract_name(definition), "run_definition")
  assert_true(
    publication_contract_json(definition).contains(
      "\"compiled_plan_cid\":\"" + admission_test_cid("7") + "\"",
    ),
  )
  assert_true(
    publication_contract_json(definition).contains(
      "\"authorization_context_cid\":\"" + admission_test_cid("8") + "\"",
    ),
  )
}

///|
test "Run admission rejects substituted authority and unverified review" {
  let template = admission_test_template()
  let allowed = admission_test_prepared(template, "allow")
  let reviewed = admission_test_prepared(template, "review")
  assert_true(
    admit_run_publication(
      template,
      allowed,
      admission_test_authorization(reviewed, "approved", true),
    )
    is Err(RunAdmissionPreparedMismatch),
  )
  assert_true(
    admit_run_publication(
      template,
      reviewed,
      admission_test_authorization(reviewed, "approved", false),
    )
    is Err(RunAdmissionDecisionMismatch),
  )
  assert_true(
    admit_run_publication(
      template,
      allowed,
      admission_test_authorization(allowed, "approved", true),
    )
    is Err(RunAdmissionDecisionMismatch),
  )
}

///|
test "Run Definition cannot outlive admitted preparation" {
  let template = admission_test_template()
  let prepared = admission_test_prepared(template, "allow")
  let admission = admit_run_publication(
    template,
    prepared,
    admission_test_authorization(prepared, "allowed", false),
  ).unwrap()
  assert_true(
    issue_run_definition(
      admission,
      "scope",
      "run",
      admission_test_cid("b"),
      "2026-09-18T00:00:00.000Z",
      "2026-09-18T04:00:00.000Z",
      16384,
      128,
      8,
    )
    is Err(RunAdmissionInvalidLifetime),
  )
}
