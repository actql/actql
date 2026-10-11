///|
/// Physical HTTPS upload of this original holder's confirmed review. The test
/// server acknowledges artifact transport only; it is not a Cloud Run Owner.
fn retained_holder_upload_original_review(
  work : @effect_provider.NativeResidentEffectReview,
  journal_path : String,
  store : @store.Store,
  publication : @effect_provider.NativeResidentEffectReviewPublication,
  context : @resident.ResidentEffectReviewInputContext,
  journal : @dispatch_journal.Journal,
  authority : String,
) -> Unit raise {
  let required = name => @env.get_env_var(name).unwrap()
  let http = @http.load_library(required("ACTQL_TEST_NATIVE_HTTP_LIBRARY")).unwrap()
  let client = http
    .create_authenticated_client(
      required("ACTQL_TEST_NATIVE_HTTP_CA"),
      Bearer(required("ACTQL_TEST_NATIVE_HTTP_SECRET")),
      262144L,
      2000,
      5000,
    )
    .unwrap()
  let url = required("ACTQL_TEST_EFFECT_REVIEW_UPLOAD_FIXTURE_URL")
  let report_url = required("ACTQL_TEST_EFFECT_REVIEW_REPORT_FIXTURE_URL")
  let (before_report, before_wire) = work
    .review_projection(() => true, 65536)
    .unwrap()
  // Inject a separately admitted report for the same dispatch into the actual
  // journal. Its protocol validity cannot acknowledge this holder's original
  // paired Store report. Restore the exact original bytes before asserting,
  // so the normal retry/cleanup cases retain their original physical custody.
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
  let original_checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(
    before_report,
  )
  let foreign_checkpoint = @checkpoint.seal_checkpoint(
    {
      ..original_checkpoint.checkpoint,
      checkpoint_id: original_checkpoint.checkpoint.checkpoint_id + "-foreign",
    },
    limits,
  ).unwrap()
  let foreign_persisted = @checkpoint.confirm_checkpoint_persisted(
    foreign_checkpoint,
    foreign_checkpoint.wire,
  ).unwrap()
  let dispatch = @remote.remote_effect_checkpoint_report_dispatch(before_report)
  let foreign_report = @remote.prepare_remote_effect_checkpoint_report(
    dispatch, foreign_persisted, limits,
  ).unwrap()
  assert_true(
    @remote.remote_effect_checkpoint_report_identity(foreign_report) !=
    @remote.remote_effect_checkpoint_report_identity(before_report),
  )
  let database = @sqlite.load_library(
      required("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"),
    )
    .unwrap()
    .open_database(journal_path, 262144L)
    .unwrap()
  let report_key = @remote.dispatch_request_identity(dispatch)
  let saved = database
    .read("site_effect_checkpoint_report", report_key)
    .unwrap()
  let changed = database
    .compare_exchange(
      "site_effect_checkpoint_report",
      report_key,
      saved.revision,
      @utf8.encode(@remote.remote_effect_checkpoint_report_json(foreign_report)),
    )
    .unwrap()
  let mismatch = work.upload_review_projection(client, report_url, url, () => {
    true
  })
  database
  .compare_exchange(
    "site_effect_checkpoint_report",
    report_key,
    changed,
    saved.body,
  )
  .unwrap()
  |> ignore
  database.close_checked().unwrap()
  assert_true(mismatch is Err(InvalidResponse))
  assert_true(
    work.upload_review_projection(client, report_url, url, () => false)
    is Err(Review(_)),
  )
  // The fixture's first response is bare HTTP success, not a typed ACK.
  // No artifact upload may follow it, and the original report stays pending.
  assert_true(
    work.upload_review_projection(client, report_url, url, () => true)
    is Err(Report(Protocol(_))),
  )
  assert_true(
    work.upload_review_projection(client, report_url, url, () => true)
    is Err(HttpStatus(503)),
  )
  let reads = Ref(0)
  assert_true(
    work.upload_review_projection(client, report_url, url, () => {
      reads.val += 1
      reads.val < 5
    })
    is Err(Review(_)),
  )
  assert_eq(reads.val, 5)
  let target_reads = Ref(0)
  let configured = {
    ..publication,
    access: (_, _) => {
      target_reads.val += 1
      abort("confirmed review repeated a Provider observation")
    },
  }
  assert_true(
    work.publish_review(store, client, configured, () => false)
    is Err(ReadAuthorityDenied),
  )
  // Changed retry crypto custody cannot replace the original report or send
  // another Checkpoint. Its first retention configuration remains authoritative.
  assert_true(
    work.publish_review(
      store,
      client,
      { ..configured, key: Bytes::make(32, 255), },
      () => true,
    )
    is Err(EvidencePersistence(Unavailable)),
  )
  let published = work
    .publish_review(store, client, configured, () => true)
    .unwrap()
  assert_eq(
    @remote.remote_effect_checkpoint_report_json(published),
    @remote.remote_effect_checkpoint_report_json(before_report),
  )
  assert_eq(target_reads.val, 0)
  let (after_report, after_wire) = work
    .review_projection(() => true, 65536)
    .unwrap()
  assert_eq(after_wire, before_wire)
  assert_eq(
    @remote.remote_effect_checkpoint_report_identity(after_report),
    @remote.remote_effect_checkpoint_report_identity(before_report),
  )
  // Readback uses the genuine original consumer context, not the live Review
  // factory. Its original Accepted report performs no additional report send;
  // only the same confirmed review bytes are retried through the same uploader.
  let before_restore = store.capacity_usage().unwrap().reserved_bytes
  let restore_upload = authorize => {
    @effect_provider.upload_native_resident_original_review_projection(
      context,
      journal,
      store,
      authority,
      publication.crypto,
      publication.key,
      publication.limits,
      client,
      report_url,
      url,
      authorize,
    )
  }
  assert_true(
    restore_upload(() => false) is Err(OriginalReview(EvidenceDenied)),
  )
  assert_true(
    @effect_provider.upload_native_resident_original_review_projection(
      context,
      journal,
      store,
      retained_compute_cid("f"),
      publication.crypto,
      publication.key,
      publication.limits,
      client,
      report_url,
      url,
      () => true,
    )
    is Err(OriginalReview(Store(StateCollision))),
  )
  let original_reads = Ref(0)
  assert_true(
    restore_upload(() => {
      original_reads.val += 1
      original_reads.val < 3
    })
    is Err(OriginalReview(EvidenceDenied)),
  )
  assert_eq(original_reads.val, 3)
  // Artifact save can outlive disclosure authority. Keep its original report
  // and bytes, but do not turn remote success into current completion permission.
  let save_reads = Ref(0)
  assert_true(
    restore_upload(() => {
      save_reads.val += 1
      save_reads.val < 5
    })
    is Err(OriginalReview(EvidenceDenied)),
  )
  assert_eq(save_reads.val, 5)
  restore_upload(() => true).unwrap()
  let (restored_report, restored_wire) = context
    .read_original_review_projection(
      journal,
      store,
      authority,
      publication.crypto,
      publication.key,
      publication.limits,
      () => true,
    )
    .unwrap()
  assert_eq(restored_wire, before_wire)
  assert_eq(
    @remote.remote_effect_checkpoint_report_json(restored_report),
    @remote.remote_effect_checkpoint_report_json(before_report),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, before_restore)
  assert_eq(target_reads.val, 0)
  assert_true(client.close())
}
