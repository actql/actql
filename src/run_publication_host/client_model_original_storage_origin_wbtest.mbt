///|
fn client_original_storage_test_body() -> String {
  (
    // Independent selected-Store preimage from the fixed physical issuer unit.
    // Sealing this fixture is DATA admission, never an actual Store observation.
    #|{"key_generation_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","private_namespace":"local-continuation-private","store_authority_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","store_contract_cid":"sha256:247d00ffcfddef53c9631b096e4ee3dfd37e2f83a035e0bcf6f7559b852476df","store_contract_wire":"{\"version\":\"actql-local-publication-store/0.1\",\"isolation\":\"execution-namespace\",\"store_authority_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"}","version":"actql-model-original-storage-binding/0.1"}
  )
}

///|
fn client_original_storage_test_document(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout,
) -> @publication.ModelOriginalResourceDocument {
  let wire = client_original_origin_test_wire(
    compiled, definition, plan, layout,
  ).replace(
    old="\"storage_binding_cid\":\"sha256:" + "b".repeat(64) + "\"",
    new="\"storage_binding_cid\":\"sha256:78c803436a1ff3cb68ebd954f539a2353049544615e942931d7aa0ab6839e2a3\"",
  )
  @publication.read_model_original_resource_document(wire, 10000, 1000, 16).unwrap()
}

///|
test "original storage origin checks the twelfth independent binding without resource mutation" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let layout = client_node_layout_test_declaration(plan)
  let document = client_original_storage_test_document(
    compiled, definition, plan, layout,
  )
  let storage = @publication.seal_run_evidence_value(
    "model_original_storage_binding",
    client_original_storage_test_body(),
    2048,
    32,
    2,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(storage),
    "sha256:78c803436a1ff3cb68ebd954f539a2353049544615e942931d7aa0ab6839e2a3",
  )
  let before = @resources.ledger_usage(ledger)
  let check = fn(value) {
    check_client_model_original_storage_origin(
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
      value,
    )
  }
  assert_true(check(storage) is Ok(_))
  // A value-admitted copy also matches this data guard. The physical port's
  // exact-handle check is essential and cannot be replaced by this result.
  let copied = @publication.admit_run_evidence_value(
    "model_original_storage_binding",
    @publication.run_evidence_value_json(storage),
    2048,
    32,
    2,
  ).unwrap()
  assert_true(check(copied) is Ok(_))
  assert_true(
    check(@publication.run_publication_prepared(compiled.admission))
    is Err(OriginMismatch("storage_binding_cid")),
  )
  let changed_key = @publication.seal_run_evidence_value(
    "model_original_storage_binding",
    client_original_storage_test_body().replace(
      old="\"key_generation_cid\":\"sha256:" + "2".repeat(64) + "\"",
      new="\"key_generation_cid\":\"sha256:" + "3".repeat(64) + "\"",
    ),
    2048,
    32,
    2,
  ).unwrap()
  assert_true(check(changed_key) is Err(OriginMismatch("storage_binding_cid")))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "original storage origin cannot bypass original Run or pending cleanup" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let layout = client_node_layout_test_declaration(plan)
  let document = client_original_storage_test_document(
    compiled, definition, plan, layout,
  )
  let storage = @publication.seal_run_evidence_value(
    "model_original_storage_binding",
    client_original_storage_test_body(),
    2048,
    32,
    2,
  ).unwrap()
  let (_, other_definition, _) = client_model_read_test_run("storage-foreign")
  assert_true(
    check_client_model_original_storage_origin(
      scope,
      compiled,
      other_definition,
      plan,
      document,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
      storage,
    )
    is Err(ForeignRun),
  )
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, false).unwrap(),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    check_client_model_original_storage_origin(
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
      storage,
    )
    is Err(Unavailable),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(before.reserved_retention_bytes, 10L)
  assert_eq(before.reserved_execution_bytes, 7L)
  settle_client_model_read(read, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}
