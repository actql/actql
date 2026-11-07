///|
/// Save this actual original review through the existing evidence custodians.
/// Store reopening retains the live holding and Ledger; it is not Host restart,
/// a committed Cloud waiting state, reviewer approval or an execution permit.
fn native_mapped_create_checkpoint_roundtrip(
  work : @effect_provider.NativeResidentEffectReview,
  journal : @dispatch_journal.Journal,
  consumer : @resident.ResidentSourceCompute,
  policy : @effect_provider.NativeResidentEffectReviewPolicy,
  complete : @effect_provider.NativeResidentEffectReviewCapture,
) -> Unit raise {
  let root_path = retained_runtime_required_env(
    "ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT",
  )
  let root = @filesystem.open_root(root_path).unwrap()
  let child = "mapped-create-checkpoint-" + @env.now().to_string()
  root.create_directory(child).unwrap() |> ignore
  let path = root_path + "/" + child
  let sqlite = @sqlite.load_library(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"),
  ).unwrap()
  let crypto = @signature.load_library(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY"),
  ).unwrap()
  // Local encryption fixture only; never a Cloud authorization or signing key.
  let key = Bytes::makei(32, index => index.to_byte())
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 262144,
    max_nodes: 10000,
    max_depth: 64,
  }
  // Match the existing nominal retention fixture's explicit test charges.
  // Unit widths exercise custody, not an adopted Native allocation profile.
  let computation_capacity : @resident.ResidentEffectComputationCapacity = {
    contract_bytes: 1048576L,
    control_bytes: 4096L,
    workspace_bytes: 65536L,
    max_utf16_units: 1048576,
    layout: original_computation_fixture_layout(),
  }
  let created_at = "2026-10-10T00:00:00.000Z"
  let expires_at = "2026-10-11T00:00:00.000Z"
  let checkpoint_id = "native-original-mapped-create"
  let baseline = consumer.usage().reserved_retention_bytes
  let retention = work
    .prepare_retention(
      crypto, key, checkpoint_id, created_at, expires_at, limits,
    )
    .unwrap()
  assert_true(retention.report() is Err(Unavailable))
  let open = () => {
    @store.open_store(
      sqlite,
      path,
      policy.store_authority_cid,
      536870912L,
      8L,
      262144L,
    ).unwrap()
  }
  let mut store = open()
  let lost = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-continuation-persisted" && !lost.val {
      lost.val = true
      store.close().unwrap() |> ignore
    }
  })
  assert_true(
    work.persist_and_retain_report(
      store,
      crypto,
      key,
      checkpoint_id,
      created_at,
      expires_at,
      limits,
      computation_capacity=Some(computation_capacity),
    )
    is Err(Retention(Checkpoint(Store(Closed)))),
  )
  assert_true(lost.val)
  println("native-mapped-create: original continuation response lost")
  let pending = consumer.usage().reserved_retention_bytes
  assert_true(pending > baseline)
  assert_true(retention.report() is Err(_))
  store = open()
  retention.restore_store(store).unwrap()
  assert_eq(consumer.usage().reserved_retention_bytes, pending)
  let persist = () => {
    work
    .persist_and_retain_report(
      store,
      crypto,
      key,
      checkpoint_id,
      created_at,
      expires_at,
      limits,
      computation_capacity=Some(computation_capacity),
    )
    .unwrap()
  }
  let report = persist()
  println("native-mapped-create: original Checkpoint and journal confirmed")
  let report_wire = @remote.remote_effect_checkpoint_report_json(report)
  let dispatch = @remote.remote_effect_checkpoint_report_dispatch(report)
  assert_eq(
    @remote.dispatch_request_identity(
      @remote.remote_effect_checkpoint_report_dispatch(report),
    ),
    work.dispatch_identity(),
  )
  let saved = journal.effect_checkpoint_report(dispatch, limits).unwrap()
  assert_eq(@remote.remote_effect_checkpoint_report_json(saved.0), report_wire)
  // Saving a report is not receiving an ACK or committing approval wait.
  assert_eq(saved.1, None)
  assert_true(
    work.review_projection(() => false, 65536) is Err(Retention(EvidenceDenied)),
  )
  let projection = work.review_projection(() => true, 65536).unwrap()
  assert_eq(projection.1, complete.preview.wire)
  assert_eq(
    @remote.remote_effect_checkpoint_report_json(projection.0),
    report_wire,
  )
  let reserved = consumer.usage().reserved_retention_bytes
  let physical_reserved = store.capacity_usage().unwrap().reserved_bytes
  let result = work.result_capture().unwrap()
  for _ in 0..<2 {
    assert_eq(
      @remote.remote_effect_checkpoint_report_json(persist()),
      report_wire,
    )
    assert_eq(consumer.usage().reserved_retention_bytes, reserved)
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, physical_reserved)
  }
  let cleanup_lost = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-checkpoint-terminal-saved" && !cleanup_lost.val {
      cleanup_lost.val = true
      store.close().unwrap() |> ignore
    }
  })
  assert_true(work.retry_cleanup() is Err(Retention(_)))
  assert_true(cleanup_lost.val)
  println("native-mapped-create: original review cleanup pending")
  let cleanup_pending = consumer.usage().reserved_retention_bytes
  assert_true(cleanup_pending > baseline)
  // Retirement revokes evidence access but retains the same physical Result.
  assert_true(work.result_capture() is None)
  assert_true(result.output.result_schema_wire() is Ok(_))
  store = open()
  retention.restore_store(store).unwrap()
  assert_eq(consumer.usage().reserved_retention_bytes, cleanup_pending)
  assert_true(work.retry_cleanup().unwrap())
  assert_false(work.retry_cleanup().unwrap())
  assert_true(work.result_capture() is None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(retention.report() is Err(Unavailable))
  store.close().unwrap() |> ignore
  println("native-mapped-create: original review cleanup confirmed")
}
