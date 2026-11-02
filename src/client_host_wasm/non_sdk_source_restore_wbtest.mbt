///|
// Actual exported restore caller and canonical Core material codec. Account,
// buffer stop and physical current are explicit component ports. No physical
// Store, saved business state, dispatch, VM parent or ordinary ACK is supplied.
fn non_sdk_source_restore_case(
  nonce : Int64,
  retain_source_view : Bool,
) -> Unit raise {
  let (value, preparation, pool, capacity, source_slot, environment_slot) = published_preparation_fixture(
    nonce, "SELECT 1 AS n",
  )
  assert_eq(prepare_program(nonce, 2), 0)
  let submitted = preparation.submitted.unwrap()
  let input = @preparation.local_submitted_preparation_input(submitted)
  let account = @authorization.admit_account_configuration({
    account_id: "source-restore-account",
    entries: [
      {
        entry_id: "source-restore",
        outcome: Allow,
        scope: {
          principal: All,
          connection: AnyOf(["python.local"]),
          resource: AnyOf(["runs"]),
          operation: AnyOf(["submit"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
  let tuple : @authorization.AccessTuple = {
    principal: "local-user",
    connection: "python.local",
    resource: "runs",
    operation: "submit",
  }
  let context = "sha256:" + "a".repeat(64)
  let authority = "sha256:" + "b".repeat(64)
  let policy = "sha256:" + "c".repeat(64)
  let permit = @authorization.bind_dispatch_authorization(
    account,
    tuple,
    @authorization.Activation,
    @host.prepared_client_identity(@preparation.local_prepared_program(input)).program_definition_cid,
    context,
  ).unwrap()
  let original = @local_run.prepare_source_free_local_run(
    input,
    authority,
    "original-source-restore",
    permit,
    account,
    tuple,
    context,
    policy,
    "local",
    "original-source-run",
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
    submitted=Some(submitted),
  ).unwrap()
  let configuration = value.environments[1]
  let material_wire = @local_run.export_local_run_materials(
    original,
    configuration.environment,
    configuration.wire,
    None,
  ).unwrap()
  let cid = @local_run.local_run_definition_cid(original)
  let restored = @local_run.restore_local_run_materials(material_wire, cid).unwrap()
  let request = @local_run.local_run_request(original)
  assert_true(
    @host.client_request_input_cid(request) !=
    @host.source_free_caller_input_intent_cid(),
  )
  let request_bytes = @utf8.encode(
    @host.client_request_identity_record_wire(request).unwrap(),
  )
  let request_slot = @buffers.reserve_buffer(pool, request_bytes.length(), 0L, () => {
    true
  }).unwrap()
  @buffers.fill_buffer(pool, request_slot, 0, request_bytes.length(), i => {
    Some(request_bytes[i])
  }).unwrap()
  @buffers.seal_buffer(pool, request_slot, 16384, 64).unwrap()
  let material_bytes = @utf8.encode(material_wire)
  let material_slot = @buffers.reserve_buffer(
    pool,
    material_bytes.length(),
    0L,
    () => true,
  ).unwrap()
  @buffers.fill_buffer(pool, material_slot, 0, material_bytes.length(), i => {
    Some(material_bytes[i])
  }).unwrap()
  @buffers.seal_buffer(pool, material_slot, 16384, 64).unwrap()
  value.run_configurations[3] = {
    borrow: @buffers.borrow_buffer(pool, environment_slot, () => true).unwrap(),
    account,
    tuple,
    authority_scope_cid: authority,
    context_cid: context,
    policy_cid: policy,
    run_namespace: "local",
    source_free_result_policy: None,
    host_current: None,
    sdk: None,
  }
  value.restorations[4] = {
    borrow: @buffers.borrow_buffer(pool, material_slot, () => true).unwrap(),
    invoked: true,
    expected_definition_cid: Some(cid),
    outcome: Some(Ok(restored)),
    sdk_configuration: None,
    sdk_submission: None,
    saved_original: None,
  }
  let record : StoredRun = {
    borrow: @buffers.borrow_buffer(pool, request_slot, () => true).unwrap(),
    slot: request_slot,
    input_physical: 0,
    configuration: 3,
    preparation: 2,
    invoked: false,
    restoration: None,
    physical_start_reserved: false,
    native_source_reserved: false,
    source_free_compute_reserved: false,
    normalization: None,
    outcome: None,
    finite_policy: None,
    sdk_submission: None,
    saved_snapshot: None,
  }
  value.runs[5] = record
  if !retain_source_view {
    // The same codec-bound submitted carrier remains. This does not recreate
    // Source, lower a document or issue a new request during restoration.
    preparation.source = None
  }
  assert_eq(restore_run(nonce, 5, 4), 0)
  guard record.outcome is Some(Ok(actual)) else {
    fail(
      "the actual non-SDK caller must retain its original Source request domain",
    )
  }
  assert_eq(@local_run.local_run_request(actual), request)
  assert_eq(@local_run.local_run_definition_cid(actual), cid)
  assert_true(
    physical_equal(
      @local_run.local_run_prepared(actual),
      @host.client_task_run_materials_retained_program(
        @host.client_task_run_materials_retained_input(restored),
      ),
    ),
  )
  assert_true(physical_equal(preparation.submitted.unwrap(), submitted))
  assert_true(
    physical_equal(stored_preparation_input(preparation).unwrap(), input),
  )
  assert_false(
    record.physical_start_reserved ||
    record.native_source_reserved ||
    record.source_free_compute_reserved,
  )
  assert_eq(value.runs.length(), 1)
  assert_eq(close_run(nonce, 5), 0)
  assert_eq(close_restoration(nonce, 4), 0)
  assert_eq(close_run_configuration(nonce, 3), 0)
  @buffers.close_buffer(pool, request_slot).unwrap()
  @buffers.close_buffer(pool, material_slot).unwrap()
  published_preparation_close(
    nonce, pool, capacity, source_slot, environment_slot,
  )
}

///|
test "non-SDK published Source restore retains same carrier from its original live Source" {
  non_sdk_source_restore_case(7321L, true)
}

///|
test "non-SDK published Source restore retains same codec carrier without a live Source view" {
  non_sdk_source_restore_case(7322L, false)
}
