///|
fn retained_attempt_wire_limits() -> @execution.RowWireLimits {
  {
    max_bytes: 100,
    max_nodes: 20,
    max_depth: 4,
    max_columns: 2,
    max_order_work: 100,
  }
}

///|
fn receive_retained_attempt(
  attempt : @duckdb_compute.DuckDBComputeAttempt,
  available : Ref[Bool],
) -> @execution.RetainedOutputHandle[String] {
  @duckdb_compute.begin_duckdb_compute_stream_result(
    attempt,
    [("id", @duckdb.Float64)],
    retained_attempt_wire_limits(),
    64,
    1,
  ).unwrap()
  @duckdb_compute.receive_duckdb_compute_stream_chunk(attempt, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  assert_eq(
    @duckdb_compute.drain_duckdb_compute_stream_row(attempt).unwrap(),
    Some("[{\"id\":3}"),
  ) catch {
    _ => abort("canonical batch")
  }
  let (receipt, tail) = @duckdb_compute.finish_duckdb_compute_stream_result(
    attempt,
  ).unwrap()
  assert_eq(tail, "]") catch {
    _ => abort("canonical tail")
  }
  // Trusted test Store fixture only: the standard Host must supply real storage.
  @execution.retain_admitted_output_stream(receipt, "exact fixture holding", fn() {
    available.val
  })
}

///|
test "retained Compute fixes frame capacity before streaming and rejects full row fallback" {
  let transport : FixedComputeTestTransport = { settled: None, }
  let (attempt, _) = fixed_compute_attempt_fixture(
    transport,
    fixed_compute_attempt_limits(),
    stream_transport={
      max_bytes: 64,
      max_nodes: 20,
      max_rows: 1,
      max_columns: 1,
      max_text_bytes: 64,
    },
  )
  let plan = @duckdb_compute.duckdb_compute_attempt_plan(attempt)
  assert_false(@duckdb.fixed_compute_retains_join_keys(plan))
  let frame : @duckdb.TransportColumnLimits = {
    max_bytes: 64,
    max_nodes: 20,
    max_rows: 1,
    max_columns: 1,
    max_text_bytes: 64,
  }
  let limits = fixed_compute_attempt_limits()
  let large = { ..limits, values: { ..limits.values, max_nodes: 1000000, }, }
  assert_true(
    @duckdb_compute.duckdb_stream_scratch_capacity(large, frame, compute=plan).unwrap() <
    @duckdb_compute.duckdb_stream_scratch_capacity(large, frame).unwrap(),
  )
  assert_eq(
    @duckdb_compute.duckdb_stream_scratch_capacity(
      large,
      { ..frame, max_rows: 0, },
      compute=plan,
    ),
    None,
  )
  assert_true(
    @duckdb_compute.begin_duckdb_compute_result(attempt, [
      ("id", @duckdb.Float64),
    ])
    is Err(InvalidState),
  )
  for (bytes, rows) in [(65, 1), (64, 2), (0, 1)] {
    assert_true(
      @duckdb_compute.begin_duckdb_compute_stream_result(
        attempt,
        [("id", @duckdb.Float64)],
        retained_attempt_wire_limits(),
        bytes,
        rows,
      )
      is Err(InvalidState),
    )
  }
  let handle = receive_retained_attempt(attempt, Ref(true))
  transport.settled = Some(attempt)
  @duckdb_compute.stage_retained_duckdb_compute_material(
    attempt,
    @execution.retained_output_material(handle),
  ).unwrap()
  let output = @duckdb_compute.complete_duckdb_compute_attempt(attempt).unwrap()
  assert_true(@execution.completed_output_available(output))
  @duckdb_compute.close_duckdb_compute_attempt(attempt)
}

///|
test "retained Compute inputs must finish exact import before result receiving" {
  for mode in 0..<3 {
    let producer_transport : FixedComputeTestTransport = { settled: None, }
    let (producer, producer_input) = fixed_compute_attempt_fixture(
      producer_transport,
      fixed_compute_attempt_limits(),
    )
    let held = receive_retained_attempt(producer, Ref(true))
    producer_transport.settled = Some(producer)
    @duckdb_compute.stage_retained_duckdb_compute_material(
      producer,
      @execution.retained_output_material(held),
    ).unwrap()
    let output = @duckdb_compute.complete_duckdb_compute_attempt(producer).unwrap()
    let owner = @execution.producer_read_receiver(producer_input)
    let receiver = typed_receiver(
      owner, "[{\"filter\":\"id > 2\"},{\"select\":[\"id\"]}]",
    )
    let read = @execution.prepare_producer_read(
      receiver,
      @execution.bind_completed_input(receiver, 0, owner, output).unwrap(),
      100,
      1000,
    ).unwrap()
    let transport : FixedComputeTestTransport = { settled: None, }
    let (attempt, _) = fixed_compute_attempt_fixture(
      transport,
      fixed_compute_attempt_limits(),
      supplied_input=Some(read),
      stream_transport={
        max_bytes: 64,
        max_nodes: 20,
        max_rows: 1,
        max_columns: 1,
        max_text_bytes: 64,
      },
    )
    assert_false(@duckdb_compute.duckdb_compute_inputs_ready(attempt))
    assert_true(
      @duckdb_compute.begin_duckdb_compute_result(attempt, [
        ("id", @duckdb.Float64),
      ])
      is Err(InvalidState),
    )
    assert_true(
      @duckdb_compute.begin_duckdb_compute_input_stream(
        attempt,
        0,
        retained_attempt_wire_limits(),
        65,
      )
      is Err(InvalidState),
    )
    @duckdb_compute.begin_duckdb_compute_input_stream(
      attempt,
      0,
      retained_attempt_wire_limits(),
      64,
    ).unwrap()
    @duckdb_compute.append_duckdb_compute_input_stream(
      attempt,
      0,
      if mode == 1 {
        "{\"id\":9}"
      } else {
        "{\"id\":3}"
      },
      { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
    ).unwrap()
    |> ignore
    if mode == 2 {
      @duckdb_compute.close_duckdb_compute_attempt(producer)
    }
    let finished = @duckdb_compute.finish_duckdb_compute_input_stream(
      attempt, 0,
    )
    if mode == 0 {
      finished.unwrap()
      assert_true(@duckdb_compute.duckdb_compute_inputs_ready(attempt))
      let result_handle = receive_retained_attempt(attempt, Ref(true))
      transport.settled = Some(attempt)
      @duckdb_compute.stage_retained_duckdb_compute_material(
        attempt,
        @execution.retained_output_material(result_handle),
      ).unwrap()
      let result = @duckdb_compute.complete_duckdb_compute_attempt(attempt).unwrap()
      @duckdb_compute.close_duckdb_compute_attempt(producer)
      assert_true(@execution.completed_output_available(result))
      @duckdb_compute.close_duckdb_compute_attempt(attempt)
    } else {
      assert_true(finished is Err(_))
      assert_false(@duckdb_compute.duckdb_compute_inputs_ready(attempt))
      assert_true(
        @duckdb_compute.begin_duckdb_compute_result(attempt, [
          ("id", @duckdb.Float64),
        ])
        is Err(InvalidState),
      )
    }
    @duckdb_compute.close_duckdb_compute_attempt(producer)
  }
}

///|
test "retained DuckDB Compute seals independent completion and converts explicitly for Local" {
  let (input, close_upstream) = duckdb_captured_input_lifetime(filter="id > 2")
  let transport : FixedComputeTestTransport = { settled: None, }
  let (attempt, _) = fixed_compute_attempt_fixture(
    transport,
    fixed_compute_attempt_limits(),
    supplied_input=Some(input),
  )
  let available = Ref(true)
  let held = receive_retained_attempt(attempt, available)
  transport.settled = Some(attempt)
  @duckdb_compute.stage_retained_duckdb_compute_material(
    attempt,
    @execution.retained_output_material(held),
  ).unwrap()
  let output = @duckdb_compute.complete_duckdb_compute_attempt(attempt).unwrap()
  assert_false(@execution.completed_has_cell_access(output))
  assert_true(@execution.completed_output_matches_inputs(output, [input]))
  close_upstream()
  assert_false(@execution.producer_read_available(input))
  assert_true(@execution.completed_output_available(output))
  let owner = @execution.producer_read_receiver(input)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let bound = @execution.bind_completed_input(receiver, 0, owner, output).unwrap()
  let read = @execution.prepare_producer_read(receiver, bound, 100, 1000).unwrap()
  assert_eq(
    @execution.retained_producer_payload(held, read),
    Some("exact fixture holding"),
  )
  let conversion = @execution.prepare_completed_output_import(
    output,
    2,
    fixed_compute_attempt_limits().retention,
    retained_attempt_wire_limits(),
    64,
  ).unwrap()
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(owner),
    Step(1),
  ).unwrap()
  let cell = @admitted.admit(
    @schema.field_at(schema, 0).unwrap().contract,
    input_cursor("3"),
    { max_nodes: 10, max_text_bytes: 10, max_depth: 4, },
  ).unwrap()
  @execution.append_completed_output_import(conversion, [cell]).unwrap()
  let local_copy = @execution.finish_completed_output_import(conversion).unwrap()
  let local_input = @execution.bind_completed_input(
    receiver, 0, owner, local_copy,
  ).unwrap()
  let downstream = @execution.execute_generated_sequence(
    compute_test_sequence(receiver),
    [],
    compute_test_limits(),
    produced=[local_input],
  ).unwrap()
  available.val = false
  assert_false(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(local_copy))
  @duckdb_compute.close_duckdb_compute_attempt(attempt)
  assert_false(@execution.completed_output_available(local_copy))
  assert_true(@execution.completed_output(downstream, Step(0)) is Some(_))
}

///|
test "retained DuckDB completion rejects unverified unavailable foreign and expired material" {
  for mode in 0..<4 {
    let (input, close_upstream) = duckdb_captured_input_lifetime(
      filter="id > 2",
    )
    let transport : FixedComputeTestTransport = { settled: None, }
    let (attempt, _) = fixed_compute_attempt_fixture(
      transport,
      fixed_compute_attempt_limits(),
      supplied_input=Some(input),
    )
    let available = Ref(true)
    let held = receive_retained_attempt(attempt, available)
    if mode != 0 {
      transport.settled = Some(attempt)
    }
    if mode == 1 {
      available.val = false
    }
    if mode == 2 {
      close_upstream()
    }
    let material = if mode == 3 {
      let other_transport : FixedComputeTestTransport = { settled: None, }
      let (other, _) = fixed_compute_attempt_fixture(
        other_transport,
        fixed_compute_attempt_limits(),
      )
      @execution.retained_output_material(
        receive_retained_attempt(other, Ref(true)),
      )
    } else {
      @execution.retained_output_material(held)
    }
    match
      @duckdb_compute.stage_retained_duckdb_compute_material(attempt, material) {
      Ok(_) =>
        assert_true(
          @duckdb_compute.complete_duckdb_compute_attempt(attempt) is Err(_),
        )
      Err(_) => ()
    }
    assert_true(
      @duckdb_compute.complete_duckdb_compute_attempt(attempt)
      is Err(InvalidState),
    )
  }
}

///|
test "retained completion preserves demand failure and does not expose a row-backed fallback" {
  let transport : FixedComputeTestTransport = { settled: None, }
  let limits = fixed_compute_attempt_limits()
  let (attempt, _) = fixed_compute_attempt_fixture(transport, {
    ..limits,
    demand: { ..limits.demand, max_work: 0, },
  })
  let held = receive_retained_attempt(attempt, Ref(true))
  transport.settled = Some(attempt)
  @duckdb_compute.stage_retained_duckdb_compute_material(
    attempt,
    @execution.retained_output_material(held),
  ).unwrap()
  assert_true(
    @duckdb_compute.complete_duckdb_compute_attempt(attempt) is Err(Demand(_)),
  )
  assert_true(
    @duckdb_compute.complete_duckdb_compute_attempt(attempt)
    is Err(InvalidState),
  )
}
