///|
fn completed_runtime_fixture(
  name : String,
  commit_evidence? : Bool = true,
) -> (
  DispatchRecord,
  RemoteExecutionEvidence,
  RemoteManagedOutputSubject,
  RemoteManagedOutputMeasurement,
) {
  let bundle = cid("a".repeat(64))
  let dispatch = request(name, 1, 1, bundle)
  let (_, record) = commit_dispatch_acceptance(
    prepare_dispatch_acceptance(journal(), dispatch).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_begin_provisioning(record, execution_capability()).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_begin_remote_execution(record).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_confirm_native_settled(record).unwrap(),
    true,
  ).unwrap()
  let holding = remote_output_holding_evidence_cid(
    dispatch, "original-material", 1L,
  ).unwrap()
  commit_dispatch_transition(
    prepare_retain_remote_output(record, "original-material", holding).unwrap(),
    true,
  ).unwrap()
  let measurement = prepare_remote_managed_output_measurement(
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
  let subject = prepare_remote_managed_output_subject(
    dispatch_request_identity(dispatch),
    "original-material",
    holding,
    cid("d".repeat(64)),
    cid("e".repeat(64)),
    cid("f".repeat(64)),
    cid("1".repeat(64)),
    cid("2".repeat(64)),
    remote_managed_output_measurement_cid(measurement),
    1,
    1L,
  ).unwrap()
  let evidence = issue_remote_managed_output_evidence(
    managed_output_issuer(),
    record,
    subject,
  ).unwrap()
  if commit_evidence {
    commit_dispatch_transition(
      prepare_durable_execution_evidence(record, evidence).unwrap(),
      true,
    ).unwrap()
  }
  (record, evidence, subject, measurement)
}

///|
test "completed runtime restoration acquires no resources or execution permission" {
  let (record, evidence, subject, measurement) = completed_runtime_fixture(
    "restore-original",
  )
  let revision = dispatch_record_revision(record)
  let custody = restore_remote_runtime_completed_custody(
    record, evidence, subject, measurement,
  ).unwrap()
  assert_true(remote_runtime_custody_operation_acquired(custody))
  assert_true(remote_runtime_custody_operation_settled(custody))
  assert_false(remote_runtime_custody_output_acquired(custody))
  assert_false(remote_runtime_custody_holding_acquired(custody))
  assert_false(remote_runtime_custody_bundle_acquired(custody))
  assert_false(remote_runtime_record_startable(record))
  assert_false(remote_runtime_custody_resources_reclaimed(custody))
  assert_true(
    prepare_remote_runtime_success(record, custody) is Err(MaterialUnavailable),
  )
  assert_true(
    prepare_owned_remote_runtime_cleanup(record, custody)
    is Err(MaterialUnavailable),
  )
  assert_false(confirm_remote_runtime_completed_restoration(record, custody))
  assert_true(remote_runtime_custody_acquire_output(custody))
  assert_true(remote_runtime_custody_acquire_holding(custody))
  assert_true(
    prepare_remote_runtime_success(record, custody) is Err(MaterialUnavailable),
  )
  assert_true(remote_runtime_custody_acquire_bundle(custody))
  assert_true(confirm_remote_runtime_completed_restoration(record, custody))
  assert_false(confirm_remote_runtime_completed_restoration(record, custody))
  assert_eq(
    prepare_remote_runtime_success(record, custody).unwrap(),
    RuntimeSuccessFinished,
  )
  assert_eq(dispatch_record_revision(record), revision)
}

///|
test "completed runtime restoration retains obligations across a stale revision or foreign occurrence" {
  let (record, evidence, subject, measurement) = completed_runtime_fixture(
    "restore-revision",
  )
  let custody = restore_remote_runtime_completed_custody(
    record, evidence, subject, measurement,
  ).unwrap()
  assert_true(remote_runtime_custody_acquire_bundle(custody))
  assert_true(remote_runtime_custody_acquire_output(custody))
  assert_true(remote_runtime_custody_acquire_holding(custody))
  let (foreign, _, _, _) = completed_runtime_fixture("restore-revision-foreign")
  assert_false(confirm_remote_runtime_completed_restoration(foreign, custody))
  assert_false(remote_runtime_custody_resources_reclaimed(custody))
  assert_true(
    prepare_owned_remote_runtime_cleanup(record, custody)
    is Err(MaterialUnavailable),
  )
  commit_dispatch_transition(
    prepare_begin_remote_release(record).unwrap(),
    true,
  ).unwrap()
  let revision = dispatch_record_revision(record)
  assert_false(confirm_remote_runtime_completed_restoration(record, custody))
  assert_true(
    prepare_owned_remote_runtime_cleanup(record, custody)
    is Err(MaterialUnavailable),
  )
  assert_eq(dispatch_record_revision(record), revision)
  assert_false(remote_runtime_record_released(record))
}

///|
test "completed runtime restoration refuses historical foreign and incomplete evidence" {
  let (record, evidence, subject, measurement) = completed_runtime_fixture(
    "restore-bound",
  )
  let (foreign_record, foreign_evidence, foreign_subject, foreign_measurement) = completed_runtime_fixture(
    "restore-foreign",
  )
  assert_true(
    restore_remote_runtime_completed_custody(
      record, foreign_evidence, foreign_subject, foreign_measurement,
    )
    is Err(DispatchIdentityMismatch),
  )
  assert_true(
    restore_remote_runtime_completed_custody(
      foreign_record, evidence, subject, measurement,
    )
    is Err(DispatchIdentityMismatch),
  )
  let changed_measurement = prepare_remote_managed_output_measurement(
    1,
    1,
    2,
    1,
    [1],
    [1],
    [1],
    [1],
    [0],
    [1],
  ).unwrap()
  assert_true(
    restore_remote_runtime_completed_custody(
      record, evidence, subject, changed_measurement,
    )
    is Err(DispatchIdentityMismatch),
  )
  let (incomplete, proof, output, measured) = completed_runtime_fixture(
    "restore-incomplete",
    commit_evidence=false,
  )
  assert_true(
    restore_remote_runtime_completed_custody(
      incomplete, proof, output, measured,
    )
    is Err(InvalidTransition),
  )
  commit_dispatch_transition(
    prepare_begin_remote_release(record).unwrap(),
    true,
  ).unwrap()
  assert_true(
    restore_remote_runtime_completed_custody(
      record, evidence, subject, measurement,
    )
    is Err(InvalidTransition),
  )
  commit_dispatch_transition(
    prepare_confirm_remote_release(record).unwrap(),
    true,
  ).unwrap()
  assert_true(
    restore_remote_runtime_completed_custody(
      record, evidence, subject, measurement,
    )
    is Err(InvalidTransition),
  )
  assert_true(remote_runtime_record_released(record))
}

///|
test "completed runtime cleanup restoration follows a current release without granting success" {
  let (record, evidence, subject, measurement) = completed_runtime_fixture(
    "restore-cleanup-current",
  )
  let custody = restore_remote_runtime_completed_custody(
    record, evidence, subject, measurement,
  ).unwrap()
  assert_true(remote_runtime_custody_acquire_bundle(custody))
  assert_true(remote_runtime_custody_acquire_output(custody))
  assert_true(remote_runtime_custody_acquire_holding(custody))
  commit_dispatch_transition(
    prepare_begin_remote_release(record).unwrap(),
    true,
  ).unwrap()
  let revision = dispatch_record_revision(record)
  assert_false(confirm_remote_runtime_completed_restoration(record, custody))
  let (_, foreign, foreign_subject, foreign_measurement) = completed_runtime_fixture(
    "restore-cleanup-foreign",
  )
  assert_false(
    confirm_remote_runtime_completed_cleanup_restoration(
      record, custody, foreign, foreign_subject, foreign_measurement,
    ),
  )
  assert_true(
    confirm_remote_runtime_completed_cleanup_restoration(
      record, custody, evidence, subject, measurement,
    ),
  )
  assert_false(
    confirm_remote_runtime_completed_cleanup_restoration(
      record, custody, evidence, subject, measurement,
    ),
  )
  assert_eq(dispatch_record_revision(record), revision)
  assert_false(remote_runtime_record_released(record))
  assert_true(prepare_remote_runtime_success(record, custody) is Err(_))
  let cleanup = prepare_owned_remote_runtime_cleanup(record, custody).unwrap()
  assert_eq(remote_runtime_step_action_code(cleanup), 3)
  assert_false(remote_runtime_custody_resources_reclaimed(custody))
}

///|
test "completed runtime cleanup observation refresh preserves exact completion and strict reconstruction" {
  let (source, _, _, _) = completed_runtime_fixture("cleanup-refresh-exact")
  let original = dispatch_record_durable_json(source).unwrap()
  let cached_journal = journal()
  let record = restore_durable_dispatch_record(
    cached_journal,
    admit_durable_dispatch_record(@utf8.encode(original)).unwrap(),
  ).unwrap()
  let copy = restore_durable_dispatch_record(
    journal(),
    admit_durable_dispatch_record(@utf8.encode(original)).unwrap(),
  ).unwrap()
  commit_dispatch_transition(prepare_begin_remote_release(copy).unwrap(), true).unwrap()
  let changed = admit_durable_dispatch_record(
    @utf8.encode(dispatch_record_durable_json(copy).unwrap()),
  ).unwrap()
  assert_true(
    restore_durable_dispatch_record(cached_journal, changed)
    is Err(StateCollision),
  )
  refresh_remote_completed_cleanup_observation(record, changed).unwrap()
  assert_eq(
    dispatch_record_durable_json(record),
    dispatch_record_durable_json(copy),
  )
  assert_false(remote_runtime_record_startable(record))
  assert_false(remote_runtime_record_released(record))
  assert_true(
    refresh_remote_completed_cleanup_observation(
      record,
      admit_durable_dispatch_record(@utf8.encode(original)).unwrap(),
    )
    is Err(StateCollision),
  )
}

///|
test "completed runtime cleanup observation refuses changed material foreign identity and terminal adoption" {
  let (record, _, _, _) = completed_runtime_fixture("cleanup-refresh-refused")
  let original = dispatch_record_durable_json(record).unwrap()
  let copy = restore_durable_dispatch_record(
    journal(),
    admit_durable_dispatch_record(@utf8.encode(original)).unwrap(),
  ).unwrap()
  commit_dispatch_transition(prepare_begin_remote_release(copy).unwrap(), true).unwrap()
  let body = dispatch_record_durable_json(copy).unwrap()
  let changed = admit_durable_dispatch_record(
    @utf8.encode(
      body.replace(old="original-material", new="replacement-material"),
    ),
  ).unwrap()
  assert_true(
    refresh_remote_completed_cleanup_observation(record, changed)
    is Err(StateCollision),
  )
  let (foreign, _, _, _) = completed_runtime_fixture("cleanup-refresh-foreign")
  assert_true(
    refresh_remote_completed_cleanup_observation(
      record,
      admit_durable_dispatch_record(
        @utf8.encode(dispatch_record_durable_json(foreign).unwrap()),
      ).unwrap(),
    )
    is Err(StateCollision),
  )
  commit_dispatch_transition(
    prepare_confirm_remote_release(copy).unwrap(),
    true,
  ).unwrap()
  assert_true(
    refresh_remote_completed_cleanup_observation(
      record,
      admit_durable_dispatch_record(
        @utf8.encode(dispatch_record_durable_json(copy).unwrap()),
      ).unwrap(),
    )
    is Err(StateCollision),
  )
  assert_eq(dispatch_record_durable_json(record), Ok(original))
  assert_true(
    refresh_remote_completed_cleanup_observation(
      copy,
      admit_durable_dispatch_record(
        @utf8.encode(dispatch_record_durable_json(copy).unwrap()),
      ).unwrap(),
    )
    is Err(StateCollision),
  )
  let (_, accepted) = commit_dispatch_acceptance(
    prepare_dispatch_acceptance(journal(), dispatch_record_request(record)).unwrap(),
    true,
  ).unwrap()
  assert_true(
    refresh_remote_completed_cleanup_observation(
      accepted,
      admit_durable_dispatch_record(
        @utf8.encode(dispatch_record_durable_json(accepted).unwrap()),
      ).unwrap(),
    )
    is Err(StateCollision),
  )
}
