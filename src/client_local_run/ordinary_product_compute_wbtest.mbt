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
  let before = @resources.ledger_usage(root)
  let host = configure_source_free_local_compute_on_ledger(
    original,
    root,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let run = local_compute_run(host)
  assert_true(physical_equal(@strategy.captured_dag_ledger(run), root))
  let configured = source_free_setup_usage(root, run, before)
  // Binding the packaged module starts no attempt and reserves no future
  // task. The actual authorized start must refuse the exhausted original.
  let current = account(Allow)
  assert_true(
    start_local_compute_task(
      host,
      compute_start(host),
      [],
      permit(original.input, current),
      current,
      tuple(),
      context_cid(),
    )
    is Err(
      Managed(@managed.Execution(@strategy.Physical(@resources.ExecutionLimit)))
    ),
  )
  assert_eq(@resources.ledger_usage(root), configured)
  assert_false(@strategy.captured_task_completed(run, 0))
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 16777216L)
  assert_eq(@resources.ledger_usage(root).held_bytes, 0L)
  @resources.close_shared_capacity(wasm).unwrap()
  @resources.settle_shared_capacity(wasm).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
}

///|
test "packaged Local task activation retains the completed producer through a quantum-one join" {
  let original = plan(
    prepared(
      @input.Aql(
        "WITH seed AS (SELECT 1 AS n) FROM seed AS l |> JOIN seed AS r ON l.n = r.n MAX_OUTPUT_ROWS 1 |> SELECT l.n + r.n AS n |> RESULT answer",
      ),
    ),
    "ordinary-packaged-join",
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
    retained_bytes: 536870912L,
    execution_bytes: 603979776L,
  }).unwrap()
  let wasm = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let transfers = @resources.reserve_shared_capacity(root, 12582912L).unwrap()
  let setup = @resources.reserve_shared_capacity(root, 8388608L).unwrap()
  let host = configure_source_free_local_compute_on_ledger(
    original,
    root,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let run = local_compute_run(host)
  let current = account(Allow)
  let allowed = permit(original.input, current)
  let start = compute_start(host)
  let outputs : Map[Int, @execution.ManagedCompletedOutput[Int]] = Map([])
  let retained : Map[Int, @managed.LocalManagedDispatchOperations[Int]] = Map([])
  let available = Ref(true)
  let tasks : Array[Int] = []
  while @strategy.next_captured_task(run) is Some(task) {
    assert_true(tasks.length() < 10)
    let producers = local_compute_producers(host)
    let inputs = producers.map(index => outputs.get(index).unwrap())
    let operations = match
      start_local_compute_task(
        host,
        start,
        inputs,
        allowed,
        current,
        tuple(),
        context_cid(),
      ) {
      Ok(Some(operations)) => operations
      Err(Dispatch(Implementation(Implementation(error)))) =>
        fail("packaged task dispatch: " + error.to_string())
      Err(Dispatch(Implementation(MissingOutput))) =>
        fail("packaged task dispatch: MissingOutput")
      Err(Dispatch(Implementation(ForeignCandidate))) =>
        fail("packaged task dispatch: ForeignCandidate")
      _ => fail("packaged task activation refused before its input transfer")
    }
    for index, transfer in operations.inputs {
      let source = retained.get(producers[index]).unwrap()
      for row in 0..<(source.output_rows)() {
        (transfer.append)((source.output_row)(row).unwrap()).unwrap()
      }
      (transfer.finish)().unwrap()
    }
    let mut executed = false
    for _ in 0..<1000 {
      if (operations.advance)(1).unwrap().complete {
        executed = true
        break
      }
    }
    assert_true(executed)
    (operations.prepare_finalization)(task, operations.storage_bytes, () => {
      available.val
    }).unwrap()
    let mut finalized = false
    for _ in 0..<1000 {
      if (operations.advance_finalization)(1).unwrap().complete {
        finalized = true
        break
      }
    }
    assert_true(finalized)
    (operations.settle)().unwrap()
    outputs[task] = (operations.complete)(task, operations.storage_bytes, () => {
      available.val
    }).unwrap()
    retained[task] = operations
    tasks.push(task)
  }
  assert_true(tasks.length() >= 2)
  let last = retained.get(tasks[tasks.length() - 1]).unwrap()
  assert_eq((last.output_rows)(), 1)
  assert_eq((last.output_row)(0).unwrap(), "{\"n\":2}")
  available.val = false
  for offset in 0..<tasks.length() {
    let task = tasks[tasks.length() - offset - 1]
    (retained.get(task).unwrap().close)()
    @strategy.close_captured_task_output(run, task)
    assert_true((retained.get(task).unwrap().cleanup_refresh)())
  }
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  for capacity in [setup, transfers, wasm] {
    @resources.close_shared_capacity(capacity).unwrap()
    @resources.settle_shared_capacity(capacity).unwrap()
  }
  let usage = @resources.ledger_usage(root)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
}

///|
test "ordinary Python numeric PIVOT configures on the finite original root" {
  let assets = @host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("packaged Environment evidence missing")
  }
  let environment = @host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  ).unwrap()
  let document =
    #|WITH r AS (
    #|  SELECT 'east' AS side, 1 AS v UNION ALL
    #|  SELECT 'west', 2 UNION ALL SELECT 'west', 3
    #|)
    #|FROM r |> PIVOT(SUM(v) FOR side IN ('east','west'))
  let input = @input.prepare_local_input_material(
    Aql(document),
    environment,
    None,
    Some(
      @input.bind_local_input_context(environment, [], "python.local").unwrap(),
    ),
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let original = plan(input, "ordinary-python-numeric-pivot")
  let installed = @local.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(
    @local.prepare_source_free_local_requirements(
      original.prepared,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is None,
  )
  let root = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 4096,
    holdings: 4096,
    transfer_bytes: 67108864L,
    retained_bytes: 536870912L,
    execution_bytes: 603979776L,
  }).unwrap()
  let wasm = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let before = @resources.ledger_usage(root)
  let host = configure_source_free_local_compute_on_ledger(
    original,
    root,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let run = local_compute_run(host)
  assert_true(physical_equal(@strategy.captured_dag_ledger(run), root))
  assert_true(@strategy.captured_task_activation_required(run))
  let setup = @resources.ledger_usage(root)
  assert_eq(setup.attempts, before.attempts)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  @resources.close_shared_capacity(wasm).unwrap()
  @resources.settle_shared_capacity(wasm).unwrap()
  let closed = @resources.ledger_usage(root)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
}
