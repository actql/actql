///|
test "managed Transfer failed completion preserves Site holding release custody" {
  let (run, issuer) = captured_graph_fixture(
    local_values_unary_chain=Some("select"),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        max_bytes: 1000,
        max_nodes: 200,
        max_depth: 4,
        max_columns: 4,
        max_order_work: 100,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let live = Ref(true)
  let (operations, _) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    live,
  )
  let transfer = @strategy.begin_captured_managed_transfer(
    run, 1, 16L, 32L, 64L,
  ).unwrap()
  let progress = @strategy.begin_managed_transfer_progress(transfer)
  assert_true(@strategy.record_managed_transfer_source_stop(progress))
  assert_true(
    @strategy.record_managed_transfer_source_site_settlement(progress),
  )
  assert_true(@strategy.record_managed_transfer_destination_created(progress))
  assert_true(
    @strategy.record_managed_transfer_destination_admission(
      progress,
      {
        distinct_material: true,
        distinct_generation: true,
        rows: 2,
        batches: 1,
        max_batch_rows: 2,
        max_batch_bytes: 64,
        transferred_bytes: 0L,
        retained_bytes: 32L,
      },
      16L,
      32L,
    ),
  )
  @strategy.settle_captured_managed_transfer(run, transfer, true).unwrap()
  assert_true(@strategy.record_managed_transfer_destination_holding(progress))
  assert_true(
    @strategy.record_managed_transfer_destination_site_settlement(progress),
  )
  assert_true(
    @strategy.record_managed_transfer_destination_cleanup_release(progress),
  )
  // Revoke the exact producer's physical availability after the destination
  // Site holding is acquired, before Core issues a successful Transfer receipt.
  live.val = false
  assert_true(
    @strategy.complete_captured_managed_transfer(run, transfer, 32L)
    is Err(MissingOutput),
  )
  assert_true(
    @strategy.prepare_managed_transfer_cleanup_step(progress)
    is Ok(TransferReclaimDestination),
  )
  assert_false(@strategy.record_managed_transfer_site_holding_release(progress))
  assert_true(@strategy.record_managed_transfer_destination_reclaimed(progress))
  assert_false(@strategy.record_managed_transfer_site_holding_release(progress))
  @strategy.abort_captured_managed_transfer(run, transfer, false).unwrap()
  assert_false(@strategy.record_managed_transfer_site_holding_release(progress))
  @strategy.abort_captured_managed_transfer(run, transfer, true).unwrap()
  assert_true(
    @strategy.prepare_managed_transfer_cleanup_step(progress)
    is Ok(TransferReleaseSiteHolding),
  )
  assert_true(@strategy.record_managed_transfer_site_holding_release(progress))
  assert_true(@strategy.record_managed_transfer_site_holding_release(progress))
  assert_true(
    @strategy.prepare_managed_transfer_cleanup_step(progress)
    is Ok(TransferFinished),
  )
  (operations.close)()
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}
