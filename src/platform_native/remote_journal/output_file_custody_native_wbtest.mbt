///|
fn file_custody_fixture(
  request : @remote.DispatchRequest,
) -> (
  NativeOutputFileCustody,
  @remote.RemoteExecutionEvidence,
  @remote.RemoteManagedOutputSubject,
  @remote.RemoteManagedOutputMeasurement,
) {
  let (_, original, _) = test_managed_output(request)
  let fields = @remote.remote_managed_output_subject_projection(original)
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    fields[4],
    fields[5],
    fields[6],
    1,
    [fields[7]],
    [1L],
    [1],
    1,
    4096,
    1L,
  ).unwrap()
  let (evidence, subject, measurement) = test_managed_output(
    request,
    manifest_cid=Some(@manifest.manifest_cid(manifest)),
  )
  let custody = prepare_native_output_file_custody(
    request,
    "exact-original-task",
    { device: 18446744073709551615UL, inode: 9007199254740993UL, size: 1L, },
    fields[4],
    fields[1],
    manifest,
  ).unwrap()
  (custody, evidence, subject, measurement)
}

///|
fn file_custody_journal(
  name : String,
) -> (
  Journal,
  @remote.DispatchRequest,
  @remote.DispatchRecord,
  String,
  @sqlite.Library,
) {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap_or_else(() => {
      abort("SQLite library required")
    }),
  ).unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap_or_else(() => {
    abort("private SQLite root required")
  })
  let path = root + "/" + name + "-" + @env.now().to_string() + ".sqlite3"
  let journal = open_journal(library, path, 1048576L, test_control(test_site())).unwrap()
  let request = test_request(name)
  let (_, record) = journal.accept(request).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, test_capability(test_site())).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  journal
  .commit_transition(
    @remote.prepare_retain_remote_output(
      record,
      "native-material",
      @remote.remote_output_holding_evidence_cid(request, "native-material", 1L).unwrap(),
    ).unwrap(),
  )
  .unwrap()
  (journal, request, record, path, library)
}

///|
test "native output file custody restores exact uint64 identity with typed completion" {
  let (journal, request, record, path, library) = file_custody_journal(
    "file-custody-roundtrip",
  )
  let (custody, evidence, subject, measurement) = file_custody_fixture(request)
  let transition = @remote.prepare_durable_execution_evidence(record, evidence).unwrap()
  journal
  .commit_evidence_transition(
    transition,
    evidence,
    subject,
    measurement,
    file_custody=Some(custody),
  )
  .unwrap()
  assert_true(journal.close())
  let reopened = open_journal(
    library,
    path,
    1048576L,
    test_control(test_site()),
  ).unwrap()
  let observation = reopened.observation(request).unwrap()
  let restored = recovered_site_dispatch_file_custody(observation).unwrap()
  assert_eq(
    native_output_file_custody_generation(restored).device,
    18446744073709551615UL,
  )
  assert_eq(
    native_output_file_custody_generation(restored).inode,
    9007199254740993UL,
  )
  assert_eq(native_output_file_custody_generation(restored).size, 1L)
  assert_eq(
    output_file_custody_json(restored).unwrap(),
    output_file_custody_json(custody).unwrap(),
  )
  assert_eq(
    @remote.remote_managed_output_subject_cid(
      recovered_site_dispatch_subject(observation).unwrap(),
    ),
    @remote.remote_managed_output_subject_cid(subject),
  )
  assert_eq(
    @remote.remote_execution_evidence_cid(
      recovered_site_dispatch_evidence(observation).unwrap(),
    ),
    @remote.remote_execution_evidence_cid(evidence),
  )
  assert_true(reopened.close())
}

///|
test "native output file custody commit failure rolls back both custody and completion" {
  let (journal, request, record, _, _) = file_custody_journal(
    "file-custody-commit-failure",
  )
  let (custody, evidence, subject, measurement) = file_custody_fixture(request)
  let key = @remote.dispatch_request_attempt_identity(request).unwrap()
  let transition = @remote.prepare_durable_execution_evidence(record, evidence).unwrap()
  let revision = @remote.dispatch_record_revision(record)
  test_fail_cancel_commit(journal.database, 1)
  assert_true(
    journal.commit_evidence_transition(
      transition,
      evidence,
      subject,
      measurement,
      file_custody=Some(custody),
    )
    is Err(Physical(_)),
  )
  assert_eq(@remote.dispatch_record_revision(record), revision)
  assert_true(
    journal.database.read("site_output_file", key) is Err(@sqlite.NotFound),
  )
  assert_true(
    journal.database.read("site_managed_observation", key)
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    journal.database.read("site_dispatch", key).unwrap().revision,
    revision.to_int64(),
  )
  journal
  .commit_evidence_transition(
    transition,
    evidence,
    subject,
    measurement,
    file_custody=Some(custody),
  )
  .unwrap()
  assert_eq(@remote.dispatch_record_revision(record), revision + 1)
  assert_true(
    recovered_site_dispatch_file_custody(journal.observation(request).unwrap())
    is Some(_),
  )
  assert_true(journal.close())
}

///|
test "native output file custody lost commit reply requires the exact original snapshot" {
  let (journal, request, record, path, library) = file_custody_journal(
    "file-custody-lost-reply",
  )
  let (custody, evidence, subject, measurement) = file_custody_fixture(request)
  let transition = @remote.prepare_durable_execution_evidence(record, evidence).unwrap()
  let revision = @remote.dispatch_record_revision(record)
  test_fail_cancel_commit_reply(journal.database, 1)
  assert_true(
    journal.commit_evidence_transition(
      transition,
      evidence,
      subject,
      measurement,
      file_custody=Some(custody),
    )
    is Err(Physical(_)),
  )
  assert_eq(@remote.dispatch_record_revision(record), revision)
  let key = @remote.dispatch_request_attempt_identity(request).unwrap()
  let original = journal.database.read("site_output_file", key).unwrap()
  let foreign = prepare_native_output_file_custody(
    request,
    custody.occurrence,
    { ..custody.generation, inode: 5UL, },
    custody.content_cid,
    custody.material_generation,
    custody.manifest,
  ).unwrap()
  assert_true(
    journal.commit_evidence_transition(
      transition,
      evidence,
      subject,
      measurement,
      file_custody=Some(foreign),
    )
    is Err(StateCollision),
  )
  assert_true(
    journal.commit_evidence_transition(
      transition, evidence, subject, measurement,
    )
    is Err(StateCollision),
  )
  assert_eq(
    journal.database.read("site_output_file", key).unwrap().body,
    original.body,
  )
  journal
  .commit_evidence_transition(
    transition,
    evidence,
    subject,
    measurement,
    file_custody=Some(custody),
  )
  .unwrap()
  assert_eq(@remote.dispatch_record_revision(record), revision + 1)
  assert_eq(
    journal.database.read("site_output_file", key).unwrap().revision,
    0L,
  )
  assert_true(journal.close())
  let reopened = open_journal(
    library,
    path,
    1048576L,
    test_control(test_site()),
  ).unwrap()
  assert_eq(
    recovered_site_dispatch_file_custody(reopened.observation(request).unwrap()).unwrap().generation.inode,
    custody.generation.inode,
  )
  assert_true(reopened.close())
}

///|
test "native output file custody rejects foreign request and changed typed manifest before persistence" {
  let (journal, request, record, _, _) = file_custody_journal(
    "file-custody-foreign",
  )
  let (custody, evidence, subject, measurement) = file_custody_fixture(request)
  let transition = @remote.prepare_durable_execution_evidence(record, evidence).unwrap()
  let key = @remote.dispatch_request_attempt_identity(request).unwrap()
  let foreign = prepare_native_output_file_custody(
    test_request("another-original"),
    custody.occurrence,
    custody.generation,
    custody.content_cid,
    custody.material_generation,
    custody.manifest,
  ).unwrap()
  assert_true(
    journal.commit_evidence_transition(
      transition,
      evidence,
      subject,
      measurement,
      file_custody=Some(foreign),
    )
    is Err(StateCollision),
  )
  let changed_manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    custody.manifest.schema_contract_cid,
    custody.manifest.view_contract_cid,
    custody.manifest.codec_contract_cid,
    1,
    [custody.content_cid],
    [1L],
    [1],
    1,
    4096,
    1L,
  ).unwrap()
  let changed = prepare_native_output_file_custody(
    request,
    custody.occurrence,
    custody.generation,
    custody.content_cid,
    custody.material_generation,
    changed_manifest,
  ).unwrap()
  assert_true(
    journal.commit_evidence_transition(
      transition,
      evidence,
      subject,
      measurement,
      file_custody=Some(changed),
    )
    is Err(StateCollision),
  )
  assert_true(
    journal.database.read("site_output_file", key) is Err(@sqlite.NotFound),
  )
  assert_true(
    journal.database.read("site_managed_observation", key)
    is Err(@sqlite.NotFound),
  )
  let body = output_file_custody_json(custody).unwrap()
  assert_true(
    admit_output_file_custody(
      request,
      body.replace(old="9007199254740993", new="09007199254740993"),
    )
    is Err(StateCollision),
  )
  assert_true(
    admit_output_file_custody(test_request("another-original"), body)
    is Err(StateCollision),
  )
  assert_true(journal.close())
}
