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
  original_normalization? : Bool = false,
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
  // The strict Local path obtains its original journal inside the Work owner.
  // Legacy test-owned journal bytes belong only to the generic fixture path.
  let normalization = if original_normalization {
    None
  } else {
    Some(
      @publication.seal_run_evidence_value(
        "normalization_journal",
        "{\"version\":\"actql-normalization-journal/0.1\",\"rule_catalog_cid\":\"" +
        local_client_publication_cid("normalization-rules") +
        "\",\"entries\":[]}",
        1000000,
        100000,
        100,
      ).unwrap(),
    )
  }
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
  let prepare = (
    context : @native_publication.NativeCapturedResultPublicationContext,
  ) => {
    if original_normalization {
      work.prepare_local_publication(
        service,
        context,
        authoring,
        intent,
        occurrence,
        resident_compute_limits(),
        1000000,
        100000,
        100,
      )
    } else {
      work.prepare_publication(
        service,
        context,
        normalization.unwrap(),
        authoring,
        intent,
        occurrence,
        resident_compute_limits(),
        1000000,
        100000,
        100,
      )
    }
  }
  if !original_normalization {
    assert_true(
      work.prepare_local_publication(
        service,
        result,
        authoring,
        intent,
        occurrence,
        resident_compute_limits(),
        1000000,
        100000,
        100,
      )
      is Err(@client.OriginalNormalizationMissing),
    )
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  }
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
    assert_true(prepare(changed) is Err(@client.SourceBindingMismatch))
  }
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 0L)
  revoke_during_authorization.val = true
  assert_true(
    prepare(result)
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
  let pending = prepare(result).unwrap()
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
  if original_normalization {
    let index = store
      .read_publication_contract(
        "public_index_entry",
        committed.public_index_entry_cid,
      )
      .unwrap()
    guard @json.parse(@publication.publication_contract_json(index))
      is Object(index_fields) &&
      index_fields.get("run_receipt_cid") is Some(String(receipt_cid)) else {
      fail("committed original publication has no receipt identity")
    }
    let receipt = store
      .read_publication_contract("run_receipt", receipt_cid)
      .unwrap()
    guard @json.parse(@publication.publication_contract_json(receipt))
      is Object(receipt_fields) else {
      fail("original publication receipt is not an object")
    }
    // Fixed independently authored Local catalog/journal vector, not a value
    // copied from the owner under test or from the legacy fixture journal.
    guard receipt_fields.get("normalization_journal_cid")
      is Some(String(journal_cid)) else {
      fail("original receipt has no normalization identity")
    }
    assert_eq(
      journal_cid, "sha256:e245b445e5014e5764dab4bf1b9ddc3b3abdf821ddf75950f9bee9df29007164",
    )
  }

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
  journal : @client.NativeClientRunJournal,
  epoch_authority : @client.NativeClientEpochAuthority,
  reference : @client.NativeClientSubmissionReference,
  store : @store.Store,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  attempt : String,
) -> Unit raise {
  let admissions = Ref(0)
  let authority = @access.install_native_result_access_authority(
    requested => {
      requested.run_definition_cid ==
      @publication.publication_contract_identity(definition) &&
      requested.authority_scope_cid ==
      @host.client_request_authority_scope_cid(request) &&
      requested.principal_id == "fixture-principal"
    },
    _ => {
      admissions.val += 1
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
    authorize_lookup=Some(requested => {
      requested.run_definition_cid ==
      @publication.publication_contract_identity(definition) &&
      requested.authority_scope_cid ==
      @host.client_request_authority_scope_cid(request) &&
      requested.principal_id == "fixture-principal"
    }),
  )
  let service = @access.install_native_result_access_service(
    store,
    authority,
    () => "2026-10-10T00:00:08.000Z",
    1000000,
    100000,
    16,
    128,
    3,
  ).unwrap()
  let selection : @client.NativeClientResultSelection = {
    namespace_id: "native-client-fixture",
    principal_id: "fixture-principal",
    purpose: "inspect",
    result_name: "answer",
    format: "jsonl",
    attempt_id: attempt,
  }
  let scope = @host.client_request_authority_scope_cid(request)
  let read_epoch = epoch_authority.issue_epoch(scope, true, 1101.0).unwrap()
  let unresolved = @client.prepare_native_client_submission_reference(
    read_epoch, "unresolved-read-reference",
  ).unwrap()
  assert_true(
    journal.open_submitted_result(
      epoch_authority,
      unresolved,
      scope,
      () => true,
      1102.0,
      service,
      selection,
    )
    is Err(@client.UnresolvedSubmissionHistory),
  )
  let unadmitted = @client.prepare_native_client_submission_reference(
    read_epoch, "unadmitted-read-reference",
  ).unwrap()
  let unadmitted_intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    resident_compute_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  journal
  .record_submitted_intent(
    epoch_authority, unadmitted, unadmitted_intent, scope, true, 1102.0,
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.open_submitted_result(
      epoch_authority,
      unadmitted,
      scope,
      () => true,
      1103.0,
      service,
      selection,
    )
    is Err(@client.RunNotAdmitted),
  )
  assert_true(
    journal.open_submitted_result(
      epoch_authority,
      reference,
      "sha256:" + "b".repeat(64),
      () => true,
      1103.0,
      service,
      selection,
    )
    is Err(@client.Journal(@client.Epoch(@client.ScopeMismatch))),
  )
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_root(root_path).unwrap()
  let foreign_name = "native-client-read-foreign-" + @env.now().to_string()
  root.create_directory(foreign_name).unwrap() |> ignore
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let (store_authority, _, _) = store.custody_location().unwrap()
  let foreign_store = @store.open_store(
    library,
    root_path + "/" + foreign_name,
    store_authority,
    128L,
    8L,
    1000000L,
  ).unwrap()
  let foreign_service = @access.install_native_result_access_service(
    foreign_store,
    authority,
    () => "2026-10-10T00:00:08.000Z",
    1000000,
    100000,
    16,
    128,
    3,
  ).unwrap()
  assert_true(
    journal.open_submitted_result(
      epoch_authority,
      reference,
      scope,
      () => true,
      1103.0,
      foreign_service,
      selection,
    )
    is Err(@client.Journal(@client.ForeignRun)),
  )
  assert_true(foreign_store.close().unwrap())
  assert_true(
    journal.open_submitted_result(
      epoch_authority,
      reference,
      scope,
      () => false,
      1101.0,
      service,
      selection,
    )
    is Err(@client.Journal(@client.AuthorizationDenied)),
  )
  assert_true(
    journal.open_submitted_result(
      epoch_authority,
      reference,
      scope,
      () => true,
      1101.0,
      service,
      { ..selection, namespace_id: "foreign-publication-namespace", },
    )
    is Err(@client.Journal(@client.ForeignRun)),
  )
  let authorization_calls = Ref(0)
  assert_true(
    journal.open_submitted_result(
      epoch_authority,
      reference,
      scope,
      () => {
        authorization_calls.val += 1
        authorization_calls.val < 3
      },
      1101.0,
      service,
      selection,
    )
    is Err(@client.Journal(@client.AuthorizationDenied)),
  )
  assert_eq(admissions.val, 0)
  let accessed = match
    journal.open_submitted_result(
      epoch_authority,
      reference,
      scope,
      () => true,
      1101.0,
      service,
      selection,
    ) {
    Ok(value) => Ok(value)
    Err(@client.ResultAccess(issue)) => Err(issue)
    Err(_) => fail("actual original Submission Result resolution refused")
  }
  let session = match accessed {
    Ok(value) => value
    Err(@access.InvalidRequest) =>
      fail("actual Source Result access: InvalidRequest")
    Err(@access.InvalidProgress) =>
      fail("actual Source Result access: InvalidProgress")
    Err(@access.AccessDenied) =>
      fail("actual Source Result access: AccessDenied")
    Err(@access.ResultUnavailable) =>
      fail("actual Source Result access: ResultUnavailable")
    Err(@access.LookupUnavailable) =>
      fail("actual Source Result access: LookupUnavailable")
    Err(@access.Publication(issue)) =>
      fail(
        "actual Source Result access publication: " + @debug.to_string(issue),
      )
    Err(@access.Store(@store.ClockRegression)) =>
      fail("actual Source Result access: StoreClockRegression")
    Err(@access.Store(@store.InvalidConfiguration)) =>
      fail("actual Source Result access: StoreInvalidConfiguration")
    Err(@access.Store(@store.DeliveryIssuance(issue))) =>
      fail("actual Source Result access delivery: " + @debug.to_string(issue))
    Err(@access.Store(@store.Database(@sqlite.NotFound))) =>
      fail("actual Source Result access: StoreRecordMissing")
    Err(@access.Store(@store.StateCollision)) =>
      fail("actual Source Result access: StoreStateCollision")
    Err(@access.Store(@store.DigestMismatch)) =>
      fail("actual Source Result access: StoreDigestMismatch")
    Err(@access.Store(@store.DeliveryLimit)) =>
      fail("actual Source Result access: StoreDeliveryLimit")
    Err(@access.Store(@store.CleanupPending)) =>
      fail("actual Source Result access: StoreCleanupPending")
    Err(@access.Store(@store.ExistingDeliveryAttempt)) =>
      fail("actual Source Result access: StoreExistingAttempt")
    Err(@access.Store(@store.ExistingPayload)) =>
      fail("actual Source Result access: StoreExistingPayload")
    Err(@access.Store(@store.RecoveryRequired)) =>
      fail("actual Source Result access: StoreRecoveryRequired")
    Err(@access.Store(@store.ReaderBusy)) =>
      fail("actual Source Result access: StoreReaderBusy")
    Err(@access.Store(@store.Closed)) =>
      fail("actual Source Result access: StoreClosed")
    Err(@access.Store(@store.RowFrame(issue))) =>
      fail("actual Source Result row frame: " + @debug.to_string(issue))
    Err(@access.Store(@store.Delivery(issue))) =>
      fail("actual Source Result serialization: " + @debug.to_string(issue))
    Err(@access.Store(_)) =>
      fail("actual Source Result access: StorePhysicalBoundary")
  }
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
  assert_eq(admissions.val, 1)
  assert_true(sink.poll() is Ok(@access.SinkComplete(_)))
  assert_eq(output.length(), 9)
  assert_eq(finishes.val, 1)
  sink.close().unwrap()
  let lookup_selection : @client.NativeClientDeliveryAttemptSelection = {
    namespace_id: selection.namespace_id,
    principal_id: selection.principal_id,
    purpose: selection.purpose,
    result_name: selection.result_name,
    attempt_id: selection.attempt_id,
  }
  for _ in 0..<2 {
    guard journal.lookup_submitted_result_delivery(
        epoch_authority,
        reference,
        scope,
        () => true,
        1104.0,
        service,
        lookup_selection,
      )
      is Ok(Some(original)) &&
      original.record is Some(record) &&
      original.host_release_receipt is Some(saved_receipt) else {
      fail("original successful Source read evidence was not restored")
    }
    assert_eq(
      @publication.publication_contract_identity(original.attempt),
      receipt.delivery_attempt_cid,
    )
    assert_eq(
      @publication.publication_contract_identity(record),
      receipt.delivery_record_cid,
    )
    assert_eq(
      @publication.publication_contract_identity(saved_receipt),
      receipt.result_delivery_receipt_cid,
    )
  }
  assert_true(
    journal.lookup_submitted_result_delivery(
      epoch_authority,
      reference,
      scope,
      () => true,
      1104.0,
      service,
      { ..lookup_selection, namespace_id: "foreign-publication-namespace", },
    )
    is Err(@client.Journal(@client.ForeignRun)),
  )
  assert_true(
    journal.lookup_submitted_result_delivery(
      epoch_authority,
      reference,
      scope,
      () => false,
      1104.0,
      service,
      lookup_selection,
    )
    is Err(@client.Journal(@client.AuthorizationDenied)),
  )
  assert_true(
    journal.lookup_submitted_result_delivery(
      epoch_authority,
      reference,
      scope,
      () => true,
      1104.0,
      service,
      { ..lookup_selection, attempt_id: "absent-original-read", },
    )
    is Ok(None),
  )
  assert_eq(admissions.val, 1)
  assert_eq(output.length(), 9)
  assert_eq(finishes.val, 1)
}
