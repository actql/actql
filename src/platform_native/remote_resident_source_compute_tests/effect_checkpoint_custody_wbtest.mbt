// Real Native continuation/Checkpoint persistence. Reopening the Store retains
// the original live Ledger; it is not Host/Coordinator restart acceptance.

///|
fn retained_effect_checkpoint_store(
  consumer : @resident.ResidentSourceCompute,
  inputs : @strategy.CapturedEffectInputs,
  review : @resident.ResidentEffectReviewCheckpoint,
  computation : @resident.ResidentEffectCaptureCustody,
  preview : @resident.ResidentEffectPreviewCustody,
  store : @store.Store,
  authority : String,
  crypto : @signature.Library,
  key : Bytes,
  sqlite : @sqlite.Library,
  path : String,
  limits : @checkpoint.WireLimits,
) -> @store.Store raise {
  let mut store = store
  let open = () => {
    @store.open_store(sqlite, path, authority, 536870912L, 8L, 262144L).unwrap()
  }
  let baseline = consumer.usage().reserved_retention_bytes
  let physical_baseline = store.capacity_usage().unwrap().reserved_bytes
  assert_true(
    store.prepare_effect_checkpoint_custody(
      review.checkpoint,
      review.continuation_wire + "\n",
      authority,
      crypto,
      key,
    )
    is Err(DigestMismatch),
  )
  assert_true(
    store.prepare_effect_checkpoint_custody(
      review.checkpoint,
      review.continuation_wire,
      retained_compute_cid("f"),
      crypto,
      key,
    )
    is Err(StateCollision),
  )
  let persist = () => {
    consumer.persist_effect_review_checkpoint(
      store, inputs, review, crypto, key,
    )
  }
  let lost = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-continuation-persisted" && !lost.val {
      lost.val = true
      store.close().unwrap() |> ignore
    }
  })
  let first = persist()
  guard first is Err({ issue: Store(Closed), custody: Some(custody), }) else {
    fail("partial continuation commit must retain both custody handles")
  }
  let reservation = consumer.usage().reserved_retention_bytes - baseline
  assert_true(reservation > 0L)
  store = open()
  computation.restore_store(store).unwrap()
  preview.restore_store(store).unwrap()
  custody.restore_store(store).unwrap()
  assert_true(
    custody.waiting_projection("2026-10-10T00:00:00.000Z", ["r"], limits)
    is Err(Store(Database(@sqlite.NotFound))),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + reservation)
  let partial_bytes = store.capacity_usage().unwrap().reserved_bytes
  assert_true(partial_bytes > physical_baseline)
  assert_true(partial_bytes < physical_baseline + reservation)
  let inspection = sqlite
    .open_database(path + "/.actql-publication.sqlite3", 262144L)
    .unwrap()
  let holding = review.checkpoint.checkpoint_cid
  let original = inspection
    .read("effect_continuation_custody", holding)
    .unwrap()
  assert_true(original.body != @utf8.encode(review.continuation_wire))
  assert_false(@utf8.decode(original.body).contains("Count__c"))
  assert_eq(
    crypto
    .open_private_evidence(
      key,
      "continuation_record",
      review.checkpoint.checkpoint.continuation_state_cid,
      original.body,
    )
    .unwrap(),
    @utf8.encode(review.continuation_wire),
  )
  assert_true(
    crypto.open_private_evidence(
      key,
      "effect_capture",
      review.checkpoint.checkpoint.continuation_state_cid,
      original.body,
    )
    is Err(CipherRejected),
  )
  assert_true(
    store.restore_effect_checkpoint_custody(
      review.checkpoint,
      review.continuation_wire,
      authority,
      crypto,
      Bytes::make(32, 0),
    )
    is Err(PrivateEvidence(CipherRejected)),
  )
  let lost_checkpoint = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-checkpoint-persisted" && !lost_checkpoint.val {
      lost_checkpoint.val = true
      store.close().unwrap() |> ignore
    }
  })
  assert_true(persist() is Err({ issue: Store(Closed), custody: Some(_), }))
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + reservation)
  store = open()
  computation.restore_store(store).unwrap()
  preview.restore_store(store).unwrap()
  custody.restore_store(store).unwrap()
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    physical_baseline + reservation,
  )
  assert_true(physical_equal(persist().unwrap(), custody))
  let (confirmed, continuation) = custody.confirm().unwrap()
  assert_eq(confirmed.artifact.checkpoint_cid, holding)
  assert_eq(continuation, review.continuation_wire)
  assert_eq(
    inspection.read("effect_continuation_custody", holding).unwrap().body,
    original.body,
  )
  let checkpoint_record = inspection
    .read("effect_checkpoint_custody", holding)
    .unwrap()
  assert_eq(
    crypto
    .open_private_evidence(key, "checkpoint", holding, checkpoint_record.body)
    .unwrap(),
    @utf8.encode(review.checkpoint.wire),
  )
  let waiting = custody
    .waiting_projection("2026-10-10T00:00:00.000Z", ["r"], limits)
    .unwrap()
  assert_true(waiting.contains("waiting_checkpoint"))
  assert_true(waiting.contains("original-effect-run"))
  assert_true(waiting.contains(holding))
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + reservation)
  // A committed terminal whose acknowledgement is lost still owns capacity.
  // Retry completes retirement through the same pair, never a fresh holding.
  let lost_cleanup = Ref(false)
  store.observe_allocation(step => {
    if step == "effect-checkpoint-terminal-saved" && !lost_cleanup.val {
      lost_cleanup.val = true
      store.close().unwrap() |> ignore
    }
  })
  assert_true(custody.retry_cleanup() is Err(Store(Closed)))
  assert_eq(consumer.usage().reserved_retention_bytes, baseline + reservation)
  store = open()
  computation.restore_store(store).unwrap()
  preview.restore_store(store).unwrap()
  custody.restore_store(store).unwrap()
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    physical_baseline + reservation,
  )
  assert_true(
    custody.waiting_projection("2026-10-10T00:00:00.000Z", ["r"], limits)
    is Err(Store(RecoveryRequired)),
  )
  assert_true(custody.retry_cleanup().unwrap())
  assert_false(custody.retry_cleanup().unwrap())
  assert_true(custody.confirm() is Err(Unavailable))
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, physical_baseline)
  assert_true(computation.confirm() is Ok(_))
  assert_true(preview.confirm() is Ok(_))
  let retired = store
    .restore_effect_checkpoint_custody(
      review.checkpoint,
      review.continuation_wire,
      authority,
      crypto,
      key,
    )
    .unwrap()
  assert_true(retired.persist() is Err(RecoveryRequired))
  assert_false(retired.retry_cleanup().unwrap())
  for table in ["effect_continuation_custody", "effect_checkpoint_custody"] {
    let terminal = inspection.read(table, holding).unwrap()
    assert_eq(terminal.revision, 1L)
    assert_false(@utf8.decode(terminal.body).contains("ciphertext"))
  }
  inspection.close()
  println(
    "retained-effect-checkpoint: original pair confirmed before waiting projection; partial persistence and cleanup retried without duplicate reservations",
  )
  store
}
