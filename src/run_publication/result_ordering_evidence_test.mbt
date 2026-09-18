///|
fn ordering_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn ordering_test_definition() -> PublicationContract {
  result_definition_contract(
    prepare_result_definition(ordering_test_cid("1"), "result").unwrap(),
  )
}

///|
fn ordering_test_derivation(
  definition : PublicationContract,
  logical : String,
  schema : String,
  policy : String,
) -> PublicationContract {
  seal_publication_contract(
    "derivation_evidence",
    "{\"version\":\"actql-acquisition-derivation-evidence/0.1\"," +
    "\"producer_contract_cid\":\"" +
    publication_contract_identity(definition) +
    "\",\"computation_contract_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"input_relation_cids\":[],\"logical_value_cid\":\"" +
    logical +
    "\",\"relation_schema_cid\":\"" +
    schema +
    "\",\"scope_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"ordering\":{\"kind\":\"occurrence\",\"terms\":[]}," +
    "\"issuer_id\":\"common-host\",\"authority_scope_cid\":\"" +
    ordering_test_cid("6") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
}

///|
fn ordering_test_ordering(
  definition : PublicationContract,
  derivation : PublicationContract,
) -> PublicationContract {
  seal_publication_contract(
    "ordering_evidence",
    "{\"version\":\"actql-acquisition-ordering/0.1\"," +
    "\"producer_contract_cid\":\"" +
    publication_contract_identity(definition) +
    "\",\"kind\":\"occurrence\",\"terms\":[]," +
    "\"witness_evidence\":[{\"kind\":\"derivation\",\"cid\":\"" +
    publication_contract_identity(derivation) +
    "\"}]}",
    8192,
    64,
    5,
  ).unwrap()
}

///|
test "Result ordering requires its exact admitted derivation witness" {
  let definition = ordering_test_definition()
  let logical = ordering_test_cid("3")
  let schema = ordering_test_cid("4")
  let policy = ordering_test_cid("7")
  let derivation = ordering_test_derivation(definition, logical, schema, policy)
  let ordering = ordering_test_ordering(definition, derivation)
  let evidence = validate_result_occurrence_ordering_evidence(
    definition, derivation, ordering, logical, schema, policy,
  ).unwrap()
  assert_eq(
    result_ordering_evidence_cid(evidence),
    publication_contract_identity(ordering),
  )
  assert_eq(
    result_ordering_derivation_cid(evidence),
    publication_contract_identity(derivation),
  )
  assert_true(
    validate_result_occurrence_ordering_evidence(
      definition,
      derivation,
      ordering,
      ordering_test_cid("8"),
      schema,
      policy,
    )
    is Err(LogicalValueMismatch),
  )
  let retention = seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    ordering_test_cid("8") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2026-09-18T01:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T02:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T03:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    ordering_test_cid("9") +
    "\",\"clock_contract_cid\":\"" +
    ordering_test_cid("a") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
  let artifact = seal_publication_contract(
    "result_artifact",
    "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    publication_contract_identity(definition) +
    "\",\"invocation_cid\":\"" +
    ordering_test_cid("b") +
    "\",\"logical_result_cid\":\"" +
    logical +
    "\",\"result_schema_cid\":\"" +
    schema +
    "\",\"ordering_evidence_cid\":\"" +
    result_ordering_evidence_cid(evidence) +
    "\",\"actual_row_count\":2,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"effective_retention_policy_cid\":\"" +
    publication_contract_identity(retention) +
    "\",\"provenance_evidence_cids\":[\"" +
    result_ordering_derivation_cid(evidence) +
    "\"]}",
    16384,
    128,
    5,
  ).unwrap()
  assert_eq(
    validate_result_artifact_evidence(definition, artifact, evidence, retention),
    Ok(()),
  )
}

///|
test "ordering contracts reject unsupported or noncanonical witnesses" {
  assert_true(
    seal_publication_contract(
      "ordering_evidence",
      "{\"version\":\"actql-acquisition-ordering/0.1\"," +
      "\"producer_contract_cid\":\"" +
      ordering_test_cid("1") +
      "\",\"kind\":\"occurrence\",\"terms\":[{" +
      "\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"last\"}]," +
      "\"witness_evidence\":[{\"kind\":\"derivation\",\"cid\":\"" +
      ordering_test_cid("2") +
      "\"}]}",
      8192,
      64,
      5,
    )
    is Err(ConditionalField("terms")),
  )
  assert_true(
    seal_publication_contract(
      "ordering_evidence",
      "{\"version\":\"actql-acquisition-ordering/0.1\"," +
      "\"producer_contract_cid\":\"" +
      ordering_test_cid("1") +
      "\",\"kind\":\"occurrence\",\"terms\":[]," +
      "\"witness_evidence\":[" +
      "{\"kind\":\"source\",\"cid\":\"" +
      ordering_test_cid("3") +
      "\"},{\"kind\":\"derivation\",\"cid\":\"" +
      ordering_test_cid("2") +
      "\"}]}",
      8192,
      64,
      5,
    )
    is Err(InvalidField("witness_evidence")),
  )
}
