///|
fn restored_output_fixture(
  name : String,
  wrong_content? : Bool = false,
  runtime_bundle_cid? : String? = None,
  input_binding_cid? : String? = None,
  budget_cid? : String? = None,
) -> (
  @journal.Journal,
  @remote.DispatchRequest,
  String,
  String,
  @filesystem.NativeFileGeneration,
  @site.ExecutionSite,
) raise {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap_or_else(() => {
    abort("private physical root required")
  })
  let db_root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap_or_else(() => {
      abort("private SQLite root required")
    },
  )
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap_or_else(() => {
      abort("SQLite library required")
    }),
  ).unwrap()
  let cid = "sha256:" + "a".repeat(64)
  let bundle = runtime_bundle_cid.unwrap_or(cid)
  let request = @remote.prepare_dispatch_request(
    "authority",
    cid,
    "task",
    1,
    name,
    "site",
    1,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    input_binding_cid.unwrap_or(cid),
    cid,
    budget_cid.unwrap_or(cid),
    cid,
    cid,
  ).unwrap()
  let site = @site.create_site("site", 1, bundle, 4, 4, 1000L, 1000L).unwrap()
  let control = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let path = db_root + "/" + name + ".sqlite3"
  let journal = @journal.open_journal(library, path, 1048576L, control).unwrap()
  let (_, record) = journal.accept(request).unwrap()
  let capability = @remote.register_remote_execution_capability(
    site, bundle, "local", "local/1", "strategy/1", cid,
  ).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, capability).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  let file = @retained_file.begin_native_retained_task_file(root, name, 10L).unwrap()
  file.append("[{\"id\":3}]").unwrap()
  let actual_cid = "sha256:" + @sha.hex(b"[{\"id\":3}]")
  let saved_cid = if wrong_content {
    "sha256:" + @sha.hex(b"[{\"id\":4}]")
  } else {
    actual_cid
  }
  file.seal(saved_cid, 10).unwrap()
  let generation = file.sealed_generation().unwrap()
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    cid,
    cid,
    cid,
    1,
    [actual_cid],
    [10L],
    [1],
    1,
    4096,
    10L,
  ).unwrap()
  let holding = @remote.remote_output_holding_evidence_cid(
    request, "original-generation", 10L,
  ).unwrap()
  journal
  .commit_transition(
    @remote.prepare_retain_remote_output(record, "original-generation", holding).unwrap(),
  )
  .unwrap()
  let measurement = @remote.prepare_remote_managed_output_measurement(
    1,
    1,
    1,
    1,
    [1],
    [1],
    [1],
    [1],
    [0],
    [1],
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    "original-generation",
    holding,
    cid,
    cid,
    cid,
    cid,
    @manifest.manifest_cid(manifest),
    @remote.remote_managed_output_measurement_cid(measurement),
    1,
    10L,
  ).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_managed_output_evidence_kind(),
    cid,
  ).unwrap()
  let evidence = @remote.issue_remote_managed_output_evidence(
    issuer, record, subject,
  ).unwrap()
  let custody = @journal.prepare_native_output_file_custody(
    request, name, generation, saved_cid, "original-generation", manifest,
  ).unwrap()
  journal
  .commit_evidence_transition(
    @remote.prepare_durable_execution_evidence(record, evidence).unwrap(),
    evidence,
    subject,
    measurement,
    file_custody=Some(custody),
  )
  .unwrap()
  assert_true(journal.close())
  // Reopen both the journal and the physical file independently. The sealed
  // writer's finalizer keeps its committed file; no old object is returned.
  let fresh_site = @site.create_site("site", 1, bundle, 4, 4, 1000L, 1000L).unwrap()
  let reopened = @journal.open_journal(
    library,
    path,
    1048576L,
    @remote.create_site_dispatch_journal(fresh_site, "actql-remote-site/0.1").unwrap(),
  ).unwrap()
  (reopened, request, root, name, generation, fresh_site)
}

///|
test "native restored standard output verifies original bytes from reopened custody" {
  let (journal, request, root, name, generation, _) = restored_output_fixture(
    "standard-restored-output",
  )
  let before = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_true(
    @standard.restore_native_remote_standard_output(
      journal.observation(request).unwrap(),
      root,
      10L,
      () => true,
    )
    is @standard.NativeRestoredOutput(@runtime.NativeRemoteOutputReady(_)),
  )
  let physical = @filesystem.open_root(root).unwrap()
  assert_true(physical.verify_generation("output-" + name, generation))
  assert_true(physical.inspect_generation("stage-" + name) is Ok(None))
  let reader = physical.open_reader("output-" + name, generation).unwrap()
  assert_eq(reader.next(10).unwrap().bytes, b"[{\"id\":3}]")
  reader.close().unwrap()
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    before,
  )
  assert_false(
    @remote.remote_runtime_record_startable(journal.require(request).unwrap()),
  )
  physical.reclaim_generation("output-" + name, generation).unwrap()
  assert_true(journal.close())
}

///|
test "native restored standard output refuses incorrect content without changing execution evidence" {
  let (journal, request, root, name, generation, _) = restored_output_fixture(
    "standard-restored-corrupt",
    wrong_content=true,
  )
  let original = journal.observation(request).unwrap()
  let proof = @remote.remote_execution_evidence_cid(
    @journal.recovered_site_dispatch_evidence(original).unwrap(),
  )
  guard @standard.restore_native_remote_standard_output(original, root, 10L, () => {
      true
    })
    is @standard.NativeOutputRestorationPending(code, cleanup) else {
    fail("mismatched content admitted")
  }
  assert_eq(code, "output-restore-content")
  let current = journal.observation(request).unwrap()
  assert_eq(
    @remote.remote_execution_evidence_cid(
      @journal.recovered_site_dispatch_evidence(current).unwrap(),
    ),
    proof,
  )
  assert_false(
    @remote.remote_runtime_record_startable(
      @journal.recovered_site_dispatch_record(current),
    ),
  )
  let physical = @filesystem.open_root(root).unwrap()
  assert_true(physical.verify_generation("output-" + name, generation))
  assert_true(cleanup())
  assert_true(cleanup())
  assert_true(physical.inspect_generation("output-" + name) is Ok(None))
  assert_true(journal.close())
}

///|
test "native restored standard output refuses release progress and missing material" {
  let (journal, request, root, name, generation, _) = restored_output_fixture(
    "standard-restored-releasing",
  )
  let physical = @filesystem.open_root(root).unwrap()
  let record = journal.require(request).unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_release(record).unwrap())
  .unwrap()
  assert_true(
    @standard.restore_native_remote_standard_output(
      journal.observation(request).unwrap(),
      root,
      10L,
      () => true,
    )
    is @standard.NativeOutputRestorationPending(_, _),
  )
  assert_true(physical.verify_generation("output-" + name, generation))
  physical.reclaim_generation("output-" + name, generation).unwrap()
  assert_true(journal.close())
  let (missing, request, root, name, generation, _) = restored_output_fixture(
    "standard-restored-missing",
  )
  let physical = @filesystem.open_root(root).unwrap()
  physical.reclaim_generation("output-" + name, generation).unwrap()
  guard @standard.restore_native_remote_standard_output(
      missing.observation(request).unwrap(),
      root,
      10L,
      () => true,
    )
    is @standard.NativeOutputRestorationPending(code, cleanup) else {
    fail("missing bytes admitted")
  }
  assert_eq(code, "output-restore-physical")
  assert_true(cleanup())
  assert_false(
    @remote.remote_runtime_record_startable(missing.require(request).unwrap()),
  )
  assert_true(missing.close())
}

///|
test "native restored standard output rechecks current ownership during physical verification" {
  let (journal, request, root, _, _, _) = restored_output_fixture(
    "standard-restored-current",
  )
  let original = journal.observation(request).unwrap()
  let revision = @remote.dispatch_record_revision(
    @journal.recovered_site_dispatch_record(original),
  )
  let checks = Ref(0)
  guard @standard.restore_native_remote_standard_output(original, root, 10L, () => {
      checks.val += 1
      checks.val < 5
    })
    is @standard.NativeOutputRestorationPending(code, cleanup) else {
    fail("lost authority admitted")
  }
  assert_eq(code, "output-restore-current")
  assert_eq(checks.val, 5)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_false(
    @remote.remote_runtime_record_startable(journal.require(request).unwrap()),
  )
  assert_true(cleanup())
  assert_true(cleanup())
  assert_true(journal.close())
}
