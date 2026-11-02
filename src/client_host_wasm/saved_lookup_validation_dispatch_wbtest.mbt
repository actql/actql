///|
// Exercise the actual exported validation dispatch and existing typed callee.
// A missing original snapshot must refuse there, never manufacture a Run or
// validate from scalar metadata. No physical Host or normal admission is used.
fn saved_lookup_validation_dispatch_case(kind : Int) -> (Int, Int) raise {
  let root = @resources.create_ledger({
    planning_work: 10000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 65536L,
    retained_bytes: 65536L,
    execution_bytes: 33554432L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let pool = @buffers.open_pool_on_ledger(root, 65536L, 8, 4096).unwrap()
  assert_eq(
    install_buffer_instance(
      4901L,
      root,
      capacity,
      None,
      pool,
      8,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(4901L).unwrap()
  let input = @buffers.reserve_output_buffer(pool, 2, 0L, () => true).unwrap()
  @buffers.supply_buffer_output(pool, input, b"{}").unwrap()
  let borrow = @buffers.borrow_buffer(pool, input, () => true).unwrap()
  let slot = @buffers.reserve_output_buffer(pool, 2, 0L, () => true).unwrap()
  @buffers.supply_buffer_output(pool, slot, b"{}").unwrap()
  value.run_configurations[1] = {
    borrow,
    account: @authorization.admit_account_configuration_json(
      "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"local:operator\",\"entries\":[]}",
    ).unwrap(),
    tuple: {
      principal: "operator",
      connection: "local",
      resource: "run",
      operation: "read",
    },
    authority_scope_cid: "uninterpreted-dispatch-fixture",
    context_cid: "uninterpreted-dispatch-fixture",
    policy_cid: "uninterpreted-dispatch-fixture",
    run_namespace: "client_runs",
    source_free_result_policy: None,
    host_current: Some(77),
    sdk: None,
  }
  let record : StoredSubmissionProjection = {
    configuration: 1,
    kind,
    borrow: Ok(borrow),
    slot,
    saved_result: None,
    saved_snapshot: None,
    append_plan: None,
    failure_preparation: None,
    failure_plan: None,
    invoked: true,
    produced: true,
    output_closed: false,
  }
  value.submissions[10] = record
  let direct = validate_submission_lookup(4901L, 10, 77)
  let exported = validate_submission_append(4901L, 10, 77)
  // Retire the test's actual pool/borrow even on the original product counter.
  value.submissions.remove(10) |> ignore
  value.run_configurations.remove(1) |> ignore
  @buffers.return_buffer_borrow(pool, borrow).unwrap()
  @buffers.close_buffer(pool, slot).unwrap()
  @buffers.close_buffer(pool, input).unwrap()
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  instance.val = None
  (direct, exported)
}

///|
test "saved status exported validation reaches its existing original snapshot guard" {
  let (direct, exported) = saved_lookup_validation_dispatch_case(7)
  assert_eq(direct, -42)
  assert_eq(exported, -42)
}

///|
test "saved original descriptor exported validation reaches its existing original snapshot guard" {
  let (direct, exported) = saved_lookup_validation_dispatch_case(8)
  assert_eq(direct, -42)
  assert_eq(exported, -42)
}
