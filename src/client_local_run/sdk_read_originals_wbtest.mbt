///|
priv struct SDKReadFixture {
  preflight : LocalPublicationPreflight
  reference_wire : String
  account : @authorization.AdmittedAccountConfiguration
  original : @host.ClientLocalRunPolicyOriginal
  selection : @publication.LocalSDKResultReadSelection
  owner : @publication.PublicationCommitPreparation
  view : @publication.PublicationCommitReadView
  result : LocalResultPublication
  payload : @payload.PublicationPayloadRecord?
  cleanup : () -> Unit raise
}

///|
// Actual Common checked Source-free task/export/Receipt and full stored-chain
// validation. Epoch/adoption and physical binding literals are metadata fixtures,
// not authenticated Host custody, Store ACK, real Wasm or product admission.
fn sdk_read_fixture(
  bound_scope? : Bool = false,
  sealed_payload? : Bool = false,
) -> SDKReadFixture raise {
  let at = "2026-10-13T00:00:00.001Z"
  let bootstrap = @host.client_local_product_sdk_bootstrap_originals(
    "/private/local", at,
  ).unwrap()
  let current = @authorization.admit_account_configuration_json(
    @utf8.decode(bootstrap.original.common.account),
  ).unwrap()
  let env = environment()
  let input = @input.prepare_local_input_material(
    @input.Aql("SELECT 1 AS n"),
    env,
    None,
    Some(@input.bind_local_input_context(env, [], "local").unwrap()),
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let selected : @authorization.AccessTuple = {
    principal: "local-cli",
    connection: "local",
    resource: "run",
    operation: "submit",
  }
  let permit = @authorization.bind_dispatch_authorization(
    current,
    selected,
    Activation,
    @host.prepared_client_identity(@input.local_prepared_program(input)).program_definition_cid,
    context_cid(),
  ).unwrap()
  let authority = if bound_scope {
    "sha256:" +
    @sha.hex(
      @host.client_local_authority_scope_body(
        current,
        "sha256:" + "a".repeat(64),
        selected.principal,
        selected.connection,
      ).unwrap(),
    )
  } else {
    "sha256:" + "b".repeat(64)
  }
  let reference_wire = submitted_rows_reference_wire.replace(
    old="sha256:" + "b".repeat(64),
    new=authority,
  )
  let reference = @host.admit_client_submission_reference_record(reference_wire).unwrap()
  let plan = prepare_source_free_local_publication_run(
    input,
    authority,
    @host.client_submission_reference_record_request_id(reference),
    permit,
    current,
    selected,
    context_cid(),
    "sha256:" + "c".repeat(64),
    "local",
    "sdk-original-run",
    at,
    "2026-10-14T00:00:00.001Z",
    (source_free_original_policy_cid, source_free_original_policy),
  ).unwrap()
  let root = source_free_root()
  let host = source_free_shared_host(plan, root).unwrap()
  let start = confirm_local_compute_start(
    host,
    plan.request,
    @publication.publication_contract_identity(plan.definition),
    true,
    true,
    false,
    false,
    permit,
    current,
    selected,
    context_cid(),
  ).unwrap()
  let invocation = issue_local_source_free_invocation(host, start, current).unwrap()
  let retention = @host.issue_client_local_run_retention_policy(
    bootstrap.profile,
    at,
  ).unwrap()
  let original = @host.bind_client_local_run_policy_original(
    bootstrap.profile,
    reference,
    plan.request,
    plan.definition,
    retention,
    at,
    "sha256:" + "a".repeat(64),
    @publication.local_sdk_result_read_selection_cid(bootstrap.read),
  ).unwrap()
  let intent = prepare_local_publication_intent(
    plan,
    "local-results",
    current.configuration_cid(),
    "sha256:" + "4".repeat(64),
    at,
    "publication-attempt",
    "sha256:" + "5".repeat(64),
    None,
    "2026-10-13T00:00:01.000Z",
    {
      max_results: 16,
      max_wire_bytes: 1048576,
      max_nodes: 100000,
      max_depth: 64,
    },
  ).unwrap()
  let preflight = check_local_publication_preflight(
    intent,
    invocation,
    current,
    [retention],
  ).unwrap()
  let operations = start_local_compute_task(
      host,
      start,
      [],
      permit,
      current,
      selected,
      context_cid(),
    )
    .unwrap()
    .unwrap()
  let mut done = false
  for _ in 0..<1000 {
    if (operations.advance)(1).unwrap().complete {
      done = true
      break
    }
  }
  assert_true(done)
  let available = Ref(true)
  (operations.prepare_finalization)(0, operations.storage_bytes, () => {
    available.val
  }).unwrap()
  done = false
  for _ in 0..<1000 {
    if (operations.advance_finalization)(1).unwrap().complete {
      done = true
      break
    }
  }
  assert_true(done)
  (operations.settle)().unwrap()
  let completed = (operations.complete)(0, operations.storage_bytes, () => {
    available.val
  }).unwrap()
  let limits : @host.PublicationOutputExportLimits = {
    max_result_fields: 100,
    max_result_mapping_work: 100000,
    max_result_order_work: 1000000,
    max_result_workspace_entries: 100000,
    max_rows: 100000,
    values: {
      max_nodes: 10000,
      max_text_bytes: 65536,
      max_depth: 64,
      max_work: 100000,
    },
    payload_wire: {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 64,
    },
    logical_wire: {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 64,
    },
    schema: {
      max_fields: 100,
      max_bytes: 65536,
      max_nodes: 10000,
      max_depth: 64,
    },
    max_batch_bytes: 65536,
  }
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    limits.max_rows,
    limits.values,
    100000,
    65536,
  ).unwrap()
  assert_eq((operations.output_rows)(), 1)
  assert_eq((operations.output_row)(0).unwrap(), "{\"n\":1}")
  @execution.append_managed_publication_bridge_wire(
    bridge,
    (operations.output_row)(0).unwrap(),
    {
      max_bytes: 65536,
      max_nodes: 10000,
      max_depth: 64,
      max_text_bytes: 65536,
    },
  ).unwrap()
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let transform = @host.start_captured_managed_result_publication_export(
    local_compute_run(host),
    0,
    completed,
    bridge,
    output,
    limits,
    max_pins=10,
  ).unwrap()
  done = false
  for _ in 0..<1000 {
    if transform.advance(1).unwrap().0 {
      done = true
      break
    }
  }
  assert_true(done)
  let exported = transform.finish().unwrap()
  // The existing codec emits a canonical rows array in chunks, including
  // its final tail. A transport chunk is not a single SDK row.
  let bytes = StringBuilder()
  let mut eof = false
  for _ in 0..<3 {
    match exported.next().unwrap() {
      Some(chunk) => bytes.write_string(chunk)
      None => {
        eof = true
        break
      }
    }
  }
  assert_true(eof)
  bytes.write_string(exported.finish().unwrap())
  assert_eq(bytes.to_string(), "[{\"n\":1}]")
  assert_eq(exported.row_count().unwrap(), 1)
  assert_eq(exported.result_fields().unwrap(), ["n"])
  let result = issue_local_preflight_result_publication(
    preflight, 0, exported, current, 1048576, 100000, 64,
  ).unwrap()
  let manifest = issue_local_run_manifest(
    host,
    invocation,
    [result],
    current,
    1048576,
    100000,
    64,
  ).unwrap()
  let normalization = issue_local_run_normalization(plan).unwrap()
  let receipt = issue_local_run_receipt(
    manifest, normalization, current, 1048576, 100000, 64,
  ).unwrap()
  let contracts = local_result_publication_contracts(result)
  let snapshot = @publication.admit_captured_result_snapshot(
    contracts[0],
    contracts[1],
    "[{\"n\":1}]",
    ["n"],
    65536,
    4096,
    64,
  ).unwrap()
  let (capture, original_receipt) = start_local_run_capture(
    manifest,
    normalization,
    [snapshot],
    current,
    1048576,
    100000,
    64,
    1000000,
  ).unwrap()
  let mut captured_ready = false
  for _ in 0..<10000 {
    if capture.advance(16).unwrap().0 {
      captured_ready = true
      break
    }
  }
  assert_true(captured_ready)
  let captured = capture.finish().unwrap()
  assert_eq(
    @publication.publication_contract_identity(original_receipt),
    @publication.publication_contract_identity(receipt),
  )
  let schema = exported.result_schema_wire().unwrap()
  let schema_cid = exported.result_schema_cid().unwrap()
  let payload = if sealed_payload {
    let request = prepare_local_preflight_payload_request(
      preflight,
      0,
      result,
      current,
      "sha256:" + "4".repeat(64),
      "sha256:" + "2".repeat(64),
      9L,
    ).unwrap()
    let record = @payload.prepare_publication_payload_record(request)
    @payload.commit_publication_payload_transition(
      @payload.prepare_publication_payload_reserved(record).unwrap(),
      true,
    ).unwrap()
    |> ignore
    @payload.commit_publication_payload_transition(
      @payload.prepare_publication_payload_writing(record).unwrap(),
      true,
    ).unwrap()
    |> ignore
    @payload.commit_publication_payload_transition(
      @payload.prepare_publication_payload_owned(record, {
        device: 7UL,
        inode: 9UL,
      }).unwrap(),
      true,
    ).unwrap()
    |> ignore
    @payload.commit_publication_payload_transition(
      @payload.prepare_publication_payload_sealed(
        record,
        { device: 7UL, inode: 9UL, size: 9L, },
        "sha256:8cd664de3db2ebc3a68f6507c3d786addcdaffc9393fea9ce94364129ba27a98",
      ).unwrap(),
      true,
    ).unwrap()
    |> ignore
    Some(record)
  } else {
    None
  }
  let binding = match payload {
    Some(record) =>
      issue_local_preflight_sealed_result_binding(
        preflight, 0, result, record, current, 1048576, 100000, 64,
      ).unwrap()
    None =>
      @publication.issue_durable_result_binding(
        plan.definition,
        contracts[0],
        invocation.invocation,
        contracts[1],
        contracts[3],
        retention,
        "sha256:" + "1".repeat(64),
        ["n"],
        schema,
        "sha256:" + "2".repeat(64),
        "sha256:" + "4".repeat(64),
        1,
        9,
        "8cd664de3db2ebc3a68f6507c3d786addcdaffc9393fea9ce94364129ba27a98",
        1048576,
        100000,
        64,
      ).unwrap()
  }
  @publication.validate_result_schema_wire(schema_cid, schema, 65536, 4096, 64).unwrap()
  let (index, owner) = prepare_local_preflight_commit_candidate(
    preflight,
    manifest,
    normalization,
    receipt,
    captured,
    [binding],
    "2026-10-13T00:00:03.000Z",
    current,
    {
      max_results: 16,
      max_wire_bytes: 1048576,
      max_nodes: 100000,
      max_depth: 64,
    },
    1000000,
  ).unwrap()
  let mut ready = false
  for _ in 0..<10000 {
    if owner.advance(16).unwrap().0 {
      ready = true
      break
    }
  }
  assert_true(ready)
  let view = owner.finish_view().unwrap()
  owner
  .begin_observed_commit(
    view,
    preflight.intent.request,
    preflight.intent.attempt,
    index,
  )
  .unwrap()
  ready = false
  for _ in 0..<10000 {
    if owner.advance_observed_commit(view, 16).unwrap().0 {
      ready = true
      break
    }
  }
  assert_true(ready)
  owner.finish_observed_commit(view).unwrap() |> ignore
  let cleanup = () => {
    owner.release_observed_commit(view).unwrap()
    owner.release_view(view).unwrap()
    exported.cancel()
    @execution.close_managed_publication_bridge(bridge)
    available.val = false
    (operations.close)()
    @strategy.close_captured_task_output(local_compute_run(host), 0)
    assert_true((operations.cleanup_refresh)())
    @strategy.stop_captured_dag(local_compute_run(host))
    @strategy.refresh_captured_retention(local_compute_run(host))
    assert_eq(@resources.ledger_usage(root).held_bytes, 0L)
    assert_eq(@resources.ledger_usage(root).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
  }
  {
    preflight,
    reference_wire,
    account: current,
    original,
    selection: bootstrap.read,
    owner,
    view,
    result,
    payload,
    cleanup,
  }
}

///|
test "SDK read originals bind actual Common stored chain selected sink and saved finite expiry" {
  let fixture = sdk_read_fixture()
  let read = prepare_local_sdk_read_originals(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    "2026-10-13T00:00:04.000Z",
    16,
  ).unwrap()
  let bodies = [0, 1, 2].map(index => {
    local_sdk_read_original(read, index).unwrap()
  })
  assert_true(
    bodies[0].0.contains(
      "\"domain\":\"python_local_read.authorization_context\"",
    ),
  )
  assert_true(
    bodies[1].0.contains("\"expires_at\":\"2026-10-14T00:00:00.001Z\""),
  )
  assert_true(bodies[1].0.contains("\"max_bytes\":65536,\"max_uses\":1"))
  assert_true(bodies[2].0.contains("\"purpose\":\"python-local-read\""))
  assert_true(bodies[2].0.contains("\"sink\":\"sdk-rows\""))
  assert_false(bodies[2].0.contains("native_local_read"))
  assert_false(bodies[2].0.contains("stdout"))
  assert_true(local_sdk_read_original(read, 3) is Err(InvalidOriginal))
  assert_eq(
    @host.client_local_run_policy_original_read_expires_at(fixture.original),
    "2026-10-14T00:00:00.001Z",
  )
  (fixture.cleanup)()
}

///|
test "SDK read refuses expired foreign selection adoption and current authority without renewal" {
  let fixture = sdk_read_fixture()
  let body = @host.client_local_run_policy_original_body(fixture.original)
  let invoke = (selection, adoption, name, format, at) => {
    prepare_local_sdk_read_originals(
      fixture.preflight,
      fixture.account,
      fixture.original,
      selection,
      adoption,
      fixture.owner,
      fixture.view,
      name,
      format,
      "sdk-read-original",
      at,
      16,
    )
  }
  assert_true(
    invoke(
      fixture.selection,
      "sha256:" + "a".repeat(64),
      "answer",
      "jsonl",
      "2026-10-14T00:00:00.001Z",
    )
    is Err(Expired),
  )
  assert_true(
    invoke(
      fixture.selection,
      "sha256:" + "a".repeat(64),
      "answer",
      "jsonl",
      "2026-10-14T00:00:00.000Z",
    )
    is Ok(_),
  )
  assert_true(
    invoke(
      fixture.selection,
      "sha256:" + "a".repeat(64),
      "answer",
      "jsonl",
      "not-a-timestamp",
    )
    is Err(Projection(_)),
  )
  assert_true(
    prepare_local_sdk_read_originals(
      fixture.preflight,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      "answer",
      "jsonl",
      "sdk-read-original",
      "2026-10-13T00:00:04.000Z",
      0,
    )
    is Err(StoredChain(Projection(DeliveryIssuanceInvalidLimit))),
  )
  assert_true(
    invoke(
      fixture.selection,
      "sha256:" + "b".repeat(64),
      "answer",
      "jsonl",
      "2026-10-13T00:00:04.000Z",
    )
    is Err(InvalidOriginal),
  )
  assert_true(
    invoke(
      fixture.selection,
      "sha256:" + "a".repeat(64),
      "answer",
      "csv",
      "2026-10-13T00:00:04.000Z",
    )
    is Err(InvalidSelection),
  )
  let other = @publication.issue_local_sdk_result_read_selection(
    "sha256:" + "f".repeat(64),
    "sha256:" + "e".repeat(64),
  ).unwrap()
  assert_true(
    invoke(
      other,
      "sha256:" + "a".repeat(64),
      "answer",
      "jsonl",
      "2026-10-13T00:00:04.000Z",
    )
    is Err(InvalidOriginal),
  )
  assert_true(
    prepare_local_sdk_read_originals(
      fixture.preflight,
      account(Deny),
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      "answer",
      "jsonl",
      "sdk-read-original",
      "2026-10-13T00:00:04.000Z",
      16,
    )
    is Err(Preflight(AuthorizationMismatch)),
  )
  assert_eq(@host.client_local_run_policy_original_body(fixture.original), body)
  (fixture.cleanup)()
  assert_true(
    invoke(
      fixture.selection,
      "sha256:" + "a".repeat(64),
      "answer",
      "jsonl",
      "2026-10-13T00:00:04.000Z",
    )
    is Err(StoredChain(Commit(CommitEncoding))),
  )
}

///|
// A Host/FFI byte view can mutate the exact buffer exposed by the original.
fn sdk_read_original_buffer(value : Bytes) -> FixedArray[Byte] = "%identity"

///|
test "SDK binding accepts separately admitted policy identities and rejects changed dependencies" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let plan = fixture.preflight.intent.plan
  let request = @host.admit_client_request_identity_record_wire(
    @host.client_request_identity_record_wire(plan.request).unwrap(),
  ).unwrap()
  let definition = @publication.admit_publication_contract(
    "run_definition",
    @publication.publication_contract_json(plan.definition),
    8192,
    512,
    8,
  ).unwrap()
  assert_false(physical_equal(request, plan.request))
  assert_false(physical_equal(definition, plan.definition))
  let body = @host.client_local_run_policy_original_body(fixture.original)
  let original_wire = @utf8.decode(body)
  let bootstrap = @host.client_local_product_sdk_bootstrap_originals(
    "/private/local",
    @host.client_local_run_policy_original_issued_at(fixture.original),
  ).unwrap()
  let independent = @host.admit_client_local_run_policy_original(
    @utf8.encode(original_wire),
    bootstrap.profile,
    @host.admit_client_submission_reference_record(fixture.reference_wire).unwrap(),
    request,
    definition,
    "sha256:" + "a".repeat(64),
    @publication.local_sdk_result_read_selection_cid(fixture.selection),
  ).unwrap()
  let invoke = finite => {
    validate_sdk_read_original_binding(
      local_sdk_read_source(fixture.preflight),
      fixture.account,
      finite,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      "answer",
      "jsonl",
      "sdk-read-original",
    )
  }
  assert_true(invoke(independent) is Ok(_))
  let exposed = sdk_read_original_buffer(body)
  for
    target in [
      "sha256:" + "a".repeat(64),
      @publication.local_sdk_result_read_selection_cid(fixture.selection),
    ] {
    let changed = @utf8.encode(
      original_wire.replace(old=target, new="sha256:" + "0".repeat(64)),
    )
    assert_eq(changed.length(), body.length())
    for index in 0..<body.length() {
      exposed[index] = changed[index]
    }
    assert_true(invoke(fixture.original) is Err(InvalidOriginal))
    assert_true(invoke(independent) is Ok(_))
  }
  let restored = @utf8.encode(original_wire)
  for index in 0..<body.length() {
    exposed[index] = restored[index]
  }
  assert_true(invoke(fixture.original) is Ok(_))
  exposed[0] = b'!'
  assert_true(invoke(fixture.original) is Err(InvalidOriginal))
}

///|
test "SDK metadata lookup rechecks aliased policy mutation after the Store callback" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let body = @host.client_local_run_policy_original_body(fixture.original)
  let exposed = sdk_read_original_buffer(body)
  let calls = Ref(0)
  let observed_table = Ref("")
  assert_true(
    sdk_delivery_observe(
      fixture,
      (table, _) => {
        observed_table.val = table
        calls.val += 1
        exposed[0] = b'!'
        Ok(None)
      },
      () => Ok(()),
    )
    is Err(Store(Preparation(InvalidOriginal))),
  )
  assert_eq(calls.val, 1)
  assert_eq(observed_table.val, "delivery_attempt")
  exposed[0] = b'{'
  assert_true(
    sdk_delivery_observe(fixture, (_, _) => Ok(None), () => Ok(()))
    is Err(MissingAttempt),
  )
}
