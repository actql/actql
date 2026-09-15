///|
struct FixedComputeTestTransport {
  mut settled : @duckdb_compute.DuckDBComputeAttempt?
}

///|
test "DuckDB Compute seals independent output only after live upstream validation" {
  for close_before_completion in [true, false] {
    let (input, close_upstream) = duckdb_captured_input_lifetime(
      filter="id > 2",
    )
    let transport : FixedComputeTestTransport = { settled: None, }
    let (attempt, _) = fixed_compute_attempt_fixture(
      transport,
      fixed_compute_attempt_limits(),
      supplied_input=Some(input),
    )
    fixed_compute_attempt_receive(attempt)
    transport.settled = Some(attempt)
    if close_before_completion {
      close_upstream()
      assert_true(
        @duckdb_compute.complete_duckdb_compute_attempt(attempt) is Err(_),
      )
      assert_true(
        @duckdb_compute.complete_duckdb_compute_attempt(attempt)
        is Err(InvalidState),
      )
      continue
    }
    let output = @duckdb_compute.complete_duckdb_compute_attempt(attempt).unwrap()
    assert_true(@execution.completed_output_matches_inputs(output, [input]))
    let owner = @execution.producer_read_receiver(input)
    let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
    let bound = @execution.bind_completed_input(receiver, 0, owner, output).unwrap()
    close_upstream()
    assert_false(@execution.producer_read_available(input))
    assert_true(@execution.completed_output_matches_inputs(output, [input]))
    assert_true(
      @execution.bind_completed_input(receiver, 0, owner, output) is Ok(_),
    )
    let completed = @execution.execute_generated_sequence(
      compute_test_sequence(receiver),
      [],
      compute_test_limits(),
      produced=[bound],
    ).unwrap()
    let downstream = @execution.completed_output(completed, Step(0)).unwrap()
    // Its own transport revocation remains effective after sealing.
    transport.settled = None
    assert_true(
      @execution.bind_completed_input(receiver, 0, owner, output) is Err(_),
    )
    transport.settled = Some(attempt)
    @duckdb_compute.close_duckdb_compute_attempt(attempt)
    assert_false(@execution.completed_output_matches_inputs(output, [input]))
    assert_true(
      @execution.bind_completed_input(receiver, 0, owner, output) is Err(_),
    )
    let next = typed_receiver(
      receiver,
      "[{\"select\":[\"id\"]}]",
      target=Step(0),
    )
    let retained = @execution.bind_completed_input(
      next, 0, receiver, downstream,
    ).unwrap()
    assert_true(
      @execution.execute_generated_sequence(
        compute_test_sequence(next),
        [],
        compute_test_limits(),
        produced=[retained],
      )
      is Ok(_),
    )
  }
}

///|
fn fixed_compute_attempt_limits() -> @duckdb_compute.DuckDBComputeLimits {
  {
    values: { max_work: 100, max_bytes: 100, max_nodes: 100, max_depth: 10, },
    demand: { max_work: 100, max_bytes: 100, max_nodes: 100, max_depth: 10, },
    physical: {
      max_rows: 10,
      max_cells: 10,
      max_nodes: 10,
      max_text_bytes: 100,
    },
    retention: {
      max_nodes: 100,
      max_text_bytes: 100,
      max_depth: 10,
      max_work: 1000,
    },
    metadata_work: 100,
    completion_entries: 100,
    completion_name_bytes: 1000,
  }
}

///|
fn fixed_compute_attempt_fixture(
  transport : FixedComputeTestTransport,
  limits : @duckdb_compute.DuckDBComputeLimits,
  ceiling? : Int = 5,
  supplied_input? : @execution.ProducerRead? = None,
  generated? : @execution.GeneratedSequence? = None,
) -> (@duckdb_compute.DuckDBComputeAttempt, @execution.ProducerRead) raise {
  let input = match supplied_input {
    Some(input) => input
    None => duckdb_captured_input(filter="id > 2")
  }
  let request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 2,
    max_value_bytes: ceiling,
    common_fragment: None,
  }).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "duckdb", acquisition: false, fixed_compute: true, }],
    1,
    6,
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
    abort("fixed proposal")
  }
  let attempt = @duckdb_compute.start_duckdb_compute_attempt(
    choice,
    prepared,
    match generated {
      Some(generated) => @execution.generated_completion_preparation(generated)
      None =>
        @execution.generated_completion_preparation(
          query_generated(@execution.producer_read_receiver(input)),
        )
    },
    limits,
    current => {
      match transport.settled {
        Some(expected) => physical_equal(current, expected)
        None => false
      }
    },
  ).unwrap()
  (attempt, input)
}

///|
fn fixed_compute_attempt_receive(
  attempt : @duckdb_compute.DuckDBComputeAttempt,
) -> Unit {
  @duckdb_compute.begin_duckdb_compute_result(attempt, [("id", @duckdb.Float64)]).unwrap()
  @duckdb_compute.receive_duckdb_compute_chunk(attempt, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  @duckdb_compute.finish_duckdb_compute_result(attempt).unwrap()
}

///|
test "selected fixed Compute verifies guards and transport before real completion and consumer" {
  let transport : FixedComputeTestTransport = { settled: None, }
  let (attempt, input) = fixed_compute_attempt_fixture(
    transport,
    fixed_compute_attempt_limits(),
  )
  fixed_compute_attempt_receive(attempt)
  transport.settled = Some(attempt)
  let output = @duckdb_compute.complete_duckdb_compute_attempt(attempt).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(
    @duckdb_compute.complete_duckdb_compute_attempt(attempt)
    is Err(InvalidState),
  )
  @duckdb_compute.abort_duckdb_compute_attempt(attempt) // successful result is preserved
  let owner = @execution.producer_read_receiver(input)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let bound = @execution.bind_completed_input(receiver, 0, owner, output).unwrap()
  let generated = compute_test_sequence(receiver)
  let completed = @execution.execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
    produced=[bound],
  ).unwrap()
  let downstream = @execution.completed_output(completed, @pipeline.Step(0)).unwrap()
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(3)))
  @duckdb_compute.close_duckdb_compute_attempt(attempt)
  transport.settled = None
  assert_true(
    @execution.bind_completed_input(receiver, 0, owner, output) is Err(_),
  )
  assert_true(
    @execution.execute_generated_sequence(
      generated,
      [],
      compute_test_limits(),
      produced=[bound],
    )
    is Err(_),
  )
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(3)))
  assert_true(@execution.producer_read_available(input))
}

///|
test "fixed Compute cannot turn incomplete foreign or failed attempts into completion" {
  let transport : FixedComputeTestTransport = { settled: None, }
  let (unfinished, _) = fixed_compute_attempt_fixture(
    transport,
    fixed_compute_attempt_limits(),
  )
  assert_true(
    @duckdb_compute.complete_duckdb_compute_attempt(unfinished)
    is Err(InvalidState),
  )
  assert_true(
    @duckdb_compute.begin_duckdb_compute_result(unfinished, [
      ("id", @duckdb.Float64),
    ])
    is Err(InvalidState),
  )
  let (attempt, input) = fixed_compute_attempt_fixture(
    transport,
    fixed_compute_attempt_limits(),
  )
  fixed_compute_attempt_receive(attempt)
  transport.settled = Some(unfinished)
  assert_true(
    @duckdb_compute.complete_duckdb_compute_attempt(attempt)
    is Err(UnverifiedTransport),
  )
  transport.settled = Some(attempt)
  assert_true(
    @duckdb_compute.complete_duckdb_compute_attempt(attempt)
    is Err(InvalidState),
  )
  assert_true(@execution.producer_read_available(input))
  for ceiling in [4, 5] {
    let limits = fixed_compute_attempt_limits()
    let limits = if ceiling == 5 {
      { ..limits, values: { ..limits.values, max_bytes: 2, }, }
    } else {
      limits
    }
    let (failed, input) = fixed_compute_attempt_fixture(
      transport,
      limits,
      ceiling~,
    )
    fixed_compute_attempt_receive(failed)
    transport.settled = Some(failed)
    let result = @duckdb_compute.complete_duckdb_compute_attempt(failed)
    if ceiling == 4 {
      assert_true(result is Err(Demand(Predicate(ValueBytes))))
    } else {
      assert_true(result is Err(Guard(Measurement(Output, 0, 0, _))))
    }
    assert_true(
      @duckdb_compute.complete_duckdb_compute_attempt(failed)
      is Err(InvalidState),
    )
    assert_true(@execution.producer_read_available(input))
  }
  transport.settled = None
}
