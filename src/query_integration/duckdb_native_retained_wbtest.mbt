///|
fn native_retained_values() -> @execution.ValueLimits {
  { max_nodes: 1000, max_text_bytes: 10000, max_depth: 10, max_work: 10000, }
}

///|
fn native_retained_receive(
  attempt : @duckdb_query.DuckDBNativeAttempt,
) -> @execution.AdmittedOutputStreamReceipt raise {
  let limits = native_completion_limits()
  @duckdb_query.stream_duckdb_native_validation(
    attempt,
    limits.receipts,
    limits.demand,
    3,
  ).unwrap()
  @duckdb_query.stream_duckdb_native_output(
    attempt,
    100,
    native_retained_values(),
    limits.receipts,
    1000,
    2,
  ).unwrap()
  @duckdb_query.admit_duckdb_native_metadata(
    attempt,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
  let text = StringBuilder()
  for
    (role, rows, cells) in [
      (
        @duckdb.ValidationScan,
        3,
        "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
      ),
      (@duckdb.NativeResult, 2, "[\"4008000000000000\",\"4000000000000000\"]"),
    ] {
    let port = @duckdb_query.begin_duckdb_native_receipt(attempt, role, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    @duckdb_query.accept_duckdb_native_chunk(attempt, port, rows, [
      input_cursor(cells),
    ]).unwrap()
    if role == @duckdb.NativeResult {
      while @duckdb_query.drain_duckdb_native_output(attempt).unwrap()
            is Some(row) {
        text.write_string(row)
      }
    }
    @duckdb_query.finish_duckdb_native_receipt(attempt, port).unwrap()
  }
  let (receipt, tail) = @duckdb_query.finish_duckdb_native_output_stream(
      attempt,
    )
    .unwrap()
    .unwrap()
  text.write_string(tail)
  assert_eq(text.to_string(), "[{\"id\":3},{\"id\":2}]")
  assert_eq(
    @execution.output_stream_identity(receipt),
    (
      "sha256:b578d4eb7cd3e1c8e66fd5758a9c5a98dc05739e4c6fa282fc372aec70930e18",
      19, 5, 2,
    ),
  )
  receipt
}

///|
test "retained fixed import demand uses exact decoded input and single receiving receipt" {
  let f = native_issuer_fixture()
  let attempt = native_issued_attempt(f)
  let receipt = native_retained_receive(attempt)
  let handle = @execution.retain_admitted_output_stream(receipt, (), fn() {
    true
  })
  @duckdb_query.stage_duckdb_native_output_material(
    attempt,
    @execution.retained_output_material(handle),
  ).unwrap()
  f.transport.push(attempt)
  let observation = @duckdb_query.complete_duckdb_native_capture(
    f.issuer,
    attempt,
    native_completion_limits(),
  ).unwrap()
  let output = @duckdb_query.complete_duckdb_native_retained_output(
    f.issuer,
    attempt,
    observation,
    100,
    10000,
  ).unwrap()
  let owner = @duckdb.native_query_owner(
    @duckdb.native_scan_query(
      @duckdb_query.duckdb_native_preparation_scan(
        @duckdb_query.duckdb_native_attempt_preparation(attempt),
      ),
    ),
  )
  let receiver = typed_receiver(
    owner, "[{\"filter\":\"id > 2\"},{\"select\":[\"id\"]}]",
  )
  let input = @execution.prepare_producer_read(
    receiver,
    @execution.bind_completed_input(receiver, 0, owner, output).unwrap(),
    100,
    10000,
  ).unwrap()
  for case_index in 0..<9 {
    let mode = case_index / 3
    let materialize_parameters = case_index % 3 == 0
    let ceiling = if mode == 1 { 4 } else { 5 }
    let physical : @execution.FixedInputGuardMeasureLimits = {
      max_work: 7,
      max_bytes: if mode == 2 {
        2
      } else {
        3
      },
      max_nodes: 3,
      max_depth: 10,
    }
    let compute = @duckdb.prepare_fixed_compute(
      input,
      "streamed",
      native_compile_limits(),
    ).unwrap()
    let stream = @duckdb.prepare_fixed_import_stream(
      @duckdb.fixed_compute_import(compute, 0).unwrap(),
      100,
      native_retained_values(),
      native_completion_limits().receipts,
      1000,
    ).unwrap()
    @duckdb.attach_fixed_import_demand(stream, compute, ceiling, physical).unwrap()
    assert_true(@duckdb.fixed_import_verified_demand(stream) is None)
    for index, row in ["{\"id\":3}", "{\"id\":2}"] {
      if case_index % 3 == 2 {
        let field = @schema.field_at(
          @execution.output_stream_schema(receipt),
          0,
        ).unwrap()
        let value = @admitted.admit(
          field.contract,
          input_cursor((3 - index).to_string()),
          { max_nodes: 10, max_text_bytes: 100, max_depth: 2, },
        ).unwrap()
        @duckdb.verify_fixed_import_values(stream, [value]).unwrap()
        continue
      }
      let parameters = @duckdb.append_fixed_import_stream(
        stream,
        row,
        {
          max_bytes: 1000,
          max_nodes: 100,
          max_depth: 10,
          max_text_bytes: 1000,
        },
        materialize_parameters~,
      ).unwrap()
      assert_eq(parameters.length(), if materialize_parameters { 1 } else { 0 })
    }
    @duckdb.finish_fixed_import_stream(stream).unwrap() |> ignore
    let demand = @duckdb.fixed_import_verified_demand(stream).unwrap()
    let receiving = @duckdb.prepare_fixed_compute_receiving(
      compute,
      [("id", @duckdb.Float64)],
      { max_rows: 2, max_cells: 2, max_nodes: 2, max_text_bytes: 0, },
      { max_nodes: 4, max_text_bytes: 4, max_depth: 2, max_work: 8, },
      100,
    ).unwrap()
    @duckdb.receive_fixed_compute_chunk(receiving, 1, [
      input_cursor("[\"4008000000000000\"]"),
    ]).unwrap()
    let received = @duckdb.finish_fixed_compute_receiving(receiving).unwrap()
    let measured = @duckdb.measure_fixed_compute_demand(
      compute,
      received,
      ceiling,
      physical,
      input_demand=demand,
    )
    if mode == 0 {
      guard @duckdb.fixed_compute_demand_usage(measured.unwrap())
        is Comparison(usage) else {
        fail("comparison expected")
      }
      assert_eq(
        (usage.rows, usage.true_rows, usage.false_rows, usage.null_rows),
        (2, 1, 1, 0),
      )
      assert_eq(
        (usage.field_bytes, usage.rhs_bytes, usage.predicate_bytes),
        (2L, Some(1), 9L),
      )
      assert_eq(
        (usage.physical_work, usage.physical_bytes, usage.physical_nodes),
        (7, 3, 3),
      )
      assert_true(
        @duckdb.measure_fixed_compute_demand(
          compute,
          received,
          ceiling,
          physical,
          input_demand=demand,
        )
        is Err(InvalidState),
      )
    } else if mode == 1 {
      assert_true(measured is Err(Predicate(ValueBytes)))
    } else {
      assert_true(measured is Err(Operand(_, _, _)))
    }
    assert_false(@execution.producer_read_has_cell_access(input))
  }
  @duckdb_query.close_duckdb_native_issuer(f.issuer)
}

///|
test "native retained capture completes without row storage and converts explicitly for Local" {
  let f = native_issuer_fixture()
  let attempt = native_issued_attempt(f)
  let receipt = native_retained_receive(attempt)
  let live = Ref(true)
  let handle = @execution.retain_admitted_output_stream(receipt, (), fn() {
    live.val
  })
  @duckdb_query.stage_duckdb_native_output_material(
    attempt,
    @execution.retained_output_material(handle),
  ).unwrap()
  f.transport.push(attempt)
  let observation = @duckdb_query.complete_duckdb_native_capture(
    f.issuer,
    attempt,
    native_completion_limits(),
  ).unwrap()
  let output = @duckdb_query.complete_duckdb_native_retained_output(
    f.issuer,
    attempt,
    observation,
    100,
    10000,
  ).unwrap()
  assert_false(@execution.completed_has_cell_access(output))
  assert_eq(@execution.completed_row_count(output), 2)
  let retained_owner = @duckdb.native_query_owner(
    @duckdb.native_scan_query(
      @duckdb_query.duckdb_native_preparation_scan(
        @duckdb_query.duckdb_native_attempt_preparation(attempt),
      ),
    ),
  )
  let retained_receiver = typed_receiver(
    retained_owner, "[{\"select\":[\"id\"]}]",
  )
  let retained_read = @execution.prepare_producer_read(
    retained_receiver,
    @execution.bind_completed_input(
      retained_receiver, 0, retained_owner, output,
    ).unwrap(),
    100,
    10000,
  ).unwrap()
  let import_ = @duckdb.prepare_fixed_import(
    retained_read, "retained_input", 10, 1000,
  ).unwrap()
  let import_stream = @duckdb.prepare_fixed_import_stream(
    import_,
    100,
    native_retained_values(),
    native_completion_limits().receipts,
    1000,
  ).unwrap()
  let input_measurement = @execution.prepare_streamed_fixed_producer_measurement(
    [retained_read],
    Step(0),
    max_rows=100,
    max_value_bytes=1000,
    { max_work: 1000, max_bytes: 10000, max_nodes: 1000, max_depth: 10, },
  ).unwrap()
  @duckdb.attach_fixed_import_measurement(import_stream, input_measurement).unwrap()
  for
    (row, bits) in [
      ("{\"id\":3}", "4008000000000000"),
      ("{\"id\":2}", "4000000000000000"),
    ] {
    let parameters = @duckdb.append_fixed_import_stream(import_stream, row, {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    assert_eq(parameters.length(), 1)
    let writer = @encode.writer(1000, 100, 10)
    @duckdb.emit_physical_parameter(parameters[0], writer)
    assert_eq(
      @encode.finish(writer),
      "{\"type\":{\"id\":\"DOUBLE\"},\"value\":\"" + bits + "\"}",
    )
  }
  let verified_import = @duckdb.finish_fixed_import_stream(import_stream).unwrap()
  assert_true(
    @execution.verified_producer_scan_matches(verified_import, retained_read),
  )
  assert_false(@execution.producer_read_has_cell_access(retained_read))
  assert_true(
    @duckdb_query.materialize_duckdb_native_output(
      f.issuer,
      attempt,
      observation,
      100,
      native_retained_values(),
    )
    is Err(_),
  )
  let conversion = @execution.prepare_completed_output_import(
    output,
    100,
    native_retained_values(),
    native_completion_limits().receipts,
    1000,
  ).unwrap()
  for row in ["{\"id\":3}", "{\"id\":2}"] {
    @execution.append_completed_output_import_wire(conversion, row, {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
  }
  let memory = @execution.finish_completed_output_import(conversion).unwrap()
  live.val = false
  assert_false(@execution.completed_output_available(output))
  assert_true(@execution.completed_output_available(memory))
  let owner = @duckdb.native_query_owner(
    @duckdb.native_scan_query(
      @duckdb_query.duckdb_native_preparation_scan(
        @duckdb_query.duckdb_native_attempt_preparation(attempt),
      ),
    ),
  )
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let bound = @execution.bind_completed_input(receiver, 0, owner, memory).unwrap()
  let read = @execution.prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let result = @execution.execute_generated_sequence(
    compute_test_sequence(receiver),
    [],
    compute_test_limits(),
    produced=[bound],
  ).unwrap()
  let downstream = @execution.completed_output(result, @pipeline.Step(0)).unwrap()
  @duckdb_query.close_duckdb_native_issuer(f.issuer)
  assert_false(@execution.producer_read_available(read))
  assert_false(@execution.completed_output_available(memory))
  assert_true(@execution.completed_output_available(downstream))
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(3)))
  assert_true(@execution.completed_cell(downstream, 1, 0) is Some(Number(2)))
}

///|
test "native streamed capture requires exact live held material and verified transport" {
  for mode in [0, 1, 2, 3] {
    let f = native_issuer_fixture()
    let attempt = native_issued_attempt(f)
    let receipt = native_retained_receive(attempt)
    let live = Ref(true)
    let actual = if mode == 1 {
      native_retained_receive(native_issued_attempt(f))
    } else {
      receipt
    }
    let handle = @execution.retain_admitted_output_stream(actual, (), fn() {
      live.val
    })
    if mode != 0 {
      let staged = @duckdb_query.stage_duckdb_native_output_material(
        attempt,
        @execution.retained_output_material(handle),
      )
      if mode == 1 {
        assert_true(staged is Err(InvalidRetainedLayout))
      } else {
        staged.unwrap()
      }
    }
    if mode == 2 {
      live.val = false
    }
    if mode != 3 {
      f.transport.push(attempt)
    }
    assert_true(
      @duckdb_query.complete_duckdb_native_capture(
        f.issuer,
        attempt,
        native_completion_limits(),
      )
      is Err(_),
    )
  }
}
