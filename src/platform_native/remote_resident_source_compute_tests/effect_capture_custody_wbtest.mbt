///|
// Unit widths exercise the nominal lifetime/admission connection only. They
// are not measured Native prices and do not establish an installed profile.
fn original_computation_fixture_layout() -> @resident.ResidentEffectComputationLayout {
  {
    contract_record_bytes: 1L,
    canonical_node_bytes: 1L,
    string_overhead_bytes: 1L,
    utf16_unit_bytes: 1L,
    array_record_bytes: 1L,
    object_record_bytes: 1L,
    array_slot_bytes: 1L,
    object_slot_bytes: 1L,
    frame_slot_bytes: 1L,
    measurement_fixed_bytes: 1L,
    capture_control_bytes: 1L,
  }
}

// Actual Native capture -> encrypted SQLite Store -> exact reopen and cleanup.
// Store reconstruction keeps the live Ledger; Host restart is not claimed.

///|
fn retained_effect_capture_store(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  result : @resident.ResidentEffectResultCapture,
  invocation : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  captured : @publication.PublicationContract,
  authority : String,
  provider? : Bool = false,
  private_preview? : (String, String)? = None,
  checkpoint_custody? : Bool = false,
) -> Unit raise {
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT").unwrap()
  let child = "effect-capture-custody-" + @env.now().to_string()
  @filesystem.open_root(root_path).unwrap().create_directory(child).unwrap()
  |> ignore
  let path = root_path + "/" + child
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let open = () => {
    @store.open_store(sqlite, path, authority, 536870912L, 8L, 262144L).unwrap()
  }
  let mut store = open()
  let baseline = consumer.usage().reserved_retention_bytes
  let foreign_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "foreign-private-custody",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    consumer.persist_effect_capture(
      store,
      { ..materials, run_definition: foreign_run, },
      inputs,
      result,
      invocation,
      preview,
      captured,
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
    )
    is Err({ issue: Binding(_), custody: None, }),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  // Explicit test-only charges exercise lifetime separation. They do not
  // declare an adopted Native layout or a production funding profile.
  let computation_capacity : @resident.ResidentEffectComputationCapacity = {
    contract_bytes: 1048576L,
    control_bytes: 4096L,
    workspace_bytes: 65536L,
    max_utf16_units: 1048576,
    layout: original_computation_fixture_layout(),
  }
  let metadata_bytes = computation_capacity.contract_bytes +
    computation_capacity.control_bytes
  let execution_baseline = consumer.usage().reserved_execution_bytes
  assert_true(
    consumer.persist_effect_capture(
      store, materials, inputs, result, invocation, preview, captured, authority,
      crypto, key, 65536, 10000, 64,
    )
    is Err({ issue: ComputationCapacityMissing, custody: None, }),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  // A positive workspace is not enough. Under these independent unit widths,
  // depth 64 requires 1 + (2 * 128 + 3) = 260 scratch units before traversal.
  assert_true(
    consumer.persist_effect_capture(
      store,
      materials,
      inputs,
      result,
      invocation,
      preview,
      captured,
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
      computation_capacity=Some({
        ..computation_capacity,
        workspace_bytes: 259L,
      }),
    )
    is Err({ issue: Capacity(ExecutionLimit), custody: None, }),
  )
  assert_true(
    consumer.persist_effect_capture(
      store,
      materials,
      inputs,
      result,
      invocation,
      preview,
      captured,
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
      computation_capacity=Some({
        ..computation_capacity,
        layout: { ..computation_capacity.layout, capture_control_bytes: 4097L, },
      }),
    )
    is Err({ issue: Capacity(RetentionLimit), custody: None, }),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  assert_eq(consumer.usage().reserved_execution_bytes, execution_baseline)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  let persist = () => {
    consumer.persist_effect_capture(
      store,
      materials,
      inputs,
      result,
      invocation,
      preview,
      captured,
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
      computation_capacity=Some(computation_capacity),
    )
  }
  let closed = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-capture-persisted" && !closed.val {
      closed.val = true
      store.close().unwrap() |> ignore
    }
  })
  let first = persist()
  let code = match first {
    Ok(_) => "unexpected-success"
    Err({ issue: Unavailable, .. }) => "unavailable"
    Err({ issue: Capacity(_), .. }) => "ledger-capacity"
    Err({ issue: Binding(_), .. }) => "common-binding"
    Err({ issue: Store(Database(issue)), .. }) =>
      match issue {
        UnsupportedTarget => "sqlite-unsupported"
        InvalidName => "sqlite-name"
        InvalidLimit => "sqlite-limit"
        LibraryLoad(_) => "sqlite-library"
        DatabaseOpen(_) => "sqlite-open"
        DatabaseClosed => "sqlite-closed"
        NotFound => "sqlite-not-found"
        Collision => "sqlite-collision"
        Busy => "sqlite-busy"
        BodyTooLarge => "sqlite-body"
        CapacityExceeded => "sqlite-capacity"
        Physical(_) => "sqlite-physical"
        OperationRoutingBefore(_) => "sqlite-routing-before"
        OperationRoutingAfter(_, _) => "sqlite-routing-after"
      }
    Err({ issue: Store(PrivateEvidence(issue)), .. }) =>
      match issue {
        UnsupportedTarget => "crypto-unsupported"
        InvalidInput => "crypto-input"
        CipherRejected => "crypto-rejected"
      }
    Err({ issue: Store(StateCollision), .. }) => "store-collision"
    Err({ issue: Store(InvalidConfiguration), .. }) => "store-configuration"
    Err({ issue: Store(Closed), .. }) => "store-closed"
    Err(_) => "store-other"
  }
  guard first is Err({ issue: Store(Closed), custody: Some(custody), }) else {
    fail("lost encrypted capture acknowledgement: " + code)
  }
  let charged = consumer.usage().reserved_retention_bytes -
    baseline -
    metadata_bytes
  assert_true(charged > 0L)
  store = open()
  custody.restore_store(store).unwrap()
  assert_eq(
    @publication.publication_contract_identity(custody.confirm().unwrap()),
    @publication.publication_contract_identity(captured),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, charged)
  assert_eq(
    custody
    .original_computation_representation_extent(10000, 64, 65536)
    .unwrap()
    .length(),
    6,
  )
  assert_eq(
    consumer.usage().reserved_execution_bytes,
    execution_baseline + computation_capacity.workspace_bytes,
  )
  let original_binding = @publication.prepare_effect_capture_holding_binding(
    materials.run_definition,
    invocation,
    [result.definition],
    [result.artifact],
    result.manifest,
    result.receipt,
    captured,
    @strategy.captured_effect_preview_ledger_identity(preview),
    authority,
    65536,
    10000,
    64,
  ).unwrap()
  let inspection = sqlite
    .open_database(path + "/.actql-publication.sqlite3", 262144L)
    .unwrap()
  let slot = @publication.effect_capture_holding_identity(original_binding)
  let encrypted_row = inspection.read("effect_capture_custody", slot).unwrap()
  let capture_wire = @publication.publication_contract_json(captured)
  assert_true(encrypted_row.body != @utf8.encode(capture_wire))
  assert_false(
    @utf8.decode(encrypted_row.body).contains(
      "\"answer\":" + retained_effect_expected_rows(provider),
    ),
  )
  assert_eq(
    crypto
    .open_private_evidence(
      key,
      "effect_capture",
      @publication.publication_contract_identity(captured),
      encrypted_row.body,
    )
    .unwrap(),
    @utf8.encode(capture_wire),
  )
  assert_true(
    store.restore_effect_capture_custody(
      original_binding,
      crypto,
      Bytes::make(32, 0),
    )
    is Err(PrivateEvidence(CipherRejected)),
  )
  let before_changed_capacity = consumer.usage()
  assert_true(
    consumer.persist_effect_capture(
      store,
      materials,
      inputs,
      result,
      invocation,
      preview,
      captured,
      authority,
      crypto,
      key,
      65536,
      10000,
      64,
      computation_capacity=Some({
        ..computation_capacity,
        control_bytes: 4097L,
      }),
    )
    is Err({ issue: Unavailable, custody: Some(original), }) &&
    physical_equal(original, custody),
  )
  assert_eq(consumer.usage(), before_changed_capacity)
  assert_true(physical_equal(persist().unwrap(), custody))
  assert_eq(
    inspection.read("effect_capture_custody", slot).unwrap().body,
    encrypted_row.body,
  )
  assert_eq(
    consumer.usage().reserved_retention_bytes,
    baseline + charged + metadata_bytes,
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, charged)
  if private_preview is Some((wire, authoring_cid)) {
    store = retained_effect_preview_store(
      consumer,
      materials,
      inputs,
      result,
      invocation,
      preview,
      captured,
      authority,
      wire,
      authoring_cid,
      crypto,
      key,
      sqlite,
      path,
      store,
      custody,
      baseline + metadata_bytes,
      charged,
      checkpoint_custody~,
    )
  }
  // Lose cleanup acknowledgement after ciphertext removal, before capacity
  // release. The original live Ledger charge must survive Store reconstruction.
  let closed_cleanup = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-capture-terminal-saved" && !closed_cleanup.val {
      closed_cleanup.val = true
      store.close().unwrap() |> ignore
    }
  })
  assert_true(custody.retry_cleanup() is Err(Store(Closed)))
  assert_eq(
    consumer.usage().reserved_retention_bytes,
    baseline + charged + metadata_bytes,
  )
  store = open()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, charged)
  custody.restore_store(store).unwrap()
  assert_true(custody.confirm() is Err(Store(RecoveryRequired)))
  assert_true(custody.retry_cleanup().unwrap())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  assert_eq(consumer.usage().reserved_execution_bytes, execution_baseline)
  assert_true(
    custody.original_computation_representation_extent(10000, 64, 65536)
    is Err(Unavailable),
  )
  let terminal_row = inspection.read("effect_capture_custody", slot).unwrap()
  assert_eq(terminal_row.revision, 1L)
  assert_true(terminal_row.body != encrypted_row.body)
  assert_false(@utf8.decode(terminal_row.body).contains("ciphertext"))
  // A pre-persistence cleanup must fence another already prepared handle.
  // Use a distinct Store so the earlier persisted tombstone cannot mask it.
  @filesystem.open_root(root_path)
  .unwrap()
  .create_directory(child + "-empty")
  .unwrap()
  |> ignore
  let empty_path = path + "-empty"
  let empty_store = @store.open_store(
    sqlite, empty_path, authority, 536870912L, 8L, 262144L,
  ).unwrap()
  let early = empty_store
    .prepare_effect_capture_custody(original_binding, crypto, key)
    .unwrap()
  let late = empty_store
    .prepare_effect_capture_custody(original_binding, crypto, key)
    .unwrap()
  early.retry_cleanup().unwrap() |> ignore
  assert_true(
    late.persist() is Err(RecoveryRequired),
    msg="cleanup before persistence must prevent revival",
  )
  assert_eq(empty_store.capacity_usage().unwrap().reserved_bytes, 0L)
  empty_store.close().unwrap() |> ignore
  let reopened = @store.open_store(
    sqlite, empty_path, authority, 536870912L, 8L, 262144L,
  ).unwrap()
  let restored_empty = reopened
    .restore_effect_capture_custody(original_binding, crypto, key)
    .unwrap()
  assert_true(restored_empty.persist() is Err(RecoveryRequired))
  assert_true(restored_empty.retry_cleanup() is Ok(false))
  reopened.close().unwrap() |> ignore
  inspection.close()
  assert_true(custody.retry_cleanup() is Ok(false))
  let terminal = store
    .restore_effect_capture_custody(original_binding, crypto, key)
    .unwrap()
  assert_true(terminal.persist() is Err(RecoveryRequired))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  store.close().unwrap() |> ignore
  println(
    "retained-effect-capture: encrypted original capture reconciled; cleanup reservations returned once",
  )
}
