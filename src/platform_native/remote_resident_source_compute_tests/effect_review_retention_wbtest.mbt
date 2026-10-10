///|
/// Exercise the production retention connection with original real holders,
/// physical Provider evidence and real SQLite/crypto. Store reopening retains
/// the live Ledger and does not establish Host restart or approval acceptance.
fn retained_effect_review_retention_store(
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
  review_work? : @effect_provider.NativeResidentEffectReview? = None,
  original_journal_path? : String? = None,
) -> Unit raise {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT").unwrap()
  let child = "effect-review-retention-" + @env.now().to_string()
  @filesystem.open_root(root).unwrap().create_directory(child).unwrap()
  |> ignore
  let path = root + "/" + child
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 262144,
    max_nodes: 10000,
    max_depth: 64,
  }
  let prepare = (material, secret, bounds) => {
    consumer.prepare_effect_review_retention(
      material, inputs, result, invocation, preview, captured, wire, authoring_cid,
      authority, crypto, secret, "native-original-review-retention", "2026-10-10T00:00:00.000Z",
      "2026-10-11T00:00:00.000Z", bounds,
    )
  }
  println("native-original-review: preparing review retention")
  let baseline = consumer.usage().reserved_retention_bytes
  assert_true(
    prepare({ ..materials, request: None, }, key, limits) is Err(Unavailable),
  )
  assert_true(
    prepare(materials, Bytes::make(31, 0), limits) is Err(InvalidConfiguration),
  )
  assert_true(
    prepare(materials, key, { ..limits, max_depth: 0, })
    is Err(InvalidConfiguration),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  let retention = match review_work {
    Some(work) => {
      let retained = work
        .prepare_retention(
          crypto, key, "native-original-review-retention", "2026-10-10T00:00:00.000Z",
          "2026-10-11T00:00:00.000Z", limits,
        )
        .unwrap()
      assert_true(
        physical_equal(
          retained,
          work
          .prepare_retention(
            crypto, key, "native-original-review-retention", "2026-10-10T00:00:00.000Z",
            "2026-10-11T00:00:00.000Z", limits,
          )
          .unwrap(),
        ),
      )
      assert_true(
        work.prepare_retention(
          crypto, key, "native-original-review-retention", "2026-10-10T00:00:00.000Z",
          "2026-10-12T00:00:00.000Z", limits,
        )
        is Err(Unavailable),
      )
      retained
    }
    None => prepare(materials, key, limits).unwrap()
  }
  assert_true(retention.report() is Err(Unavailable))
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  let open = () => {
    @store.open_store(sqlite, path, authority, 536870912L, 8L, 262144L).unwrap()
  }
  let mut store = open()
  // Lose each acknowledgement after its real commit. The same retention
  // object resumes all four boundaries without another Provider observation.
  for
    step in [
      "effect-capture-persisted", "effect-preview-persisted", "effect-continuation-persisted",
      "effect-checkpoint-persisted",
    ] {
    let lost = Ref(false)
    store.observe_allocation(actual => {
      if actual == step && !lost.val {
        lost.val = true
        store.close().unwrap() |> ignore
      }
    })
    let failed = retention.persist(store)
    assert_true(lost.val)
    match step {
      "effect-capture-persisted" =>
        assert_true(failed is Err(Capture(Store(Closed))))
      "effect-preview-persisted" =>
        assert_true(failed is Err(Preview(Store(Closed))))
      _ => assert_true(failed is Err(Checkpoint(Store(Closed))))
    }
    let pending = consumer.usage().reserved_retention_bytes
    assert_true(pending > baseline)
    assert_true(retention.report() is Err(_))
    store = open()
    retention.restore_store(store).unwrap()
    assert_eq(consumer.usage().reserved_retention_bytes, pending)
  }
  println("native-original-review: persistence fault retries confirmed")
  let report = retention.persist(store).unwrap()
  let resolution_fixture = if review_work is Some(work) {
    println("native-original-review: retaining journal report")
    let queued = work
      .persist_and_retain_report(
        store, crypto, key, "native-original-review-retention", "2026-10-10T00:00:00.000Z",
        "2026-10-11T00:00:00.000Z", limits,
      )
      .unwrap()
    assert_eq(
      @remote.remote_effect_checkpoint_report_json(queued),
      @remote.remote_effect_checkpoint_report_json(report),
    )
    Some(retained_holder_admit_resolution(work, report))
  } else {
    None
  }
  if @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_APPROVED_ROW") == Some("1") {
    retained_holder_write_row(
      review_work.unwrap(),
      report,
      resolution_fixture.unwrap(),
      invocation,
      original_journal_path.unwrap(),
      consumer,
      result,
    )
  }
  let report_wire = @remote.remote_effect_checkpoint_report_json(report)
  let checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(report)
  let holding = checkpoint.checkpoint_cid
  let inspection = sqlite
    .open_database(path + "/.actql-publication.sqlite3", 262144L)
    .unwrap()
  let continuation = inspection
    .read("effect_continuation_custody", holding)
    .unwrap()
  let checkpoint_record = inspection
    .read("effect_checkpoint_custody", holding)
    .unwrap()
  assert_false(@utf8.decode(continuation.body).contains("Count__c"))
  let reserved = consumer.usage().reserved_retention_bytes
  let physical_reserved = store.capacity_usage().unwrap().reserved_bytes
  assert_true(reserved > baseline)
  for _ in 0..<2 {
    assert_eq(
      @remote.remote_effect_checkpoint_report_json(
        retention.persist(store).unwrap(),
      ),
      report_wire,
    )
    assert_eq(consumer.usage().reserved_retention_bytes, reserved)
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, physical_reserved)
    let current = inspection
      .read("effect_continuation_custody", holding)
      .unwrap()
    assert_eq(current.body, continuation.body)
    assert_eq(current.revision, continuation.revision)
    let current = inspection.read("effect_checkpoint_custody", holding).unwrap()
    assert_eq(current.body, checkpoint_record.body)
    assert_eq(current.revision, checkpoint_record.revision)
  }
  // Retirement is independently confirmed by each existing custody owner.
  // Loss at a later boundary must not reopen earlier retired owners or return
  // the failed owner's reservation before its durable terminal is confirmed.
  for
    step in [
      "effect-checkpoint-terminal-saved", "effect-preview-terminal-saved", "effect-capture-terminal-saved",
    ] {
    let lost = Ref(false)
    let pending = Ref(0L)
    store.observe_allocation(actual => {
      if actual == step && !lost.val {
        lost.val = true
        pending.val = consumer.usage().reserved_retention_bytes
        store.close().unwrap() |> ignore
      }
    })
    match review_work {
      Some(work) =>
        if step == "effect-checkpoint-terminal-saved" {
          let (wire, authentication, reviewers, keys) = resolution_fixture.unwrap()
          // A reentrant trusted clock can begin retirement. Admission must
          // recheck the actual holder after the callback, without dropping
          // the pending original retention owner or returning capacity.
          let cleanup_failed = Ref(false)
          assert_true(
            work.admit_resolution(
              wire,
              authentication,
              reviewers,
              keys,
              () => true,
              () => {
                cleanup_failed.val = work.retry_cleanup() is Err(Retention(_))
                "2026-10-10T00:01:00.000Z"
              },
            )
            is Err(AuthorityDenied),
          )
          assert_true(cleanup_failed.val)
        } else {
          assert_true(work.retry_cleanup() is Err(Retention(_)))
        }
      None => assert_true(retention.retry_cleanup() is Err(_))
    }
    // The adapter must retain its exact input context and public Result when
    // any existing retirement owner is unconfirmed. No capacity is returned.
    assert_eq(consumer.request_for_effect_review(inputs), materials.request)
    assert_true(result.output.result_schema_wire() is Ok(_))
    assert_true(lost.val)
    assert_true(pending.val > baseline)
    assert_eq(consumer.usage().reserved_retention_bytes, pending.val)
    assert_true(retention.report() is Err(Unavailable))
    store = open()
    retention.restore_store(store).unwrap()
    assert_eq(consumer.usage().reserved_retention_bytes, pending.val)
    assert_true(retention.persist(store) is Err(Unavailable))
  }
  assert_true(retention.retry_cleanup().unwrap())
  assert_false(retention.retry_cleanup().unwrap())
  assert_true(retention.restore_store(store) is Err(Unavailable))
  assert_true(retention.report() is Err(Unavailable))
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(consumer.request_for_effect_review(inputs), materials.request)
  for table in ["effect_continuation_custody", "effect_checkpoint_custody"] {
    let terminal = inspection.read(table, holding).unwrap()
    assert_eq(terminal.revision, 1L)
    assert_false(@utf8.decode(terminal.body).contains("ciphertext"))
  }
  inspection.close()
  store.close().unwrap() |> ignore
  println(
    "native-effect-review-retention: original capture, Preview and Checkpoint resume and retire through existing custody owners",
  )
}
