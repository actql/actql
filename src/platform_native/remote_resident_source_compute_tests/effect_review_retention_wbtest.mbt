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
  original_context? : (
    @resident.ResidentEffectReviewInputContext,
    @dispatch_journal.Journal,
  )? = None,
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
  assert_true(
    retention.review_projection(() => true, 65536) is Err(Unavailable),
  )
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
    assert_true(retention.review_projection(() => true, 65536) is Err(_))
    store = open()
    retention.restore_store(store).unwrap()
    assert_eq(consumer.usage().reserved_retention_bytes, pending)
  }
  println("native-original-review: persistence fault retries confirmed")
  let report = retention.persist(store).unwrap()
  let before_projection = consumer.usage().reserved_retention_bytes
  assert_true(
    retention.review_projection(() => false, 65536) is Err(EvidenceDenied),
  )
  assert_true(
    retention.review_projection(() => true, 1) is Err(ProjectionTooLarge),
  )
  let evidence_reads = Ref(0)
  assert_true(
    retention.review_projection(
      () => {
        evidence_reads.val += 1
        evidence_reads.val < 2
      },
      65536,
    )
    is Err(EvidenceDenied),
  )
  assert_eq(evidence_reads.val, 2)
  // Both earlier checks allow this read. Current authority is unavailable
  // only after the final paired Store confirmation, before plaintext returns.
  let final_reads = Ref(0)
  assert_true(
    retention.review_projection(
      () => {
        final_reads.val += 1
        final_reads.val < 3
      },
      65536,
    )
    is Err(EvidenceDenied),
  )
  assert_eq(final_reads.val, 3)
  assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
  assert_eq(
    @remote.remote_effect_checkpoint_report_json(retention.report().unwrap()),
    @remote.remote_effect_checkpoint_report_json(report),
  )
  let closing_reads = Ref(0)
  assert_true(
    retention.review_projection(
      () => {
        closing_reads.val += 1
        if closing_reads.val == 2 {
          store.close().unwrap() |> ignore
        }
        true
      },
      65536,
    )
    is Err(_),
  )
  assert_eq(closing_reads.val, 2)
  assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
  store = open()
  retention.restore_store(store).unwrap()
  let (projection_report, projection_wire) = retention
    .review_projection(() => true, 65536)
    .unwrap()
  assert_eq(
    @remote.remote_effect_checkpoint_report_json(projection_report),
    @remote.remote_effect_checkpoint_report_json(report),
  )
  assert_eq(projection_wire, wire)
  assert_eq(
    @remote.remote_effect_checkpoint_report_checkpoint(projection_report).checkpoint.review_projection_cid,
    "sha256:" + @sha.hex(@utf8.encode(projection_wire)),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
  let resolution_fixture = if review_work is Some(work) {
    let (original_report, original_wire) = work
      .review_projection(() => true, 65536)
      .unwrap()
    assert_eq(original_wire, projection_wire)
    assert_eq(
      @remote.remote_effect_checkpoint_report_identity(original_report),
      @remote.remote_effect_checkpoint_report_identity(report),
    )
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
    if original_context is Some((context, journal)) {
      let before_original = store.capacity_usage().unwrap().reserved_bytes
      let read_original = authorize => {
        context.read_original_review_projection(
          journal, store, authority, crypto, key, limits, authorize,
        )
      }
      assert_true(read_original(() => false) is Err(EvidenceDenied))
      let original_reads = Ref(0)
      assert_true(
        read_original(() => {
          original_reads.val += 1
          original_reads.val < 2
        })
        is Err(EvidenceDenied),
      )
      assert_eq(original_reads.val, 2)
      let final_reads = Ref(0)
      assert_true(
        read_original(() => {
          final_reads.val += 1
          final_reads.val < 3
        })
        is Err(EvidenceDenied),
      )
      assert_eq(final_reads.val, 3)
      assert_eq(store.capacity_usage().unwrap().reserved_bytes, before_original)
      assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
      let restored = read_original(() => true).unwrap()
      assert_eq(restored.1, projection_wire)
      assert_eq(
        @remote.remote_effect_checkpoint_report_json(restored.0),
        @remote.remote_effect_checkpoint_report_json(queued),
      )
      assert_true(
        context.read_original_review_projection(
          journal,
          store,
          retained_compute_cid("f"),
          crypto,
          key,
          limits,
          () => true,
        )
        is Err(Store(StateCollision)),
      )
      assert_eq(store.capacity_usage().unwrap().reserved_bytes, before_original)
      assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
      // A current authorization read can retire/close custody. Recheck after
      // that boundary instead of returning previously read private bytes.
      let close_reads = Ref(0)
      assert_true(
        read_original(() => {
          close_reads.val += 1
          if close_reads.val == 2 {
            store.close().unwrap() |> ignore
          }
          true
        })
        is Err(Store(Closed)),
      )
      assert_eq(close_reads.val, 2)
      store = open()
      retention.restore_store(store).unwrap()
      assert_eq(read_original(() => true).unwrap().1, projection_wire)
      assert_eq(store.capacity_usage().unwrap().reserved_bytes, before_original)
    }
    let (upload_context, upload_journal) = original_context.unwrap()
    retained_holder_upload_original_review(
      work,
      original_journal_path.unwrap(),
      store,
      {
        crypto,
        key,
        checkpoint_id: "native-original-review-retention",
        created_at: "2026-10-10T00:00:00.000Z",
        expires_at: "2026-10-11T00:00:00.000Z",
        limits,
        report_url: @env.get_env_var(
          "ACTQL_TEST_EFFECT_REVIEW_REPORT_FIXTURE_URL",
        ).unwrap(),
        artifact_url: @env.get_env_var(
          "ACTQL_TEST_EFFECT_REVIEW_UPLOAD_FIXTURE_URL",
        ).unwrap(),
        access: (_, _) => {
          abort("confirmed review repeated a Provider observation")
        },
      },
      upload_context,
      upload_journal,
      authority,
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
  let continuation_bytes = crypto
    .open_private_evidence(
      key,
      "continuation_record",
      checkpoint.checkpoint.continuation_state_cid,
      continuation.body,
    )
    .unwrap()
  assert_eq(
    checkpoint.checkpoint.continuation_state_cid,
    "sha256:" + @sha.hex(continuation_bytes),
  )
  let doubled = @checkpoint.seal_checkpoint(
    {
      ..checkpoint.checkpoint,
      continuation_state_cid: "sha256:" +
      @sha.hex(@sha.digest(continuation_bytes)),
    },
    limits,
  ).unwrap()
  let before_rejected_continuation = store.capacity_usage().unwrap().reserved_bytes
  assert_true(
    store.prepare_effect_checkpoint_custody(
      doubled,
      @utf8.decode(continuation_bytes),
      authority,
      crypto,
      key,
    )
    is Err(DigestMismatch),
  )
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    before_rejected_continuation,
  )
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
          let cleanup_observation = Ref("cleanup callback not reached")
          assert_true(
            work.admit_resolution(
              wire,
              authentication,
              reviewers,
              keys,
              () => true,
              () => {
                let cleanup = work.retry_cleanup()
                cleanup_failed.val = cleanup is Err(Retention(_))
                cleanup_observation.val = match cleanup {
                  Err(Retention(_)) => "retention cleanup pending"
                  Err(Journal(StateCollision)) => "journal custody collision"
                  Err(Journal(Closed)) => "journal closed"
                  Err(Journal(Physical(_))) => "journal physical failure"
                  Err(Journal(_)) => "journal custody rejected"
                  Err(Unavailable) => "review custody unavailable"
                  Err(_) => "review cleanup rejected"
                  Ok(_) => "review cleanup succeeded"
                }
                "2026-10-10T00:01:00.000Z"
              },
            )
            is Err(AuthorityDenied),
            msg=cleanup_observation.val[:],
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
  assert_true(
    retention.review_projection(() => true, 65536) is Err(Unavailable),
  )
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
