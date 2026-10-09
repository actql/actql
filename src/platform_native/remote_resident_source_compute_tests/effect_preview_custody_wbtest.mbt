// Original physical Provider Preview and computation have distinct encrypted
// custody and reservations. These are real SQLite/crypto/Native connections;
// Store reopening preserves the live Ledger and is not Host restart evidence.

///|
fn retained_effect_preview_store(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  result : @resident.ResidentEffectResultCapture,
  invocation : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  captured : @publication.PublicationContract,
  authority : String,
  wire : String,
  authoring_cid : String,
  crypto : @signature.Library,
  key : Bytes,
  sqlite : @sqlite.Library,
  path : String,
  initial_store : @store.Store,
  computation : @resident.ResidentEffectCaptureCustody,
  baseline : Int64,
  computation_bytes : Int64,
) -> @store.Store raise {
  let identity = @strategy.captured_effect_preview_ledger_identity(preview)
  let holding = @publication.effect_preview_private_holding_cid(
    identity, authority,
  ).unwrap()
  let cid = @publication.effect_preview_semantic_identity(identity)
  let open = () => {
    @store.open_store(sqlite, path, authority, 536870912L, 8L, 262144L).unwrap()
  }
  let mut store = initial_store
  let before = baseline + computation_bytes
  let foreign_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "foreign-target-preview",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    consumer.persist_effect_preview(
      store,
      { ..materials, run_definition: foreign_run, },
      inputs,
      result,
      invocation,
      preview,
      captured,
      wire,
      authoring_cid,
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
    )
    is Err({ issue: Binding(_), custody: None, }),
  )
  assert_true(
    store.prepare_effect_preview_custody(
      identity,
      wire,
      @publication.publication_contract_identity(foreign_run),
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
    )
    is Err(_),
  )
  assert_true(
    store.prepare_effect_preview_custody(
      identity,
      wire.replace(old="\"Count__c\":7", new="\"Count__c\":8"),
      authoring_cid,
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
    )
    is Err(_),
  )
  assert_true(
    store.prepare_effect_preview_custody(
      identity, wire, authoring_cid, authority, crypto, key, 1, 10000, 64,
    )
    is Err(_),
  )
  assert_true(
    store.prepare_effect_preview_custody(
      identity,
      wire,
      authoring_cid,
      @publication.publication_contract_identity(foreign_run),
      crypto,
      key,
      65536,
      10000,
      64,
    )
    is Err(StateCollision),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, computation_bytes)
  assert_eq(consumer.usage().reserved_retention_bytes, before)
  let persist = () => {
    consumer.persist_effect_preview(
      store, materials, inputs, result, invocation, preview, captured, wire, authoring_cid,
      authority, crypto, key, 65536, 10000, 64,
    )
  }
  let closed = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-preview-persisted" && !closed.val {
      closed.val = true
      store.close().unwrap() |> ignore
    }
  })
  let first = persist()
  guard first is Err({ issue: Store(Closed), custody: Some(custody), }) else {
    fail("Preview persistence acknowledgement must be lost after the commit")
  }
  let (_, original_request) = retained_compute_effect_materials(provider=true)
  let review_limits : @checkpoint.WireLimits = {
    max_wire_bytes: 262144,
    max_nodes: 10000,
    max_depth: 64,
  }
  let prepare_checkpoint = (material, request, limits) => {
    consumer.prepare_effect_review_checkpoint(
      material, inputs, request, computation, custody, "native-provider-review",
      "2026-10-10T00:00:00.000Z", "2026-10-11T00:00:00.000Z", limits,
    )
  }
  assert_true(
    prepare_checkpoint(materials, original_request, review_limits)
    is Err(Capture(Store(Closed))),
  )
  let preview_bytes = consumer.usage().reserved_retention_bytes - before
  assert_true(preview_bytes > 0L)
  store = open()
  custody.restore_store(store).unwrap()
  computation.restore_store(store).unwrap()
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    computation_bytes + preview_bytes,
  )
  let (restored_identity, restored_wire) = custody.confirm().unwrap()
  assert_eq(
    @publication.effect_preview_semantic_identity(restored_identity),
    cid,
  )
  assert_eq(restored_wire, wire)
  assert_eq(
    @publication.effect_preview_row_intended_changes_wire(
      restored_identity, 0, 0,
    ),
    Some("{\"state\":\"present\",\"value\":{\"Count__c\":3}}"),
  )
  assert_true(
    restored_wire.contains(
      "\"before\":{\"state\":\"present\",\"value\":{\"Count__c\":7}}",
    ),
  )
  assert_true(
    prepare_checkpoint(
      { ..materials, run_definition: foreign_run, },
      original_request,
      review_limits,
    )
    is Err(ForeignCapture),
  )
  assert_true(
    prepare_checkpoint(materials, original_request, {
      ..review_limits,
      max_wire_bytes: 1,
    })
    is Err(Encoding),
  )
  let other_request = @host.prepare_client_effect_request_identity(
    materials.prepared,
    @host.client_request_authority_scope_cid(original_request),
    "another-request",
    @host.client_request_input_cid(original_request),
  ).unwrap()
  assert_true(
    prepare_checkpoint(materials, other_request, review_limits) is Err(Keys(_)),
  )
  for
    window in [
      ("2026-10-08T00:00:00.000Z", "2026-10-11T00:00:00.000Z"),
      ("2026-10-10T00:00:00.000Z", "2099-01-02T00:00:00.000Z"),
    ] {
    assert_true(
      consumer.prepare_effect_review_checkpoint(
        materials,
        inputs,
        original_request,
        computation,
        custody,
        "native-provider-review",
        window.0,
        window.1,
        review_limits,
      )
      is Err(RunLifetimeUnavailable),
    )
  }
  let prepared_checkpoint = prepare_checkpoint(
    materials, original_request, review_limits,
  ).unwrap()
  let checkpoint = prepared_checkpoint.checkpoint
  assert_eq(checkpoint.checkpoint.required_artifact_cid, cid)
  assert_eq(
    checkpoint.checkpoint.continuation_state_cid,
    "sha256:" +
    @sha.hex(@sha.digest(@utf8.encode(prepared_checkpoint.continuation_wire))),
  )
  assert_true(
    checkpoint.checkpoint.continuation_state_cid !=
    @publication.publication_contract_identity(captured),
  )
  assert_eq(
    checkpoint.checkpoint.review_projection_cid,
    "sha256:" + @sha.hex(@sha.digest(@utf8.encode(wire))),
  )
  assert_eq(prepared_checkpoint.review_wire, wire)
  assert_true(
    prepared_checkpoint.continuation_wire.contains("retained_input_binding"),
  )
  assert_true(
    prepared_checkpoint.continuation_wire.contains("captured_run_wire"),
  )
  assert_true(
    prepared_checkpoint.continuation_wire.contains("another-request") == false,
  )
  assert_eq(
    prepare_checkpoint(materials, original_request, review_limits).unwrap().checkpoint.wire,
    checkpoint.wire,
  )
  assert_eq(consumer.usage().reserved_retention_bytes, before + preview_bytes)
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    computation_bytes + preview_bytes,
  )
  store = retained_effect_checkpoint_store(
    consumer, inputs, prepared_checkpoint, computation, custody, store, authority,
    crypto, key, sqlite, path, review_limits,
  )
  let inspection = sqlite
    .open_database(path + "/.actql-publication.sqlite3", 262144L)
    .unwrap()
  let original = inspection.read("effect_preview_custody", holding).unwrap()
  assert_true(original.body != @utf8.encode(wire))
  assert_false(@utf8.decode(original.body).contains("Count__c"))
  assert_eq(
    crypto
    .open_private_evidence(key, "effect_preview", cid, original.body)
    .unwrap(),
    @utf8.encode(wire),
  )
  assert_true(
    crypto.open_private_evidence(key, "effect_capture", cid, original.body)
    is Err(CipherRejected),
  )
  assert_true(
    store.restore_effect_preview_custody(
      identity,
      wire,
      authoring_cid,
      authority,
      crypto,
      Bytes::make(32, 0),
      65536,
      10000,
      64,
    )
    is Err(PrivateEvidence(CipherRejected)),
  )
  assert_true(physical_equal(persist().unwrap(), custody))
  assert_eq(
    inspection.read("effect_preview_custody", holding).unwrap().body,
    original.body,
  )
  assert_eq(consumer.usage().reserved_retention_bytes, before + preview_bytes)
  // The common Preview Owner requires original canonical wire. Even harmless
  // whitespace is refused before encryption; the saved bytes remain unchanged.
  assert_true(
    store.prepare_effect_preview_custody(
      identity,
      wire + "\n",
      authoring_cid,
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
    )
    is Err(PreviewAdmission(PreviewShape(InvalidWire))),
  )
  assert_eq(
    inspection.read("effect_preview_custody", holding).unwrap().body,
    original.body,
  )
  let closed_cleanup = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-preview-terminal-saved" && !closed_cleanup.val {
      closed_cleanup.val = true
      store.close().unwrap() |> ignore
    }
  })
  assert_true(custody.retry_cleanup() is Err(Store(Closed)))
  assert_eq(consumer.usage().reserved_retention_bytes, before + preview_bytes)
  store = open()
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    computation_bytes + preview_bytes,
  )
  custody.restore_store(store).unwrap()
  computation.restore_store(store).unwrap()
  assert_true(custody.confirm() is Err(Store(RecoveryRequired)))
  assert_true(custody.retry_cleanup().unwrap())
  assert_false(custody.retry_cleanup().unwrap())
  assert_true(
    prepare_checkpoint(materials, original_request, review_limits)
    is Err(Preview(Unavailable)),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, before)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, computation_bytes)
  assert_eq(
    @publication.publication_contract_identity(computation.confirm().unwrap()),
    @publication.publication_contract_identity(captured),
  )
  let terminal = inspection.read("effect_preview_custody", holding).unwrap()
  assert_eq(terminal.revision, 1L)
  assert_false(@utf8.decode(terminal.body).contains("ciphertext"))
  assert_false(@utf8.decode(terminal.body).contains("Count__c"))
  let late = store
    .restore_effect_preview_custody(
      identity, wire, authoring_cid, authority, crypto, key, 65536, 10000, 64,
    )
    .unwrap()
  assert_true(late.persist() is Err(RecoveryRequired))
  assert_false(late.retry_cleanup().unwrap())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, computation_bytes)
  inspection.close()
  println(
    "retained-effect-preview: original target wire and Checkpoint snapshot confirmed; independent cleanup returned its reservation once",
  )
  store
}
