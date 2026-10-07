///|
test "recorded publication preserves original admitted wires and deadlines" {
  let original_template = admission_test_template()
  let original_plan = admission_test_plan(admission_test_cid("1"))
  let original_prepared = admission_test_prepared(
    original_template, original_plan, "allow",
  )
  let original_authorization = admission_test_authorization(
    original_prepared, "allowed", false,
  )
  let original = admit_run_publication(
    original_template, original_prepared, original_authorization, original_plan,
  ).unwrap()
  let definition = issue_run_definition(
    original,
    "scope",
    "run",
    admission_test_cid("b"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T02:00:00.000Z",
    16384,
    128,
    8,
  ).unwrap()
  // Restore through the real canonical owners. No compiler or fresh issuer
  // replaces the original Template, Plan, authorization or Run Definition.
  let restored = admit_run_publication(
    admit_run_evidence_value(
      "bound_invocation_template",
      run_evidence_value_json(original_template),
      16384,
      128,
      8,
    ).unwrap(),
    admit_run_evidence_value(
      "prepared_invocation",
      run_evidence_value_json(original_prepared),
      16384,
      128,
      8,
    ).unwrap(),
    admit_run_evidence_value(
      "run_authorization",
      run_evidence_value_json(original_authorization),
      16384,
      128,
      8,
    ).unwrap(),
    admit_publication_contract(
      "compiled_plan",
      publication_contract_json(original_plan),
      16384,
      128,
      8,
    ).unwrap(),
  ).unwrap()
  let result = prepare_result_definition(admission_test_cid("1"), "answer").unwrap()
  let recorded = prepare_recorded_run_publication(
    restored,
    admit_publication_contract(
      "run_definition",
      publication_contract_json(definition),
      16384,
      128,
      8,
    ).unwrap(),
    admit_result_definition(
      result_definition_json(result).unwrap(),
      16384,
      128,
      8,
    ).unwrap(),
  ).unwrap()
  assert_eq(
    recorded_run_publication_run_cid(recorded),
    publication_contract_identity(definition),
  )
  assert_eq(
    recorded_run_publication_result_cid(recorded),
    result_definition_cid(result),
  )
  assert_false(
    recorded_run_publication_current(recorded, "2026-09-17T23:59:59.999Z"),
  )
  assert_true(
    recorded_run_publication_current(recorded, "2026-09-18T00:00:00.000Z"),
  )
  assert_false(
    recorded_run_publication_current(recorded, "2026-09-18T02:00:00.000Z"),
  )
  assert_false(recorded_run_publication_current(recorded, "invalid-clock"))
  assert_true(
    recorded_run_publication_has_original_evidence(
      recorded,
      run_evidence_value_json(original_prepared),
      run_evidence_value_json(original_authorization),
    ),
  )
  assert_false(
    recorded_run_publication_has_original_evidence(
      recorded,
      run_evidence_value_json(original_prepared),
      "another-valid-authorization-is-not-the-original",
    ),
  )
  assert_false(
    recorded_run_publication_has_original_evidence(
      recorded,
      "another-preparation",
      run_evidence_value_json(original_authorization),
    ),
  )
}

///|
test "recorded publication rejects substituted original Run and Result" {
  let template = admission_test_template()
  let plan = admission_test_plan(admission_test_cid("1"))
  let prepared = admission_test_prepared(template, plan, "allow")
  let admission = admit_run_publication(
    template,
    prepared,
    admission_test_authorization(prepared, "allowed", false),
    plan,
  ).unwrap()
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
  let result = prepare_result_definition(admission_test_cid("1"), "answer").unwrap()
  assert_true(
    prepare_recorded_run_publication(
      admission,
      definition,
      prepare_result_definition(admission_test_cid("2"), "answer").unwrap(),
    )
    is Err(RunProgramForeignPlan),
  )
  let foreign_plan = admission_test_plan(admission_test_cid("2"))
  let foreign_template = admit_run_evidence_value(
    "bound_invocation_template",
    run_evidence_value_json(template).replace(
      old=admission_test_cid("1"),
      new=admission_test_cid("2"),
    ),
    16384,
    128,
    8,
  )
  // Reusing a sealed body's self identity must be rejected before restoration.
  assert_true(foreign_template is Err(_))
  let other_prepared = admission_test_prepared(template, plan, "allow")
  let denied = admission_test_authorization(other_prepared, "approved", true)
  assert_true(
    admit_run_publication(template, other_prepared, denied, plan)
    is Err(RunAdmissionDecisionMismatch),
  )
  // A different valid compilation cannot authorize the old Run Definition.
  assert_true(
    admit_run_publication(
      template,
      prepared,
      admission_test_authorization(prepared, "allowed", false),
      foreign_plan,
    )
    is Err(_),
  )
  assert_true(
    prepare_recorded_run_publication(admission, plan, result)
    is Err(RunProgramWrongDefinition),
  )
  let definition_body = captured_test_wire(
    @json.object_without_field(
      captured_test_value(publication_contract_json(definition)),
      "run_definition_cid",
    ).unwrap(),
  )
  let foreign_run = seal_publication_contract(
    "run_definition",
    definition_body.replace(
      old=admission_test_cid("8"),
      new=admission_test_cid("7"),
    ),
    16384,
    128,
    8,
  ).unwrap()
  assert_true(
    prepare_recorded_run_publication(admission, foreign_run, result)
    is Err(RunProgramForeignRun),
  )
  let renewed_run = seal_publication_contract(
    "run_definition",
    definition_body.replace(
      old="2026-09-18T02:00:00.000Z",
      new="2026-09-18T04:00:00.000Z",
    ),
    16384,
    128,
    8,
  ).unwrap()
  assert_true(
    prepare_recorded_run_publication(admission, renewed_run, result)
    is Err(RunProgramInvalidLifetime),
  )
}
