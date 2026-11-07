///|
test "ordinary Python source-free configuration uses the packaged assets and original root" {
  let original = plan(
    prepared(@input.Aql("SELECT 1 AS n")),
    "ordinary-python-root",
  )
  let assets = @host.client_local_product_assets()
  let installed = @local.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(
    @local.prepare_client_local_sequences(
      original.prepared,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is Some(_),
  )
  let original_requirements = @local.prepare_source_free_local_requirements(
    original.prepared,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let quote = original_requirements.maximum_limits()
  assert_eq(quote.retained_bytes, 200000000L)
  assert_eq(quote.execution_bytes, 536870912L)
  let root = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 4096,
    holdings: 4096,
    transfer_bytes: 67108864L,
    retained_bytes: 536870912L,
    execution_bytes: 603979776L,
  }).unwrap()
  let wasm = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let transfers = @resources.reserve_shared_capacity(root, 12582912L).unwrap()
  let setup = @resources.reserve_shared_capacity(root, 8388608L).unwrap()
  let host = match
    configure_source_free_local_compute_on_ledger(
      original,
      root,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ) {
    Ok(host) => host
    Err(Configuration) => fail("ordinary original-root configuration refused")
    Err(_) => fail("ordinary original-root compute binding refused")
  }
  let run = local_compute_run(host)
  assert_true(physical_equal(@strategy.captured_dag_ledger(run), root))
  assert_true(@strategy.captured_task_activation_required(run))
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  @resources.close_shared_capacity(setup).unwrap()
  @resources.settle_shared_capacity(setup).unwrap()
  @resources.close_shared_capacity(transfers).unwrap()
  @resources.settle_shared_capacity(transfers).unwrap()
  @resources.close_shared_capacity(wasm).unwrap()
  @resources.settle_shared_capacity(wasm).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
}

///|
test "ordinary Python insufficient original root refuses without a replacement or retained task" {
  let original = plan(
    prepared(@input.Aql("SELECT 1 AS n")),
    "ordinary-short-root",
  )
  let assets = @host.client_local_product_assets()
  let installed = @local.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let root = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 4096,
    holdings: 4096,
    transfer_bytes: 67108864L,
    // The existing Wasm holding exhausts this explicit fixture root.
    // Keep a real insufficient original, independent of quote reductions.
    retained_bytes: 16777216L,
    execution_bytes: 16777216L,
  }).unwrap()
  let wasm = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let configured = configure_source_free_local_compute_on_ledger(
    original,
    root,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  )
  let refused = match configured {
    Ok(host) => {
      println(
        "ORIGINAL_SHORT_ROOT unexpectedly configured on its original ledger",
      )
      let run = local_compute_run(host)
      assert_true(physical_equal(@strategy.captured_dag_ledger(run), root))
      @strategy.stop_captured_dag(run)
      @strategy.refresh_captured_retention(run)
      false
    }
    Err(Configuration) => {
      println("ORIGINAL_SHORT_ROOT Configuration refusal")
      true
    }
    Err(_) => fail("original root failed outside configuration capacity")
  }
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 16777216L)
  assert_eq(@resources.ledger_usage(root).held_bytes, 0L)
  @resources.close_shared_capacity(wasm).unwrap()
  @resources.settle_shared_capacity(wasm).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
  assert_true(refused)
}
