///|
fn local_client_publication_cid(label : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(label))
}

///|
fn local_client_publication_context(
  work : @client.NativeClientSourceWork,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  logical : @publication.RunEvidenceValue,
  library : @sqlite.Library,
  store_root : String,
  change_source_authorization : (Bool) -> Unit,
  journal : @client.NativeClientRunJournal,
  race : Bool,
) -> @store.Store raise {
  let authority = local_client_publication_cid("native-client-original-store")
  let store = @store.open_store(
    library, store_root, authority, 128L, 8L, 1000000L,
  ).unwrap()
  let policy = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
    local_client_publication_cid("retention") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-02T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
    local_client_publication_cid("metadata-retention") +
    "\",\"metadata_delete_by\":\"2099-01-03T00:00:00.000Z\",\"clock_contract_cid\":\"" +
    local_client_publication_cid("clock") +
    "\"}",
    1000000,
    100000,
    100,
  ).unwrap()
  let logical_body = @json.parse(@publication.run_evidence_value_json(logical))
  guard logical_body is Object(logical_fields) &&
    logical_fields.get("logical_relation_cid") is Some(String(input)) else {
    fail("original source logical identity is missing")
  }
  let result : @native_publication.NativeCapturedResultPublicationContext = {
    retention,
    computation_contract_cid: @publication.publication_contract_identity(
      @host.client_compiled_run_plan(compiled),
    ),
    input_relation_cids: [input],
    scope_cid: @publication.publication_contract_identity(definition),
    effective_data_policy_cid: policy,
    store_authority_cid: authority,
    material_generation_cid: local_client_publication_cid(
      "original-result-generation",
    ),
    max_payload_bytes: 128L,
  }
  let normalization = @publication.seal_run_evidence_value(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\",\"rule_catalog_cid\":\"" +
    local_client_publication_cid("normalization-rules") +
    "\",\"entries\":[]}",
    1000000,
    100000,
    100,
  ).unwrap()
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"" +
    @host.client_request_program_cid(request) +
    "\",\"annotations\":[]}",
    1000000,
    100000,
    100,
  ).unwrap()
  let intent : @native_publication.NativeRunPublicationIntent = {
    namespace_id: "native-client-fixture",
    authority_scope_cid: @host.client_request_authority_scope_cid(request),
    publication_policy_cid: local_client_publication_cid("publication-policy"),
    publication_target_cid: authority,
    requested_at: "2026-10-10T00:00:03.000Z",
  }
  let occurrence : @native_publication.NativeRunPublicationOccurrence = {
    attempt_id: "original-publication-attempt",
    fence_cid: local_client_publication_cid("original-publication-fence"),
    external_idempotency_key: None,
    started_at: "2026-10-10T00:00:03.000Z",
    committed_at: "2026-10-10T00:00:04.000Z",
  }
  let allowed = Ref(true)
  let revoke_during_authorization = Ref(false)
  let service = work
    .install_publication_service(
      store,
      intent.namespace_id,
      fact => {
        if revoke_during_authorization.val {
          change_source_authorization(false)
        }
        allowed.val &&
        fact.authority_scope_cid == intent.authority_scope_cid &&
        fact.run_definition_cid == result.scope_cid &&
        fact.namespace_id == intent.namespace_id
      },
      1000000,
      100000,
      100,
    )
    .unwrap()
  // Independent binding mutations must be refused before payload allocation.
  for
    changed in [
      {
        ..result,
        effective_data_policy_cid: local_client_publication_cid(
          "replacement-policy",
        ),
      },
      {
        ..result,
        input_relation_cids: [local_client_publication_cid("replacement-input")],
      },
      {
        ..result,
        computation_contract_cid: local_client_publication_cid(
          "replacement-plan",
        ),
      },
      { ..result, scope_cid: local_client_publication_cid("replacement-run"), },
    ] {
    assert_true(
      work.prepare_publication(
        service,
        changed,
        normalization,
        authoring,
        intent,
        occurrence,
        resident_compute_limits(),
        1000000,
        100000,
        100,
      )
      is Err(@client.SourceBindingMismatch),
    )
  }
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 0L)
  revoke_during_authorization.val = true
  assert_true(
    work.prepare_publication(
      service,
      result,
      normalization,
      authoring,
      intent,
      occurrence,
      resident_compute_limits(),
      1000000,
      100000,
      100,
    )
    is Err(
      @client.Publication(
        @resident.Publication(
          @native_publication.Prepare(
            @native_publication.Publication(@native_publication.AccessDenied)
          )
        )
      )
    ),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  revoke_during_authorization.val = false
  change_source_authorization(true)
  let pending = work
    .prepare_publication(
      service,
      result,
      normalization,
      authoring,
      intent,
      occurrence,
      resident_compute_limits(),
      1000000,
      100000,
      100,
    )
    .unwrap()
  assert_true(
    store
    .inspect_committed_publication(
      intent.namespace_id,
      intent.authority_scope_cid,
      result.scope_cid,
      1000000,
      100000,
      100,
    )
    .unwrap()
    is None,
  )
  // Saved private payloads do not make publication authorization irrevocable.
  allowed.val = false
  assert_true(pending.commit() is Err(@native_publication.AccessDenied))
  allowed.val = true
  revoke_during_authorization.val = true
  assert_true(pending.commit() is Err(@native_publication.AccessDenied))
  revoke_during_authorization.val = false
  change_source_authorization(true)
  if race {
    guard journal.lookup(request, true) is Ok(@client.Retained(record)) else {
      fail("original Run missing before publication race")
    }
    let committed = Ref(false)
    let checks = Ref(0)
    let observer = @client.install_native_client_cancellation_publication(
      store,
      intent.namespace_id,
      1000000,
      100000,
      100,
    ).unwrap()
    let cancelled = journal
      .cancel_operation(
        request,
        intent.namespace_id,
        "publication-race-cancel",
        @client.native_client_run_record_revision(record).to_int(),
        () => {
          checks.val += 1
          if checks.val == 3 {
            // After the actual scoped Store lookup, before cancel persistence.
            // The concurrent publication must acquire the same physical fence.
            committed.val = pending.commit() is Ok(_)
          }
          true
        },
        observer,
      )
      .unwrap()
    assert_eq(checks.val, 3)
    assert_false(
      committed.val &&
      @client.native_client_cancellation_action(cancelled) ==
      @host.AcceptCancellation,
    )
    guard journal.lookup(request, true) is Ok(@client.Retained(after)) else {
      fail("original Run missing after publication race")
    }
    assert_true(
      @client.native_client_run_record_revision(after) >=
      @client.native_client_run_record_revision(record),
    )
    assert_true(pending.cancel().unwrap())
    return store
  }
  let committed = pending.commit().unwrap()
  assert_true(committed.committed)
  guard journal.lookup(request, true) is Ok(@client.Retained(original_run)) else {
    fail("original published Run missing")
  }
  assert_true(
    journal.cancel_operation(
      request,
      intent.namespace_id,
      "wrong-publication-namespace",
      @client.native_client_run_record_revision(original_run).to_int(),
      () => true,
      @client.install_native_client_cancellation_publication(
        store, "foreign-publication-namespace", 1000000, 100000, 100,
      ).unwrap(),
    )
    is Err(@client.ChangedIntent),
  )
  let foreign_root = @filesystem.open_root(store_root).unwrap()
  foreign_root.create_directory("foreign-store").unwrap() |> ignore
  let foreign_store = @store.open_store(
    library,
    store_root + "/foreign-store",
    authority,
    128L,
    8L,
    1000000L,
  ).unwrap()
  assert_true(
    journal.cancel_operation(
      request,
      intent.namespace_id,
      "wrong-publication-store",
      @client.native_client_run_record_revision(original_run).to_int(),
      () => true,
      @client.install_native_client_cancellation_publication(
        foreign_store,
        intent.namespace_id,
        1000000,
        100000,
        100,
      ).unwrap(),
    )
    is Err(@client.ChangedIntent),
  )
  assert_eq(foreign_store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(foreign_store.close().unwrap())
  let terminal = journal
    .cancel_operation(
      request,
      intent.namespace_id,
      "after-original-publication",
      @client.native_client_run_record_revision(original_run).to_int(),
      () => true,
      @client.install_native_client_cancellation_publication(
        store,
        intent.namespace_id,
        1000000,
        100000,
        100,
      ).unwrap(),
    )
    .unwrap()
  assert_eq(
    @client.native_client_cancellation_action(terminal),
    @host.AlreadyTerminal,
  )
  assert_eq(
    @client.native_client_cancellation_revision(terminal),
    @client.native_client_run_record_revision(original_run),
  )
  assert_eq(
    pending.commit().unwrap().publication_attempt_cid,
    committed.publication_attempt_cid,
  )
  assert_true(pending.cancel() is Err(@native_publication.PublicationCommitted))
  store
}

///|
fn local_client_read_committed_result(
  store : @store.Store,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  attempt : String,
) -> Unit raise {
  let resolved = store
    .resolve_committed_result(
      "native-client-fixture",
      @host.client_request_authority_scope_cid(request),
      @publication.publication_contract_identity(definition),
      "answer",
      1000000,
      100000,
      100,
    )
    .unwrap()
  guard resolved is Some(resolved) else {
    fail("original Named Result was not published")
  }
  let grant = @publication.issue_result_read_grant(
    resolved.public_index_entry,
    resolved.result_manifest,
    ["answer"],
    ["jsonl"],
    "fixture-principal",
    "inspect",
    local_client_publication_cid(attempt + "-ceiling"),
    128,
    1,
    "2099-01-01T00:00:00.000Z",
    local_client_publication_cid("fixture-current-read-authority"),
    local_client_publication_cid("fixture-current-read-egress"),
    1000000,
    100000,
    100,
  ).unwrap()
  // The original immutable binding supplies the physical identity, schema and
  // fields; the expectation is independently fixed for the authored Program.
  let binding = @publication.project_durable_result_binding_read(
    resolved.binding,
  ).unwrap()
  let delivery = match
    store.begin_result_delivery(
      resolved.public_index_entry,
      resolved.result_manifest,
      grant,
      resolved.retention,
      resolved.binding,
      binding.material_generation_cid,
      "answer",
      "jsonl",
      attempt,
      "2026-10-10T00:00:05.000Z",
      "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
      ["id"],
      3,
      128,
      1000000,
      100000,
      16,
      128L,
    ) {
    Ok(value) => value
    Err(@store.DeliveryIssuance(issue)) =>
      fail("original Result delivery binding: " + @debug.to_string(issue))
    Err(@store.Delivery(issue)) =>
      fail("original Result serializer: " + @debug.to_string(issue))
    Err(@store.RowFrame(issue)) =>
      fail("original Result row framing: " + @debug.to_string(issue))
    Err(@store.DeliveryLimit) =>
      fail("original Result delivery admission limit")
    Err(@store.StateCollision) =>
      fail("original Result delivery custody collision")
    Err(_) => fail("original Result delivery physical owner refusal")
  }
  let bytes : Array[Byte] = []
  while true {
    let chunk = delivery.next(3, "2026-10-10T00:00:06.000Z").unwrap()
    for byte in chunk.bytes {
      bytes.push(byte)
    }
    if chunk.bytes.length() > 0 {
      delivery.confirm_chunk().unwrap() |> ignore
    }
    if chunk.eof {
      break
    }
  }
  let complete = delivery
    .confirm_sink_finished("2026-10-10T00:00:07.000Z")
    .unwrap()
  assert_eq(@utf8.decode(Bytes::from_array(bytes)), "{\"id\":3}\n")
  assert_eq(complete.confirmed_bytes, 9L)
  assert_eq(complete.delivered_sha256, @sha.text_hex("{\"id\":3}\n").unwrap())
  // The physical lookup key is the original caller attempt ID. The formal
  // attempt CID is its contract identity, not a replacement lookup operation.
  assert_true(
    store.inspect_result_delivery(delivery.attempt_cid())
    is Err(@store.Database(@sqlite.NotFound)),
  )
  assert_eq(
    store.inspect_result_delivery(attempt).unwrap().result_delivery_receipt_cid,
    Some(complete.result_delivery_receipt_cid),
  )
  delivery.close().unwrap()
}

///|
/// The already-published actual Source result reaches the same bounded sink
/// adapter used by Native CLI. This creates an explicit new read attempt,
/// not another Source/Compute operation or a replay of an old delivery grant.
fn local_client_read_result_sink(
  store : @store.Store,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  attempt : String,
) -> Unit raise {
  let authority = @access.install_native_result_access_authority(
    requested => {
      requested.run_definition_cid ==
      @publication.publication_contract_identity(definition) &&
      requested.authority_scope_cid ==
      @host.client_request_authority_scope_cid(request) &&
      requested.principal_id == "fixture-principal"
    },
    _ => {
      Some({
        authorization_context_cid: local_client_publication_cid(
          attempt + "-read-authority",
        ),
        data_ceiling_cid: local_client_publication_cid(attempt + "-ceiling"),
        egress_admission_cid: local_client_publication_cid(
          attempt + "-read-egress",
        ),
        expires_at: "2099-01-01T00:00:00.000Z",
        max_bytes: 128,
        max_uses: 1,
      })
    },
    _ => true,
  )
  let service = @access.install_native_result_access_service(
    store,
    authority,
    () => "2026-10-10T00:00:08.000Z",
    1000000,
    100000,
    100,
    128,
    3,
  ).unwrap()
  let session = @access.open_native_result_access(service, {
    namespace_id: "native-client-fixture",
    authority_scope_cid: @host.client_request_authority_scope_cid(request),
    run_definition_cid: @publication.publication_contract_identity(definition),
    principal_id: "fixture-principal",
    purpose: "inspect",
    result_name: "answer",
    format: "jsonl",
    attempt_id: attempt,
  }).unwrap()
  let output : Array[Byte] = []
  let finishes = Ref(0)
  let sink = @access.install_native_result_sink(
    session,
    3,
    9,
    bytes => {
      for byte in bytes {
        output.push(byte)
      }
      @access.SinkChunkConfirmed
    },
    () => {
      finishes.val += 1
      true
    },
  ).unwrap()
  let mut receipt = None
  for _ in 0..<40 {
    match sink.poll().unwrap() {
      @access.SinkProgress => ()
      @access.SinkComplete(value) => {
        receipt = Some(value)
        break
      }
      @access.SinkFailed(_, _) => fail("actual Source sink failed")
    }
  }
  assert_eq(@utf8.decode(Bytes::from_array(output)), "{\"id\":3}\n")
  assert_eq(finishes.val, 1)
  guard receipt is Some(receipt) else {
    fail("actual Source sink did not complete")
  }
  assert_eq(receipt.confirmed_bytes, 9L)
  assert_eq(receipt.delivery_attempt_cid, session.attempt_cid())
  assert_true(sink.poll() is Ok(@access.SinkComplete(_)))
  assert_eq(output.length(), 9)
  assert_eq(finishes.val, 1)
  sink.close().unwrap()
}
