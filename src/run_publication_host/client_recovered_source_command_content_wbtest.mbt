///|
// Real checked ContentRef Source, compiler, Request and existing original
// Ledger. This fixture supplies no provider ACK or physical Store authority.
fn recovered_source_original_fixture() -> ClientEffectKeyedOriginal raise {
  let (prepared, keyed, _) = generic_file_effect_fixture(installed_rows=true)
  let measured = measure_client_effect_generic_keyed_plan_construction(
    prepared,
    keyed,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let graph = issue_client_effect_keyed_plan_graph(
    measured, 1000000, 100000, 100,
  ).unwrap()
  let limits = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "source-only-scope", "source-only-original", "2026-11-15T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = client_effect_allowed_keyed_run(allowed, graph, definition).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "source-only-request",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 100,
    holdings: 100,
    transfer_bytes: 1000000L,
    retained_bytes: 1000000L,
    execution_bytes: 1000000L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 100000L, 100000L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 10, 10, 0,
  ).unwrap()
  let original = bind_client_effect_keyed_original(
    prepared, compilation, compiled, definition, request, graph, keyed, ledger, identity,
  ).unwrap()
  original
}

///|
fn recovered_source_binding_wire(
  original : ClientEffectKeyedOriginal,
) -> String {
  let facts = client_keyed_acquisition_source_evidence_facts(original.keyed).unwrap()
  let binding : Json = {
    "content_store_id": "source-store",
    "content_store_cid": "sha256:" + "1".repeat(64),
    "workspace_scope_cid": "sha256:" + "2".repeat(64),
    "storage_scope": "run",
    "retention_class": "run-content",
    "expires_at": "2099-01-01T00:00:00.000Z",
    "availability_evidence_cid": "sha256:" + "3".repeat(64),
    "effective_data_policy_cid": facts.source_data_policy_cid,
    "data_classification": facts.data_classification,
    "issuer_contract_cid": "sha256:" + "4".repeat(64),
    "capture_authority_cid": "sha256:" + "5".repeat(64),
  }
  binding.stringify()
}

///|
fn recovered_source_reference_limits() -> @values.ReferenceLimits {
  { max_bytes: 16384, max_nodes: 512, max_depth: 16, max_text_units: 8192, }
}

///|
fn recovered_source_reference_wire(
  original : ClientEffectKeyedOriginal,
) -> String {
  let limits = recovered_source_reference_limits()
  let binding = @publication.parse_content_reference_binding(
    recovered_source_binding_wire(original),
    limits,
  ).unwrap()
  let candidate = @publication.prepare_captured_content_reference(
    binding,
    "Application/Octet-Stream",
    "sha256:" + "6".repeat(64),
    3113,
    limits,
  ).unwrap()
  @publication.captured_content_reference_wire(candidate)
}

///|
test "recovered Source candidate uses actual keyed original and preserves policy lifetime and original wire" {
  let original = recovered_source_original_fixture()
  let limits = recovered_source_reference_limits()
  let wire = recovered_source_reference_wire(original)
  let binding = recovered_source_binding_wire(original)
  let facts = client_effect_keyed_original_source_evidence_facts(
    original,
    original.prepared,
    original.request,
  ).unwrap()
  assert_eq(facts.length(), 6)
  assert_eq(
    facts,
    @planning.query_source_evidence_fact_values(
      client_keyed_acquisition_source_evidence_facts(original.keyed).unwrap(),
    ),
  )
  let restored = prepare_client_recovered_source_content_candidate(
    original,
    original.prepared,
    original.request,
    wire,
    binding,
    limits,
  ).unwrap()
  assert_true(recovered_source_candidate_matches(original, restored))
  assert_eq(client_captured_content_wire(restored), wire)
  assert_eq(client_captured_content_storage(restored).3, 3113)
  assert_eq(
    @publication.recovered_content_issuer_kind(wire, limits),
    Ok("connector_capture"),
  )
  let available = Ref(true)
  let issuer = @values.bind_reference_issuer((_, actual) => actual == wire, _ => {
    available.val
  })
  let content = issue_client_captured_content(restored, issuer, limits).unwrap()
  guard content.value is @values.Reference(reference) else {
    fail("issued reference")
  }
  assert_true(@values.reference_available(reference))
  available.val = false
  assert_false(@values.reference_available(reference))
  assert_true(
    @resources.finish_original_ledger_inventory(original.ledger, true).unwrap(),
  )
  assert_false(client_effect_keyed_original_current(original))
  assert_true(
    prepare_client_recovered_source_content_candidate(
      original,
      original.prepared,
      original.request,
      wire,
      binding,
      limits,
    )
    is Err(InvalidBinding("source_original")),
  )
  assert_eq(
    @resources.ledger_usage(original.ledger).reserved_retention_bytes,
    0L,
  )
}

///|
test "recovered Source candidate refuses copied Request foreign Source changed wire policy and lifetime" {
  let original = recovered_source_original_fixture()
  let foreign = recovered_source_original_fixture()
  let limits = recovered_source_reference_limits()
  let wire = recovered_source_reference_wire(original)
  let binding = recovered_source_binding_wire(original)
  let copied_request = prepare_client_effect_request_identity(
    original.prepared,
    "sha256:" + "c".repeat(64),
    "source-only-request",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  assert_false(physical_equal(original.request, copied_request))
  assert_eq(
    client_request_identity_relation(original.request, copied_request),
    SameRequest,
  )
  assert_true(
    prepare_client_recovered_source_content_candidate(
      original,
      original.prepared,
      copied_request,
      wire,
      binding,
      limits,
    )
    is Err(InvalidBinding("source_original")),
  )
  assert_true(
    client_effect_keyed_original_source_evidence_facts(
      original,
      foreign.prepared,
      original.request,
    )
    is Err(ForeignInput),
  )
  let restored = prepare_client_recovered_source_content_candidate(
    original,
    original.prepared,
    original.request,
    wire,
    binding,
    limits,
  ).unwrap()
  assert_false(recovered_source_candidate_matches(foreign, restored))
  for
    changed in [
      wire.replace(old="3113", new="3114"),
      wire.replace(old="connector_capture", new="content_derivation"),
      wire + " ",
    ] {
    assert_true(
      prepare_client_recovered_source_content_candidate(
        original,
        original.prepared,
        original.request,
        changed,
        binding,
        limits,
      )
      is Err(_),
    )
    assert_true(
      @publication.recovered_content_issuer_kind(changed, limits) is Err(_),
    )
  }
  assert_true(
    prepare_client_recovered_source_content_candidate(
      original,
      original.prepared,
      original.request,
      wire,
      binding.replace(old="2099-01-01", new="2098-01-01"),
      limits,
    )
    is Err(InvalidBinding("source_run_lifetime")),
  )
  assert_true(
    prepare_client_recovered_source_content_candidate(
      original,
      original.prepared,
      original.request,
      wire,
      binding.replace(old="internal", new="public"),
      limits,
    )
    is Err(InvalidBinding("source_policy")),
  )
  for value in [original, foreign] {
    assert_true(
      @resources.finish_original_ledger_inventory(value.ledger, true).unwrap(),
    )
    assert_false(client_effect_keyed_original_current(value))
  }
}

///|
test "Source constructor quotes retain only their live role and preserve complete parser workspace" {
  let original = recovered_source_original_fixture()
  let limits = recovered_source_reference_limits()
  let wire = recovered_source_reference_wire(original)
  let binding = recovered_source_binding_wire(original)
  let view = recovered_source_content_construction_capacity(
    wire, binding, limits, "view",
  ).unwrap()
  let classify = recovered_source_content_construction_capacity(
    wire, "", limits, "classify",
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(view), 192L)
  assert_eq(@execution.execution_capacity_retained_bytes(classify), 0L)
  for
    role in [
      "metadata", "candidate", "holding", "inspect", "issuer", "issue", "view", "classify",
    ] {
    let quote = recovered_source_content_construction_capacity(
      wire, binding, limits, role,
    ).unwrap()
    assert_true(
      @execution.execution_capacity_execution_bytes(quote) >
      @execution.execution_capacity_retained_bytes(quote),
    )
    let larger_policy = { ..limits, max_bytes: 1048576, max_nodes: 100000, }
    let same = recovered_source_content_construction_capacity(
      wire, binding, larger_policy, role,
    ).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(quote),
      @execution.execution_capacity_retained_bytes(same),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(quote),
      @execution.execution_capacity_execution_bytes(same),
    )
  }
  let metadata = recovered_source_content_construction_capacity(
    wire, "", limits, "metadata",
  ).unwrap()
  let full_metadata = recovered_source_content_construction_capacity(
    wire, binding, limits, "metadata",
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(full_metadata) >
    @execution.execution_capacity_retained_bytes(metadata),
  )
  assert_true(
    recovered_source_content_construction_capacity(
      wire, binding, limits, "unknown",
    )
    is None,
  )
  assert_true(
    recovered_source_content_construction_capacity(
      wire,
      binding,
      { ..limits, max_bytes: wire.length() - 1, },
      "view",
    )
    is None,
  )
  assert_true(
    recovered_source_content_construction_capacity(
      wire,
      binding,
      { ..limits, max_depth: 0, },
      "view",
    )
    is None,
  )
  assert_true(
    prepare_client_recovered_source_content_candidate(
      original,
      original.prepared,
      original.request,
      wire,
      binding,
      { ..limits, max_nodes: 1, },
    )
    is Err(_),
  )
  assert_true(
    @resources.finish_original_ledger_inventory(original.ledger, true).unwrap(),
  )
}
