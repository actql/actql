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
fn admission_test_plan(program : String) -> PublicationContract {
  seal_publication_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"compiler-0.1\"," +
    "\"aoa_ir_version\":\"aoa-ir-0.1\"," +
    "\"executable_plan_cid\":\"" +
    admission_test_cid("0") +
    "\",\"program_definition_cid\":\"" +
    program +
    "\",\"program_semantics_cid\":\"" +
    admission_test_cid("a") +
    "\",\"aoa_contract_cid\":\"" +
    admission_test_cid("b") +
    "\",\"aoa_logical_cid\":\"" +
    admission_test_cid("c") +
    "\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
fn admission_test_prepared(
  template : RunEvidenceValue,
  plan : PublicationContract,
  decision : String,
) -> RunEvidenceValue {
  seal_run_evidence_value(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    publication_contract_identity(plan) +
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
  let plan = admission_test_plan(admission_test_cid("1"))
  let prepared = admission_test_prepared(template, plan, "allow")
  let authorization = admission_test_authorization(prepared, "allowed", false)
  let admission = admit_run_publication(template, prepared, authorization, plan).unwrap()
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
      "\"compiled_plan_cid\":\"" + publication_contract_identity(plan) + "\"",
    ),
  )
  assert_true(
    publication_contract_json(definition).contains(
      "\"authorization_context_cid\":\"" + admission_test_cid("8") + "\"",
    ),
  )
}

///|
test "checked Run admission binds Program, Values, semantics, and environment" {
  let template = admission_test_template()
  let plan = admission_test_plan(admission_test_cid("1"))
  let prepared = admission_test_prepared(template, plan, "allow")
  let authorization = admission_test_authorization(prepared, "allowed", false)
  assert_true(
    admit_checked_run_publication(
      template,
      prepared,
      authorization,
      plan,
      admission_test_cid("1"),
      admission_test_cid("2"),
      admission_test_cid("a"),
      admission_test_cid("4"),
    )
    is Ok(_),
  )
  for changed in 0..<4 {
    let program = if changed == 0 {
      admission_test_cid("d")
    } else {
      admission_test_cid("1")
    }
    let parameters = if changed == 1 {
      admission_test_cid("d")
    } else {
      admission_test_cid("2")
    }
    let semantics = if changed == 2 {
      admission_test_cid("d")
    } else {
      admission_test_cid("a")
    }
    let environment = if changed == 3 {
      admission_test_cid("d")
    } else {
      admission_test_cid("4")
    }
    assert_true(
      admit_checked_run_publication(
        template, prepared, authorization, plan, program, parameters, semantics,
        environment,
      )
      is Err(RunAdmissionCheckedProgramMismatch),
    )
  }
}

///|
test "Run admission rejects substituted authority and unverified review" {
  let template = admission_test_template()
  let plan = admission_test_plan(admission_test_cid("1"))
  let allowed = admission_test_prepared(template, plan, "allow")
  let reviewed = admission_test_prepared(template, plan, "review")
  assert_true(
    admit_run_publication(
      template,
      allowed,
      admission_test_authorization(reviewed, "approved", true),
      plan,
    )
    is Err(RunAdmissionPreparedMismatch),
  )
  assert_true(
    admit_run_publication(
      template,
      reviewed,
      admission_test_authorization(reviewed, "approved", false),
      plan,
    )
    is Err(RunAdmissionDecisionMismatch),
  )
  assert_true(
    admit_run_publication(
      template,
      allowed,
      admission_test_authorization(allowed, "approved", true),
      plan,
    )
    is Err(RunAdmissionDecisionMismatch),
  )
  let foreign_plan = admission_test_plan(admission_test_cid("d"))
  let foreign_prepared = admission_test_prepared(
    template, foreign_plan, "allow",
  )
  assert_true(
    admit_run_publication(
      template,
      foreign_prepared,
      admission_test_authorization(foreign_prepared, "allowed", false),
      foreign_plan,
    )
    is Err(RunAdmissionWrongPlan),
  )
}

///|
test "Run Definition cannot outlive admitted preparation" {
  let template = admission_test_template()
  let plan = admission_test_plan(admission_test_cid("1"))
  let prepared = admission_test_prepared(template, plan, "allow")
  let admission = admit_run_publication(
    template,
    prepared,
    admission_test_authorization(prepared, "allowed", false),
    plan,
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
