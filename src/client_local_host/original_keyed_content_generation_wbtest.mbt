///|
// A trusted in-memory physical byte fixture exercises the existing family.
// This supplies neither an actual encrypted Store ACK nor a normal profile.
fn original_keyed_version_content(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  lookup : @publication_host.ClientOriginalKeyedPrefixLookup,
  left_prefix : ClientOriginalKeyedPrefixInput,
  acquisition : @row_source_host.RowAcquisition,
  capture : @row_source_host.RowSourceCapture,
  requirement : @planning.QueryRequirement,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  typed_content? : Bool = false,
  same_ledger_consumer? : Bool = false,
  one_short_census? : Bool = false,
) -> Unit raise {
  let source_contracts = prepare_installed_sequence_contracts(source_query_original_registry, source_query_original_values, Some(source_query_original_fragment), None).unwrap()
  let selected : Array[ClientLocalContentStep] = []
  let clean = Ref(false)
  let closes = Ref(0)
  let suffix = start_client_original_keyed_content_suffix(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    lookup,
    keyed,
    0,
    7,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
    original_keyed_content_workspace(),
    {
      cancel: () => true,
      stopped: () => true,
      cleanup: () => {
        closes.val += 1
        Ok(clean.val)
      },
    },
    active => {
      selected.push(active)
      true
    },
  ).unwrap()
  let bytes = StringBuilder()
  let mut ready = false
  for _ in 0..<100000 {
    match advance_client_serialization_prefix(suffix, 7).unwrap() {
      @local.Continue(..) => ()
      @local.Settling(0, ..) => {
        assert_eq(selected.length(), 1)
        let active = selected[0]
        let (revision, piece) = client_local_content_pending_piece(active).unwrap()
        // An unchanged pending piece waits without re-emission or fake ACK.
        let before = @resources.ledger_usage(ledger)
        assert_true(
          advance_client_serialization_prefix(suffix, 7).unwrap()
          is @local.Settling(0, work=0L, ..),
        )
        assert_eq(
          client_local_content_pending_piece(active),
          Some((revision, piece)),
        )
        assert_eq(@resources.ledger_usage(ledger), before)
        bytes.write_string(piece)
        assert_false(
          acknowledge_client_local_content_piece(active, revision - 1),
        )
        assert_true(acknowledge_client_local_content_piece(active, revision))
        assert_false(acknowledge_client_local_content_piece(active, revision))
      }
      @local.Settling(1, ..) => {
        ready = true
        break
      }
      _ =>
        fail(
          "original Content family completed without byte custody/generation",
        )
    }
  }
  assert_true(ready)
  assert_eq(selected.length(), 1)
  let active = selected[0]
  assert_eq(bytes.to_string(), original_keyed_serialized_expected())
  let completion = client_local_content_byte_completion(active).unwrap()
  assert_eq((completion.row_count, completion.size_bytes), (3, 4470))
  assert_eq(
    completion.content_cid,
    "sha256:825b743cf65a3b85fd1220c1bfd6ec9b5c07389479d26df31b32ab31ecb354cd",
  )
  assert_true(client_local_content_step_generation(active) is None)
  assert_true(
    advance_client_serialization_prefix(suffix, 7).unwrap()
    is @local.Settling(1, ..),
  )
  assert_false(cleanup_client_serialization_prefix(suffix).unwrap())
  assert_false(
    @publication_host.cleanup_client_original_keyed_prefix_lookup(lookup, 1).unwrap(),
  )
  let (input, receipt, encoder) = client_local_content_generation_input(active).unwrap()
  assert_eq(
    @execution.completed_relation_export_measurement(receipt).row_count,
    3,
  )
  // Source evidence is issued from the actual accounted capture, not a copied
  // row/CID. Keyed observation retains both exact version captures and aliases.
  let workspace = original_keyed_content_workspace()
  let limits = workspace.export_limits
  let source = @row_source_host.row_capture_source(capture).unwrap()
  let identity = @query.identify_captured_source_relation(
    source,
    3,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let logical = @publication_host.issue_captured_source_input_logical(
    @publication_host.prepared_client_graph(prepared),
    source,
    identity,
    requirement,
  ).unwrap()
  let authority = "sha256:" + "2".repeat(64)
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let policy_cid = @planning.query_source_evidence_fact_values(facts)[3]
  let observation = @row_source_host.issue_row_source_evidence(
    acquisition, capture, identity, logical, authority, policy_cid, "2026-10-13T00:00:01.000Z",
  ).unwrap()
  let actual = @publication_host.client_original_keyed_prefix_lookup_input(
    lookup,
  ).unwrap()
  let right = @publication_host.issue_client_keyed_lookup_observation(
    actual, authority, "2026-10-13T00:00:01.000Z",
  ).unwrap()
  let component = @publication_host.client_compiled_run_serialization(compiled).unwrap()
  let captured = @publication_host.admit_client_keyed_serialization_captured_input(
    prepared, component, source, identity, requirement, logical, observation, right,
    authority, "2026-10-13T00:00:00.000Z", "2026-10-13T00:00:01.000Z",
  ).unwrap()
  assert_true(
    @publication_host.bind_client_serialization_input_identity(
      compiled, input, receipt, 16384, 256, 16,
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_input_artifact")),
  )
  let evidence = @publication_host.bind_client_acquired_serialization_input_identity(
    compiled, input, receipt, captured, 16384, 256, 16,
  ).unwrap()
  let reference_limits : @admitted.ReferenceLimits = {
    max_bytes: 16384,
    max_nodes: 256,
    max_depth: 32,
    max_text_units: 16384,
  }
  let candidate = @publication.prepare_generated_content_reference(
    encoder,
    {
      content_store_id: "original-memory-fixture",
      content_store_cid: "sha256:" + "1".repeat(64),
      workspace_scope_cid: authority,
      storage_scope: "workspace",
      retention_class: "fixture",
      expires_at: None,
      availability_evidence_cid: "sha256:" + "3".repeat(64),
      effective_data_policy_cid: @publication.captured_effect_dependency_body_cid(
        @publication_host.client_compiled_run_serialization_policy_body(
          compiled,
        ).unwrap(),
      ),
      data_classification: "unknown",
      issuer_contract_cid: "sha256:" + "5".repeat(64),
      capture_authority_cid: authority,
    },
    reference_limits,
  ).unwrap()
  // This fixture's actual bytes have now been verified. The separately held
  // byte allocation remains charged after the managed workspace retires.
  let holding = @resources.retain_allocation(ledger, suffix.reservation, 4470L).unwrap()
  let current = () => @resources.holding_available(ledger, holding)
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => {
      current() &&
      wire == @publication.generated_content_reference_wire(candidate)
    },
    _ => current(),
  )
  let reference = @publication.issue_generated_content_reference(
    candidate, issuer, reference_limits,
  ).unwrap()
  let generation = complete_client_local_content_step(
    active,
    compiled,
    definition,
    evidence,
    candidate,
    reference,
    current,
    limits.values,
    1000,
  ).unwrap()
  let mut output = None
  for _ in 0..<10 {
    match advance_client_serialization_prefix(suffix, 7).unwrap() {
      @local.Complete(value, ..) => {
        output = Some(value)
        break
      }
      @local.Continue(..) => ()
      _ => fail("issued Content generation did not complete the actual family")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 16384, 1000, 100).unwrap(),
    "{\"content\":" +
    @publication.generated_content_reference_wire(candidate) +
    ",\"media_type\":\"application/x-ndjson\",\"name\":\"captured.jsonl\",\"row_count\":3,\"size_bytes\":4470}",
  )
  assert_true(
    @publication_host.client_serialization_generation_output_for(
      generation, compiled,
    )
    is Some(_),
  )
  let originals = @publication_host.client_serialization_generation_source_observations_for(
    generation, compiled,
  ).unwrap()
  assert_eq(originals.map(item => item.0), ["files", "contents"])
  if typed_content {
    original_keyed_typed_content_input(
      compiled,
      plan,
      generation,
      execution,
      measurement,
      original=if same_ledger_consumer {
        Some((scope, definition, ledger))
      } else {
        None
      },
      one_short_census~,
    )
  }
  let before = @resources.ledger_usage(ledger)
  assert_false(cleanup_client_serialization_prefix(suffix).unwrap())
  assert_eq(closes.val, 1)
  assert_eq(@resources.ledger_usage(ledger), before)
  clean.val = true
  assert_true(cleanup_client_serialization_prefix(suffix).unwrap())
  assert_eq(closes.val, 2)
  assert_true(cleanup_client_serialization_prefix(suffix).unwrap())
  assert_eq(closes.val, 2)
  assert_true(@resources.holding_available(ledger, holding))
  assert_true(
    @publication_host.client_serialization_generation_output_for(
      generation, compiled,
    )
    is Some(_),
  )
  assert_true(client_local_content_generation_input(active) is None)
  assert_true(
    active.bytes is None && active.generation is None && active.output is None,
  )
  assert_false(cleanup_client_original_keyed_prefix_input(left_prefix).unwrap())
  @resources.release_allocation(ledger, holding).unwrap()
  assert_true(
    @publication_host.client_serialization_generation_output_for(
      generation, compiled,
    )
    is None,
  )
  assert_true(
    @publication_host.client_serialization_generation_reference_for(
      generation, compiled,
    )
    is None,
  )
}
