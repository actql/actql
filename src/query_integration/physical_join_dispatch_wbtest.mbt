///|
test "shared dispatch binds both completed join inputs and enforces native reservation and completion" {
  for
    (self_join, resident, cancelled) in [
      (false, false, false),
      (true, false, false),
      (false, true, false),
      (true, true, false),
      (false, true, true),
      (true, true, true),
    ] {
    let (run, issuer) = captured_graph_fixture(join=true, self_join~)
    let registry = search_registry()
    let host = @dbhost.configure_strategy_dispatch(
      run,
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      @connector.capability_registration_at(registry, 1).unwrap(),
      dispatch_test_generated(run),
      dispatch_test_limits(),
    ).unwrap()
    assert_eq(@dbhost.dispatch_excluded_realizations(host).length(), 0)
    @strategy.configure_strategy_search(run, {
      max_offers: 8,
      max_strategies: 16,
      max_work: 1000,
      max_revisions: 1,
    }).unwrap()
    let offered = search_offers(run, registry, [1, 2, 3, 4], Some(1L))
    let native = @strategy.prepare_task_offer(
      run,
      3,
      @connector.capability_registration_at(registry, 1).unwrap(),
      8,
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
      {
        transfer_bytes: 100000L,
        retained_bytes: 8000000L,
        execution_bytes: 134217728L,
      },
      100,
    ).unwrap()
    let native = if resident {
      let profile = @strategy.prepare_resident_profile(
        run,
        @connector.capability_registration_at(registry, 1).unwrap(),
        20000000L,
        Some(0L),
        Some(0L),
        Array::make(5, @strategy.ResidentImportEstimate::{
          milliseconds: Some(0L),
          transfer_bytes: 20L,
          scratch_bytes: 100L,
          table_bytes: 80L,
        }),
      ).unwrap()
      @strategy.resident_task_offer(run, native, profile).unwrap()
    } else {
      native
    }
    assert_true(
      @strategy.revise_strategy(
        run,
        [offered[0], offered[2], native, offered[6]],
        registry,
        None,
      )
      is Ok(Selected(_)),
    )
    for task in [1, 2] {
      let dispatch = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
      assert_eq(@dbhost.dispatch_task(dispatch), task)
      @dbhost.execute_local_dispatch(dispatch).unwrap()
    }
    @planning.close_mock_query_issuer(issuer)
    let dispatch = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
    assert_true(@dbhost.dispatch_is_native(dispatch))
    assert_eq(@dbhost.dispatch_task(dispatch), 3)
    let setup = @dbhost.take_native_dispatch(dispatch).unwrap()
    let env = if resident {
      let env = @strategy.begin_resident_environment(run, 3, 20000000L).unwrap()
      @strategy.confirm_resident_environment(run, env, 20000000L).unwrap()
      let inventory = @dbhost.dispatch_resident_inputs(host, 3).unwrap()
      assert_eq(inventory.length(), 2)
      assert_eq(inventory[0].0, 1)
      assert_eq(inventory[1].0, if self_join { 1 } else { 2 })
      for producer in (if self_join { [1] } else { [1, 2] }) {
        let table = @strategy.prepare_resident_table(
          run, env, producer, 80L, 1000, 10000, 10000,
        ).unwrap()
        let transfer = @strategy.begin_resident_transfer(run, table, 20L, 100L).unwrap()
        @strategy.charge_resident_transfer(run, transfer, 12L).unwrap()
        @strategy.settle_resident_transfer(run, transfer, true).unwrap()
        @strategy.complete_resident_transfer(run, transfer).unwrap()
      }
      Some(env)
    } else {
      None
    }
    let resident_inputs = env.map(env => {
      let left = @strategy.resident_table_at(run, env, 1).unwrap()
      let right = @strategy.resident_table_at(
        run,
        env,
        if self_join {
          1
        } else {
          2
        },
      ).unwrap()
      assert_true(
        @dbhost.borrow_configured_resident_inputs(
          setup,
          env,
          [left],
          1000,
          10000,
          10000,
        )
        is Err(ForeignCandidate),
      )
      if !self_join {
        // The first borrow succeeds; rejecting the second must return it.
        for _ in 0..<3 {
          assert_true(
            @dbhost.borrow_configured_resident_inputs(
              setup,
              env,
              [left, left],
              1000,
              10000,
              10000,
            )
            is Err(_),
          )
        }
        assert_true(
          @dbhost.borrow_configured_resident_inputs(
            setup,
            env,
            [right, left],
            1000,
            10000,
            10000,
          )
          is Err(_),
        )
      }
      let cancelled = @dbhost.borrow_configured_resident_inputs(
        setup,
        env,
        [left, right],
        1000,
        10000,
        10000,
      ).unwrap()
      let sql = @strategy.resident_inputs_read_plans(cancelled).map(
        @duckdb_compute.duckdb_resident_read_sql,
      )
      assert_eq(sql.length(), 2)
      assert_true(sql[0].contains("\"owned_input_0\""))
      assert_true(sql[1].contains("\"owned_input_1\""))
      @strategy.cancel_resident_inputs(cancelled).unwrap()
      assert_true(
        @strategy.cancel_resident_inputs(cancelled) is Err(InvalidCharge),
      )
      let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts
      assert_true(
        @dbhost.start_configured_strategy_compute_host(
          setup,
          _ => false,
          100000L,
          1000000L,
          resident=cancelled,
        )
        is Err(ForeignCandidate),
      )
      assert_eq(
        @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
        before,
      )
      @dbhost.borrow_configured_resident_inputs(
        setup,
        env,
        [left, right],
        1000,
        10000,
        10000,
      ).unwrap()
    })
    let transport : FixedComputeTestTransport = { settled: None, }
    let attempt = @dbhost.start_configured_strategy_compute_host(
      setup,
      current => {
        transport.settled is Some(expected) && physical_equal(current, expected)
      },
      100000L,
      1000000L,
      resident?=resident_inputs,
    ).unwrap()
    if resident_inputs is Some(inputs) {
      assert_true(
        @strategy.cancel_resident_inputs(inputs) is Err(InvalidCharge),
      )
    }
    if cancelled {
      let env = env.unwrap()
      @strategy.charge_task_execution_transfer(
        run,
        @strategy.captured_duckdb_execution(attempt),
        17L,
      ).unwrap()
      @strategy.close_task_execution(
        run,
        @strategy.captured_duckdb_execution(attempt),
      )
      @strategy.close_resident_environment(run, env).unwrap()
      assert_true(
        @strategy.settle_resident_environment(run, env) is Err(InvalidCharge),
      )
      let ledger = @strategy.captured_dag_ledger(run)
      let reserved = @resources.ledger_usage(ledger).reserved_execution_bytes
      @strategy.settle_task_execution(
        run,
        @strategy.captured_duckdb_execution(attempt),
        false,
      ).unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        reserved,
      )
      assert_true(
        @strategy.complete_task_execution(
          run,
          @strategy.captured_duckdb_execution(attempt),
        )
        is Err(Stopped),
      )
      assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
      assert_true(@strategy.captured_task_output(run, 2, Step(1)) is Some(_))
      @strategy.settle_task_execution(
        run,
        @strategy.captured_duckdb_execution(attempt),
        true,
      ).unwrap()
      @strategy.settle_resident_environment(run, env).unwrap()
      @strategy.close_captured_task_output(run, 1)
      @strategy.close_captured_task_output(run, 2)
      let usage = @resources.ledger_usage(ledger)
      assert_eq(usage.reserved_execution_bytes, 0L)
      assert_eq(usage.reserved_retention_bytes, 0L)
      assert_eq(usage.held_bytes, 0L)
      assert_eq(
        usage.transferred_bytes,
        17L + (if self_join { 12L } else { 24L }),
      )
      continue
    }
    let compute = @duckdb_compute.duckdb_compute_attempt_plan(
      @strategy.captured_duckdb_attempt(attempt),
    )
    assert_eq(@duckdb.fixed_compute_import_count(compute), 2)
    for port in [0, 1] {
      let read = @duckdb.fixed_import_input(
        @duckdb.fixed_compute_import(compute, port).unwrap(),
      )
      assert_eq(@execution.producer_read_input_index(read), port)
    }
    assert_eq(@duckdb.fixed_compute_join_output_ceiling(compute), Some(100))
    @duckdb_compute.begin_duckdb_compute_result(
      @strategy.captured_duckdb_attempt(attempt),
      [("id", @duckdb.Float64)],
    ).unwrap()
    @duckdb_compute.receive_duckdb_compute_chunk(
      @strategy.captured_duckdb_attempt(attempt),
      1,
      [input_cursor("[\"4008000000000000\"]")],
    ).unwrap()
    @duckdb_compute.finish_duckdb_compute_result(
      @strategy.captured_duckdb_attempt(attempt),
    ).unwrap()
    transport.settled = Some(@strategy.captured_duckdb_attempt(attempt))
    assert_true(
      @strategy.complete_task_execution(
        run,
        @strategy.captured_duckdb_execution(attempt),
      )
      is Err(Physical(InvalidCharge)),
    )
    @strategy.charge_task_execution_transfer(
      run,
      @strategy.captured_duckdb_execution(attempt),
      17L,
    ).unwrap()
    @strategy.settle_task_execution(
      run,
      @strategy.captured_duckdb_execution(attempt),
      true,
    ).unwrap()
    if resident {
      @strategy.confirm_captured_resident_output(run, attempt).unwrap()
    }
    @strategy.complete_task_execution(
      run,
      @strategy.captured_duckdb_execution(attempt),
    ).unwrap()
    @strategy.close_captured_task_output(run, 1)
    @strategy.close_captured_task_output(run, 2)
    let count = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
    assert_eq(@dbhost.dispatch_task(count), 4)
    @dbhost.execute_local_dispatch(count).unwrap()
    let output = @strategy.captured_task_output(run, 4, Step(0)).unwrap()
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(1)))
    @strategy.close_captured_task_output(run, 3)
    assert_true(@strategy.captured_task_output(run, 4, Step(0)) is Some(_))
    @strategy.close_captured_task_output(run, 4)
    if env is Some(env) {
      @strategy.close_resident_environment(run, env).unwrap()
      // Also proves rejected partial sets and both claimed ports were returned.
      @strategy.settle_resident_environment(run, env).unwrap()
    }
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(
      usage.transferred_bytes,
      17L + (if !resident { 0L } else if self_join { 12L } else { 24L }),
    )
  }
}

///|
test "adaptive join placement charges both ports including self join occurrences" {
  for self_join in [false, true] {
    let (run, _) = captured_graph_fixture(join=true, self_join~)
    let registry = search_registry()
    let host = adaptive_host(run, registry)
    let profiles = adaptive_profiles()
    profiles.push(profiles[0])
    profiles[2] = {
      ..profiles[2],
      native_capacity: {
        transfer_bytes: 100000L,
        retained_bytes: 8000000L,
        execution_bytes: 134217728L,
      },
      native_rates: [
        {
          ..profiles[2].native_rates[0],
          fixed_ms: Some(if self_join { 3L } else { 5L }),
        },
      ],
    }
    @dbhost.configure_dispatch_estimates(host, profiles, {
      max_offers: 8,
      max_strategies: 16,
      max_work: 1000,
      max_revisions: 4,
    }).unwrap()
    for _task in [1, 2] {
      let pending = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
      assert_false(@dbhost.dispatch_is_native(pending))
      @dbhost.execute_local_dispatch(pending).unwrap()
    }
    let pending = @dbhost.prepare_next_dispatch(host).unwrap().unwrap()
    assert_eq(@dbhost.dispatch_task(pending), 3)
    // After both inputs are observed, Local costs 2*(1+2)=6, or
    // 2*(1+1)=4 for a self join. Keeping only the last edge undercounts it.
    assert_true(@dbhost.dispatch_is_native(pending))
    @dbhost.stop_strategy_dispatch(host)
  }
}
