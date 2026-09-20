///|
test "Local materializing execution uses the common reservation and exact retained producer" {
  for mode in 0..<7 {
    let (run, _) = captured_graph_fixture()
    let ledger = @strategy.captured_dag_ledger(run)
    let transport : FixedComputeTestTransport = { settled: None, }
    let producer = captured_graph_duckdb_start(run, 1, transport)
    let attempt = @duckdb_driver.captured_duckdb_attempt(producer)
    let live = Ref(true)
    let material = receive_retained_attempt(attempt, live)
    transport.settled = Some(attempt)
    @duckdb_compute.stage_retained_duckdb_compute_material(
      attempt,
      @execution.retained_output_material(material),
    ).unwrap()
    let producer_execution = @duckdb_driver.captured_duckdb_execution(producer)
    @strategy.settle_task_execution(run, producer_execution, true).unwrap()
    @duckdb_driver.complete_captured_duckdb_task(run, producer).unwrap()
    captured_graph_local(run, 2).unwrap()
    let input = @strategy.captured_task_input(run, 3, 100, 10000).unwrap()
    assert_false(@execution.producer_read_has_cell_access(input))
    let registry = @connector.prepare_capability_registry(
      [{ name: "local", acquisition: false, fixed_compute: true, }],
      1,
      100,
    ).unwrap()
    let owner = @execution.producer_read_receiver(input)
    let request = @connector.prepare_fixed_compute_request([input], {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    }).unwrap()
    let prepared = @local_connector.local_fixed_compute_candidate(
      @connector.capability_registration_at(registry, 0).unwrap(),
      request,
      task_test_generated(owner),
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ).unwrap()
    guard @connector.choose_fixed_compute_candidate(
        registry,
        request,
        [@connector.prepared_compute_candidate(prepared)],
        Some([0]),
        100,
      ).unwrap()
      is Proposed(choice) else {
      abort("Local selection")
    }
    let limits : @local_connector.LocalImportLimits = {
      max_rows: 2,
      values: {
        ..fixed_compute_attempt_limits().retention,
        max_nodes: if mode == 4 {
          2000000
        } else {
          1000
        },
      },
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    }
    let implementation = @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      [task_test_generated(owner)],
      compute_test_limits(),
      { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
      100,
      1,
    ).unwrap()
    let before_prepare = @resources.ledger_usage(ledger)
    let invalid : Result[
      @connector.PreparedExecution[
        @local_connector.LocalMaterializingAttempt,
        @strategy.RunIssue,
      ],
      @local_connector.LocalModuleIssue,
    ] = @local_connector.prepare_local_module_materializing_compute(
      implementation,
      1,
      request,
      limits,
      _ => @strategy.RunIssue::Compute(InvalidLimits),
      None,
    )
    assert_true(invalid is Err(Candidate(ForeignPreparation)))
    let execution = if mode == 0 {
      @local_connector.prepare_local_module_materializing_compute(
        implementation,
        0,
        request,
        limits,
        _ => @strategy.RunIssue::Compute(InvalidLimits),
        None,
      ).unwrap()
    } else {
      @local_connector.prepare_local_materializing_execution(
        choice,
        prepared,
        compute_test_limits(),
        { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
        limits,
        _ => @strategy.RunIssue::Compute(InvalidLimits),
        output_limits=if mode >= 5 {
          Some({
            max_rows: 2,
            values: limits.values,
            wire: limits.wire,
            max_batch_bytes: 64,
          })
        } else {
          None
        },
      ).unwrap()
    }
    assert_eq(@resources.ledger_usage(ledger), before_prepare)
    let capacity = @connector.prepared_execution_capacity(execution)
    assert_eq(capacity.transfer_bytes, 100L)
    assert_true(
      @local_connector.local_import_retention_capacity({
        ..limits,
        max_batch_bytes: 0,
      })
      is None,
    )
    let before = @resources.ledger_usage(ledger)
    let started = @strategy.start_captured_materializing_execution(
      run, 3, execution,
    )
    if mode == 4 {
      assert_true(started is Err(Physical(RetentionLimit)))
      assert_eq(@resources.ledger_usage(ledger), before)
      assert_true(@connector.prepared_execution_available(execution))
      continue
    }
    let (consumer, ticket) = started.unwrap()
    let released = Ref(false)
    if mode >= 5 {
      @local_connector.install_local_export_retention(consumer, fn() {
        released.val
      }).unwrap()
      assert_true(
        @local_connector.install_local_export_retention(consumer, fn() { true })
        is Err(State),
      )
    }
    assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts + 1)
    assert_eq(@resources.ledger_usage(ledger).reserved_transfer_bytes, 100L)
    assert_true(
      @local_connector.execute_local_materializing_attempt(consumer)
      is Err(State),
    )
    @local_connector.begin_local_materializing_input(consumer, 0).unwrap()
    @strategy.charge_task_execution_transfer(run, ticket, 10L).unwrap()
    @local_connector.append_local_materializing_input(
      consumer,
      0,
      if mode == 1 {
        "{\"id\":9}"
      } else {
        "{\"id\":3}"
      },
    ).unwrap()
    if mode == 2 {
      @strategy.close_task_execution(run, ticket)
      assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
    }
    if mode == 3 {
      live.val = false
    }
    let imported = @local_connector.finish_local_materializing_input(
      consumer, 0,
    )
    if mode == 0 || mode >= 5 {
      imported.unwrap()
      @local_connector.execute_local_materializing_attempt(consumer).unwrap()
      @strategy.settle_task_execution(run, ticket, true).unwrap()
      if mode >= 5 {
        assert_true(
          @local_connector.local_materializing_completed_output(consumer)
          is None,
        )
        assert_false(@strategy.captured_task_completed(run, 3))
        @local_connector.begin_local_output_export(consumer).unwrap()
        assert_eq(
          @local_connector.next_local_output_export(consumer).unwrap(),
          Some("[{\"id\":3}"),
        )
        assert_true(
          @local_connector.next_local_output_export(consumer).unwrap() is None,
        )
        let (content, tail) = @local_connector.finish_local_output_export(
          consumer,
        ).unwrap()
        assert_eq(tail, "]")
        if mode == 5 {
          let material = @execution.retain_admitted_output_stream(content, (), fn() {
            true
          })
          @local_connector.bind_local_output_export(
            consumer,
            @execution.retained_output_material(material),
          ).unwrap()
        }
      }
      if mode != 6 {
        let output = @local_connector.local_materializing_completed_output(
          consumer,
        ).unwrap()
        @strategy.complete_materializing_task_execution(run, ticket, output).unwrap()
        let result = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
        assert_true(@execution.completed_output_matches_inputs(result, [input]))
        if mode == 0 {
          assert_true(
            @execution.completed_cell(result, 0, 0) is Some(Number(3)),
          )
        } else {
          assert_false(@execution.completed_has_cell_access(result))
        }
        @strategy.close_task_execution(run, producer_execution)
        assert_true(@execution.completed_output_available(result))
      } else {
        assert_true(
          @local_connector.local_materializing_completed_output(consumer)
          is None,
        )
        assert_false(@strategy.captured_task_completed(run, 3))
      }
    } else {
      assert_true(imported is Err(_))
      assert_true(
        @local_connector.execute_local_materializing_attempt(consumer)
        is Err(State),
      )
      assert_false(@strategy.captured_task_completed(run, 3))
    }
    @strategy.close_task_execution(run, ticket)
    if mode != 0 && mode < 5 {
      @strategy.settle_task_execution(run, ticket, true).unwrap()
    }
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    if mode >= 5 {
      assert_true(
        @resources.ledger_usage(ledger).held_bytes > 0L ||
        @resources.ledger_usage(ledger).reserved_retention_bytes > 0L,
      )
      assert_false(
        @strategy.refresh_task_execution_cleanup(run, ticket).unwrap(),
      )
      released.val = true
      assert_true(
        @strategy.refresh_task_execution_cleanup(run, ticket).unwrap(),
      )
    }
    assert_eq(@resources.ledger_usage(ledger).reserved_transfer_bytes, 0L)
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      before.transferred_bytes + 10L,
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_true(@strategy.captured_task_output(run, 2, Step(1)) is Some(_))
  }
}
