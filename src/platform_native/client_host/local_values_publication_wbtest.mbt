///|
// Matching Native compilation only until a separately allocated physical gate.
fn local_values_publication_context_fixture() -> (
  @host.ClientRequestIdentity,
  @host.ClientCompiledRun,
  @publication.PublicationContract,
  @native_publication.NativeCapturedResultPublicationContext,
  @native_publication.NativeRunPublicationIntent,
) {
  let (request, _, compiled, definition) = journal_test_run(
    "values-publication", "values-publication-run",
  )
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let result : @native_publication.NativeCapturedResultPublicationContext = {
    retention: @publication.seal_publication_contract(
      "result_retention_policy",
      "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
      policy +
      "\",\"effective_data_policy_cid\":\"" +
      policy +
      "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-02T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
      policy +
      "\",\"metadata_delete_by\":\"2099-01-03T00:00:00.000Z\",\"clock_contract_cid\":\"" +
      policy +
      "\"}",
      65536,
      8192,
      64,
    ).unwrap(),
    computation_contract_cid: @publication.publication_contract_identity(
      @host.client_compiled_run_plan(compiled),
    ),
    input_relation_cids: [],
    scope_cid: @publication.publication_contract_identity(definition),
    effective_data_policy_cid: policy,
    store_authority_cid: "sha256:" + "c".repeat(64),
    material_generation_cid: "sha256:" + "d".repeat(64),
    max_payload_bytes: 65536L,
  }
  let intent : @native_publication.NativeRunPublicationIntent = {
    namespace_id: "local-test",
    authority_scope_cid: @host.client_request_authority_scope_cid(request),
    publication_policy_cid: "sha256:" + "b".repeat(64),
    publication_target_cid: result.store_authority_cid,
    requested_at: "2026-10-12T00:00:00.000Z",
  }
  (request, compiled, definition, result, intent)
}

///|
test "Native Values publication binds the original plan Run policy and complete Result count" {
  let (request, compiled, definition, result, intent) = local_values_publication_context_fixture()
  assert_true(
    local_values_publication_context_matches(
      compiled,
      definition,
      request,
      result.effective_data_policy_cid,
      [result],
      intent,
    ),
  )
  for results in [[], [result, result]] {
    assert_false(
      local_values_publication_context_matches(
        compiled,
        definition,
        request,
        result.effective_data_policy_cid,
        results,
        intent,
      ),
    )
  }
}

///|
test "Native Values publication refuses a fabricated external input and replacement policy" {
  let (request, compiled, definition, result, intent) = local_values_publication_context_fixture()
  for
    foreign in [
      { ..result, input_relation_cids: ["sha256:" + "f".repeat(64)], },
      { ..result, effective_data_policy_cid: "sha256:" + "f".repeat(64), },
    ] {
    assert_false(
      local_values_publication_context_matches(
        compiled,
        definition,
        request,
        result.effective_data_policy_cid,
        [foreign],
        intent,
      ),
    )
  }
}

///|
test "Native Values publication refuses foreign Run plan and authority scope" {
  let (request, compiled, definition, result, intent) = local_values_publication_context_fixture()
  for
    foreign in [
      { ..result, scope_cid: "sha256:" + "f".repeat(64), },
      { ..result, computation_contract_cid: "sha256:" + "f".repeat(64), },
    ] {
    assert_false(
      local_values_publication_context_matches(
        compiled,
        definition,
        request,
        result.effective_data_policy_cid,
        [foreign],
        intent,
      ),
    )
  }
  assert_false(
    local_values_publication_context_matches(
      compiled,
      definition,
      request,
      result.effective_data_policy_cid,
      [result],
      { ..intent, authority_scope_cid: "sha256:" + "f".repeat(64), },
    ),
  )
}

///|
test "Native Values original policy is required rather than synthesized" {
  let (_, prepared, compiled, _) = journal_test_run(
    "values-policy-missing", "values-policy-missing-run",
  )
  assert_true(
    run_policy_originals_wire(prepared, compiled~)
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
}

///|
test "Native Values original policy roundtrips the exact admitted body" {
  let (_, prepared, compiled, _) = journal_test_run(
    "values-policy-original", "values-policy-original-run",
  )
  let cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let body = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let compiled = @host.with_client_source_free_result_policy(
    compiled, cid, body, 65536, 8192, 64,
  ).unwrap()
  let original = run_policy_originals_wire(prepared, compiled~).unwrap()
  let restored = read_run_policy_originals(original).unwrap()
  assert_eq(restored.length(), 1)
  assert_eq(@publication.captured_effect_dependency_body_cid(restored[0]), cid)
  assert_eq(
    @publication.captured_effect_dependency_body_json(restored[0]),
    body,
  )
  assert_eq(run_policy_originals_wire(prepared, compiled~).unwrap(), original)
}

///|
test "Native Values original packet refuses foreign physical preparation" {
  let (_, prepared, _, _) = journal_test_run(
    "values-policy-one", "values-policy-one-run",
  )
  let (_, _, other, _) = journal_test_run(
    "values-policy-two", "values-policy-two-run",
  )
  assert_true(
    run_policy_originals_wire(prepared, compiled=other) is Err(ForeignRun),
  )
}
