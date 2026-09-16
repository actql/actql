///|
fn captured_graph_duckdb_start(
  run : @strategy.CapturedDAG,
  task : Int,
  transport : FixedComputeTestTransport,
) -> @duckdb_driver.CapturedDuckDBTask raise {
  captured_graph_duckdb_try_start(run, task, transport).unwrap()
}

///|
fn captured_graph_duckdb_try_start(
  run : @strategy.CapturedDAG,
  task : Int,
  transport : FixedComputeTestTransport,
  transfer_bytes? : Int64 = 100000L,
  execution_bytes? : Int64 = 1000000L,
  generated? : @execution.GeneratedSequence,
  retained_storage? : (Int64, () -> Bool),
) -> Result[@duckdb_driver.CapturedDuckDBTask, @strategy.RunIssue] raise {
  let input = @strategy.captured_task_input(run, task, 100, 10000).unwrap()
  let request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 10,
    max_value_bytes: 100,
    common_fragment: None,
  }).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "duckdb", acquisition: false, fixed_compute: true, }],
    1,
    100,
  ).unwrap()
  let prepared = @duckdb_compute.duckdb_fixed_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    "fixed",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("duckdb choice")
  }
  @duckdb_driver.start_captured_duckdb_task(
    run,
    task,
    choice,
    prepared,
    match generated {
      Some(value) => @execution.generated_completion_preparation(value)
      None =>
        @execution.generated_completion_preparation(
          query_generated(@execution.producer_read_receiver(input)),
        )
    },
    fixed_compute_attempt_limits(),
    dispatch_test_limits().transport,
    transfer_bytes,
    execution_bytes,
    current => {
      transport.settled is Some(expected) && physical_equal(current, expected)
    },
    retained_storage?,
  )
}

///|
fn captured_graph_duckdb_receive(
  attempt : @duckdb_driver.CapturedDuckDBTask,
  task : Int,
) -> Unit {
  let attempt = @duckdb_driver.captured_duckdb_attempt(attempt)
  @duckdb_compute.begin_duckdb_compute_result(attempt, [("id", @duckdb.Float64)]).unwrap()
  @duckdb_compute.receive_duckdb_compute_chunk(attempt, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  if task == 2 {
    @duckdb_compute.receive_duckdb_compute_chunk(attempt, 1, [
      input_cursor("[\"4000000000000000\"]"),
    ]).unwrap()
  }
  @duckdb_compute.finish_duckdb_compute_result(attempt).unwrap()
}

///|
test "checked capture DAG supports every Local DuckDB assignment with independent completions" {
  for a in [false, true] {
    for b in [false, true] {
      for c in [false, true] {
        let (run, issuer) = captured_graph_fixture()
        let attempts : Array[@duckdb_driver.CapturedDuckDBTask] = []
        for (task, native) in [(1, a), (2, b), (3, c)] {
          if task == 3 {
            @mock.close_mock_query_issuer(issuer)
          }
          if native {
            let transport : FixedComputeTestTransport = { settled: None, }
            let attempt = captured_graph_duckdb_start(run, task, transport)
            assert_true(@strategy.next_captured_task(run) is None)
            assert_true(
              @strategy.captured_task_output(run, task, Step(1)) is None,
            )
            captured_graph_duckdb_receive(attempt, task)
            transport.settled = Some(
              @duckdb_driver.captured_duckdb_attempt(attempt),
            )
            @strategy.settle_task_execution(
              run,
              @duckdb_driver.captured_duckdb_execution(attempt),
              true,
            ).unwrap()
            @strategy.complete_task_execution(
              run,
              @duckdb_driver.captured_duckdb_execution(attempt),
            ).unwrap()
            assert_true(
              @strategy.complete_task_execution(
                run,
                @duckdb_driver.captured_duckdb_execution(attempt),
              )
              is Err(ForeignCandidate),
            )
            attempts.push(attempt)
          } else {
            captured_graph_local(run, task).unwrap()
          }
        }
        assert_true(@strategy.next_captured_task(run) is None)
        for task in 1..<4 {
          let output = @strategy.captured_task_output(run, task, Step(1)).unwrap()
          assert_eq(
            @execution.completed_row_count(output),
            if task == 2 {
              2
            } else {
              1
            },
          )
          assert_true(
            @execution.completed_cell(output, 0, 0) is Some(Number(3)),
          )
        }
        for attempt in attempts {
          @strategy.close_task_execution(
            run,
            @duckdb_driver.captured_duckdb_execution(attempt),
          )
        }
      }
    }
  }
}

///|
test "DAG rejects foreign incomplete revoked and cancelled DuckDB completions" {
  for mode in 0..<4 {
    let (run, issuer) = captured_graph_fixture()
    let transport : FixedComputeTestTransport = { settled: None, }
    let attempt = captured_graph_duckdb_start(run, 1, transport)
    let (other_run, _) = captured_graph_fixture()
    let other = captured_graph_duckdb_start(other_run, 1, { settled: None, })
    assert_true(
      @strategy.complete_task_execution(
        run,
        @duckdb_driver.captured_duckdb_execution(other),
      )
      is Err(ForeignCandidate),
    )
    assert_true(
      @strategy.captured_task_input(run, 2, 100, 10000) is Err(NotReady),
    )
    if mode != 0 {
      captured_graph_duckdb_receive(attempt, 1)
    }
    transport.settled = Some(@duckdb_driver.captured_duckdb_attempt(attempt))
    if mode == 2 {
      @mock.close_mock_query_issuer(issuer)
    }
    if mode == 3 {
      @strategy.stop_captured_dag(run)
    }
    if mode == 1 {
      transport.settled = None
    }
    @strategy.settle_task_execution(
      run,
      @duckdb_driver.captured_duckdb_execution(attempt),
      true,
    ).unwrap()
    assert_true(
      @strategy.complete_task_execution(
        run,
        @duckdb_driver.captured_duckdb_execution(attempt),
      )
      is Err(_),
    )
    assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
    assert_true(@strategy.next_captured_task(run) is None)
  }
}
