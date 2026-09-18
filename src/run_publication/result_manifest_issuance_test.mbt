///|
fn manifest_test_run(template : String) -> PublicationContract {
  seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\"," +
    "\"scope_id\":\"scope\",\"run_id\":\"run\"," +
    "\"compiled_plan_cid\":\"" +
    ordering_test_cid("1") +
    "\",\"invocation_template_cid\":\"" +
    template +
    "\",\"authorization_context_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"input_artifact_set_cid\":\"" +
    ordering_test_cid("3") +
    "\",\"created_at\":\"2026-09-18T00:00:00.000Z\"," +
    "\"valid_until\":\"2026-09-18T04:00:00.000Z\"}",
    8192,
    64,
    5,
  ).unwrap()
}

///|
fn manifest_test_invocation(template : String) -> PublicationContract {
  seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    template +
    "\",\"observation_set_cid\":\"" +
    ordering_test_cid("4") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
}

///|
fn manifest_test_retention(policy : String) -> PublicationContract {
  seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2026-09-18T01:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T02:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T03:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    ordering_test_cid("6") +
    "\",\"clock_contract_cid\":\"" +
    ordering_test_cid("7") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
}

///|
fn manifest_test_result(
  name : String,
  logical : String,
  invocation : PublicationContract,
  retention : PublicationContract,
  policy : String,
) -> (PublicationContract, ResultOrderingEvidence, PublicationContract) {
  let definition = result_definition_contract(
    prepare_result_definition(ordering_test_cid("8"), name).unwrap(),
  )
  let evidence = issue_result_occurrence_evidence(
    definition,
    ordering_test_cid("9"),
    logical,
    ordering_test_cid("a"),
    [],
    ordering_test_cid("b"),
    policy,
    "actql-common-host",
    ordering_test_cid("c"),
    16384,
    128,
    8,
  ).unwrap()
  let artifact = issue_complete_result_artifact(
    definition, invocation, evidence, retention, 2, 32768, 256, 8,
  ).unwrap()
  (definition, evidence, artifact)
}

///|
test "Result Manifest issuer fixes every declared Result in name order" {
  let template = ordering_test_cid("d")
  let run = manifest_test_run(template)
  let invocation = manifest_test_invocation(template)
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let (zeta_definition, zeta_evidence, zeta_artifact) = manifest_test_result(
    "zeta", ordering_test_cid("f"), invocation, retention, policy,
  )
  let (answer_definition, answer_evidence, answer_artifact) = manifest_test_result(
    "answer", ordering_test_cid("0"), invocation, retention, policy,
  )
  let manifest = issue_result_manifest(
    run,
    invocation,
    [zeta_definition, answer_definition],
    [zeta_artifact, answer_artifact],
    65536,
    1024,
    12,
  ).unwrap()
  let expected = "{\"invocation_cid\":\"" +
    publication_contract_identity(invocation) +
    "\",\"result_manifest_cid\":\"" +
    publication_contract_identity(manifest) +
    "\",\"results\":{\"answer\":" +
    publication_contract_json(answer_artifact) +
    ",\"zeta\":" +
    publication_contract_json(zeta_artifact) +
    "},\"run_definition_cid\":\"" +
    publication_contract_identity(run) +
    "\",\"version\":\"actql-result-manifest/0.1\"}"
  assert_eq(publication_contract_json(manifest), expected)
  assert_eq(
    validate_result_evidence_set(
      [zeta_definition, answer_definition],
      [zeta_artifact, answer_artifact],
      [
        result_ordering_derivation_contract(zeta_evidence),
        result_ordering_derivation_contract(answer_evidence),
      ],
      [
        result_ordering_evidence_contract(zeta_evidence),
        result_ordering_evidence_contract(answer_evidence),
      ],
      [retention],
    ),
    Ok(()),
  )
}

///|
test "Result Manifest issuer rejects incomplete or foreign inventories" {
  let template = ordering_test_cid("d")
  let run = manifest_test_run(template)
  let invocation = manifest_test_invocation(template)
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let (first_definition, _, first_artifact) = manifest_test_result(
    "first", ordering_test_cid("f"), invocation, retention, policy,
  )
  let (second_definition, _, second_artifact) = manifest_test_result(
    "second", ordering_test_cid("0"), invocation, retention, policy,
  )
  assert_true(
    issue_result_manifest(
      run,
      invocation,
      [first_definition, second_definition],
      [first_artifact],
      65536,
      1024,
      12,
    )
    is Err(ManifestIssuanceInventoryMismatch),
  )
  assert_true(
    issue_result_manifest(
      run,
      invocation,
      [first_definition, second_definition],
      [first_artifact, first_artifact],
      65536,
      1024,
      12,
    )
    is Err(ManifestIssuanceInventoryMismatch),
  )
  let foreign_invocation = manifest_test_invocation(ordering_test_cid("c"))
  assert_true(
    issue_result_manifest(
      run,
      foreign_invocation,
      [first_definition, second_definition],
      [first_artifact, second_artifact],
      65536,
      1024,
      12,
    )
    is Err(ManifestIssuanceChain(ChainInvocationTemplateMismatch)),
  )
}
