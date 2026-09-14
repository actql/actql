///|
fn captured_graph_duckdb_start(
  run : @strategy.CapturedDAG,
  task : Int,
  transport : FixedComputeTestTransport,
) -> @planning.DuckDBComputeAttempt raise {
  captured_graph_duckdb_try_start(run, task, transport).unwrap()
}

///|
fn captured_graph_duckdb_try_start(
  run : @strategy.CapturedDAG,
  task : Int,
  transport : FixedComputeTestTransport,
  transfer_bytes? : Int64 = 100000L,
  execution_bytes? : Int64 = 1000000L,
) -> Result[@planning.DuckDBComputeAttempt, @strategy.RunIssue] raise {
  let input = @strategy.captured_task_input(run, task, 100, 10000).unwrap()
  let request = @planning.prepare_fixed_compute_request(input, {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 10,
    max_value_bytes: 100,
    common_fragment: None,
  }).unwrap()
  let registry = @planning.prepare_capability_registry(
    [{ name: "duckdb", acquisition: false, fixed_compute: true, }],
    1,
    100,
  ).unwrap()
  let prepared = @planning.duckdb_fixed_compute_candidate(
    @planning.capability_registration_at(registry, 0).unwrap(),
    request,
    "fixed",
    native_compile_limits(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_fixed_compute_candidate(
      registry,
      request,
      [@planning.prepared_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("duckdb choice")
  }
  @strategy.start_captured_duckdb_task(
    run,
    task,
    choice,
    prepared,
    query_generated(@execution.producer_read_receiver(input)),
    fixed_compute_attempt_limits(),
    dispatch_test_limits().transport,
    transfer_bytes,
    execution_bytes,
    current => {
      transport.settled is Some(expected) && physical_equal(current, expected)
    },
  )
}

///|
fn captured_graph_duckdb_receive(
  attempt : @planning.DuckDBComputeAttempt,
  task : Int,
) -> Unit {
  @planning.begin_duckdb_compute_result(attempt, [("id", @duckdb.Float64)]).unwrap()
  @planning.receive_duckdb_compute_chunk(attempt, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  if task == 2 {
    @planning.receive_duckdb_compute_chunk(attempt, 1, [
      input_cursor("[\"4000000000000000\"]"),
    ]).unwrap()
  }
  @planning.finish_duckdb_compute_result(attempt).unwrap()
}

///|
test "checked capture DAG supports every Local DuckDB assignment with independent completions" {
  for a in [false, true] {
    for b in [false, true] {
      for c in [false, true] {
        let (run, issuer) = captured_graph_fixture()
        let attempts : Array[@planning.DuckDBComputeAttempt] = []
        for (task, native) in [(1, a), (2, b), (3, c)] {
          if task == 3 {
            @planning.close_mock_query_issuer(issuer)
          }
          if native {
            let transport : FixedComputeTestTransport = { settled: None, }
            let attempt = captured_graph_duckdb_start(run, task, transport)
            assert_true(@strategy.next_captured_task(run) is None)
            assert_true(
              @strategy.captured_task_output(run, task, Step(1)) is None,
            )
            captured_graph_duckdb_receive(attempt, task)
            transport.settled = Some(attempt)
            @strategy.settle_captured_duckdb_native(run, attempt, true).unwrap()
            @strategy.complete_captured_duckdb_task(run, attempt).unwrap()
            assert_true(
              @strategy.complete_captured_duckdb_task(run, attempt)
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
          @planning.close_duckdb_compute_attempt(attempt)
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
    let (other, _) = fixed_compute_attempt_fixture(
      { settled: None, },
      fixed_compute_attempt_limits(),
    )
    assert_true(
      @strategy.complete_captured_duckdb_task(run, other)
      is Err(ForeignCandidate),
    )
    assert_true(
      @strategy.captured_task_input(run, 2, 100, 10000) is Err(NotReady),
    )
    if mode != 0 {
      captured_graph_duckdb_receive(attempt, 1)
    }
    transport.settled = Some(attempt)
    if mode == 2 {
      @planning.close_mock_query_issuer(issuer)
    }
    if mode == 3 {
      @strategy.stop_captured_dag(run)
    }
    if mode == 1 {
      transport.settled = None
    }
    @strategy.settle_captured_duckdb_native(run, attempt, true).unwrap()
    assert_true(@strategy.complete_captured_duckdb_task(run, attempt) is Err(_))
    assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
    assert_true(@strategy.next_captured_task(run) is None)
  }
}
