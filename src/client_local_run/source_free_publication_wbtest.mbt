///|
// Retention identity is calculated independently from the normative preimage,
// excluding its self field. It is not copied from a Core response.
let source_free_retention_wire : String = "{\"available_until\":\"2099-01-01T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"effective_data_policy_cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\",\"effective_retention_policy_cid\":\"sha256:26c9b75b2981e5ba8b9065557dbe04310659c8a3c4fe8695c83f38a72179db73\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"retention_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"version\":\"actql-result-retention-policy/0.1\"}"

///|
fn source_free_retention() -> @publication.PublicationContract raise {
  let value = @publication.admit_publication_contract(
    "result_retention_policy", source_free_retention_wire, 65536, 4096, 64,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(value),
    "sha256:26c9b75b2981e5ba8b9065557dbe04310659c8a3c4fe8695c83f38a72179db73",
  )
  value
}

///|
test "source-free formal invocation enters original preflight without Source or activation" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let plan = source_free_policy_plan(input).unwrap()
  let root = source_free_root()
  let host = source_free_shared_host(plan, root).unwrap()
  let current = account(Allow)
  let before = @resources.ledger_usage(root)
  let invocation = issue_local_source_free_invocation(
    host,
    compute_start(host),
    current,
  ).unwrap()
  assert_eq(local_run_invocation_source_cids(invocation), [])
  assert_true(local_run_invocation_source_evidence(invocation).is_empty())
  let intent = publication_intent_fixture(plan).unwrap()
  let preflight = check_local_publication_preflight(
    intent,
    invocation,
    current,
    [source_free_retention()],
  ).unwrap()
  assert_eq(local_publication_preflight_count(preflight), 1)
  assert_true(
    validate_local_publication_preflight_current(preflight, current) is Ok(_),
  )
  assert_true(
    validate_local_publication_preflight_current(preflight, account(Deny))
    is Err(AuthorizationMismatch),
  )
  assert_false(
    @strategy.captured_task_activation_granted(local_compute_run(host), 0),
  )
  assert_false(@strategy.captured_task_completed(local_compute_run(host), 0))
  assert_eq(@resources.ledger_usage(root), before)
  @strategy.stop_captured_dag(local_compute_run(host))
  @strategy.refresh_captured_retention(local_compute_run(host))
}

///|
test "source-free invocation refuses foreign start or missing original policy" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let first = source_free_shared_host(
    source_free_policy_plan(input).unwrap(),
    source_free_root(),
  ).unwrap()
  let second = source_free_shared_host(
    source_free_policy_plan(input).unwrap(),
    source_free_root(),
  ).unwrap()
  assert_true(
    issue_local_source_free_invocation(
      first,
      compute_start(second),
      account(Allow),
    )
    is Err(ForeignCompute),
  )
  assert_true(
    issue_local_source_free_invocation(
      first,
      compute_start(first),
      account(Deny),
    )
    is Err(AuthorizationMismatch),
  )
  let missing = source_free_shared_host(
    plan(input, "missing-policy-invocation"),
    source_free_root(),
  ).unwrap()
  assert_true(
    issue_local_source_free_invocation(
      missing,
      compute_start(missing),
      account(Allow),
    )
    is Err(Invocation(_)),
  )
  for host in [first, second, missing] {
    @strategy.stop_captured_dag(local_compute_run(host))
    @strategy.refresh_captured_retention(local_compute_run(host))
  }
}

///|
test "source-free preflight retains original plan full inventory and retention" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let plan = source_free_policy_plan(input).unwrap()
  let host = source_free_shared_host(plan, source_free_root()).unwrap()
  let invocation = issue_local_source_free_invocation(
    host,
    compute_start(host),
    account(Allow),
  ).unwrap()
  let intent = publication_intent_fixture(plan).unwrap()
  assert_true(
    check_local_publication_preflight(intent, invocation, account(Allow), [])
    is Err(PreflightMismatch),
  )
  let foreign = source_free_policy_plan(prepared(@input.Aql("SELECT 2 AS n"))).unwrap()
  assert_true(
    check_local_publication_preflight(
      publication_intent_fixture(foreign).unwrap(),
      invocation,
      account(Allow),
      [source_free_retention()],
    )
    is Err(ForeignCompute),
  )
  let ready = check_local_publication_preflight(
    intent,
    invocation,
    account(Allow),
    [source_free_retention()],
  ).unwrap()
  assert_true(physical_equal(ready.invocation, invocation))
  assert_true(physical_equal(ready.intent.plan, plan))
  @strategy.stop_captured_dag(local_compute_run(host))
  @strategy.refresh_captured_retention(local_compute_run(host))
}

///|
test "source-free SELECT one publishes original Result manifest and Receipt" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let plan = source_free_policy_plan(input).unwrap()
  let root = source_free_root()
  let host = source_free_shared_host(plan, root).unwrap()
  let current = account(Allow)
  let start = compute_start(host)
  let invocation = issue_local_source_free_invocation(host, start, current).unwrap()
  let preflight = check_local_publication_preflight(
    publication_intent_fixture(plan).unwrap(),
    invocation,
    current,
    [source_free_retention()],
  ).unwrap()
  let operations = start_local_compute_task(
      host,
      start,
      [],
      permit(input, current),
      current,
      tuple(),
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
  assert_true(
    @publication.publication_contract_json(receipt).contains(
      "\"source_evidence_cids\":[]",
    ),
  )
  assert_true(
    validate_local_result_publication_current(result, account(Deny))
    is Err(AuthorizationMismatch),
  )
  assert_true(
    issue_local_run_receipt(
      manifest,
      normalization,
      account(Deny),
      1048576,
      100000,
      64,
    )
    is Err(AuthorizationMismatch),
  )
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
