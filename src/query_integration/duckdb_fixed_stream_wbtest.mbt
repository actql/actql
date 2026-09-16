///|
test "streamed Compute measurement retains the input budget and exact receipt identity" {
  let input = duckdb_captured_input()
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let limits : @execution.FixedInputGuardMeasureLimits = {
    max_work: 8,
    max_bytes: 4,
    max_nodes: 4,
    max_depth: 10,
  }
  let measurement = @execution.prepare_fixed_producer_measurement(
    [input],
    @pipeline.Step(1),
    max_rows=2,
    max_value_bytes=1,
    limits,
  ).unwrap()
  let receiving = streamed_fixed_receiver(compute, measurement~)
  for payload in ["[\"4008000000000000\"]", "[\"4000000000000000\"]"] {
    @duckdb.receive_fixed_compute_stream_chunk(receiving, 1, [
      input_cursor(payload),
    ]).unwrap()
    @duckdb.drain_fixed_compute_stream_row(receiving).unwrap() |> ignore
  }
  let (received, _) = @duckdb.finish_fixed_compute_stream_receiving(receiving).unwrap()
  let receipt = @duckdb.fixed_compute_stream_receipt_content(received).unwrap()
  let other = streamed_fixed_receiver(compute)
  let (unmeasured, _) = @duckdb.finish_fixed_compute_stream_receiving(other).unwrap()
  assert_true(
    @execution.finish_fixed_producer_stream_measurement(
      measurement,
      @duckdb.fixed_compute_stream_receipt_content(unmeasured).unwrap(),
    )
    is Err(ForeignInput),
  )
  let measured = @execution.finish_fixed_producer_stream_measurement(
    measurement, receipt,
  ).unwrap()
  assert_eq(
    @execution.fixed_producer_stream_measurement_usage(measured),
    (8, 4, 4),
  )
  assert_true(
    @execution.fixed_producer_stream_measurement_matches(
      measured,
      [input],
      receipt,
      2,
      1,
    ),
  )
  assert_false(
    @execution.fixed_producer_stream_measurement_matches(
      measured,
      [duckdb_captured_input()],
      receipt,
      2,
      1,
    ),
  )
  assert_false(
    @execution.fixed_producer_stream_measurement_matches(
      measured,
      [input],
      receipt,
      2,
      2,
    ),
  )
  assert_true(
    @execution.finish_fixed_producer_stream_measurement(measurement, receipt)
    is Err(ForeignInput),
  )
}

///|
test "streamed output measurement cannot reset budgets at a new chunk" {
  let input = duckdb_captured_input()
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let exact : @execution.FixedInputGuardMeasureLimits = {
    max_work: 8,
    max_bytes: 4,
    max_nodes: 4,
    max_depth: 10,
  }
  for
    physical in [
      { ..exact, max_work: 7, },
      { ..exact, max_bytes: 3, },
      { ..exact, max_nodes: 3, },
    ] {
    let measurement = @execution.prepare_fixed_producer_measurement(
      [input],
      @pipeline.Step(1),
      max_rows=2,
      max_value_bytes=1,
      physical,
    ).unwrap()
    let receiving = streamed_fixed_receiver(compute, measurement~)
    for payload in ["[\"4008000000000000\"]", "[\"4000000000000000\"]"] {
      @duckdb.receive_fixed_compute_stream_chunk(receiving, 1, [
        input_cursor(payload),
      ]).unwrap()
      @duckdb.drain_fixed_compute_stream_row(receiving).unwrap() |> ignore
    }
    let (received, _) = @duckdb.finish_fixed_compute_stream_receiving(receiving).unwrap()
    let receipt = @duckdb.fixed_compute_stream_receipt_content(received).unwrap()
    assert_true(
      @execution.finish_fixed_producer_stream_measurement(measurement, receipt)
      is Err(_),
    )
    assert_true(
      @execution.finish_fixed_producer_stream_measurement(measurement, receipt)
      is Err(ForeignInput),
    )
  }
}

///|
test "DuckDB stream retains one whole pending chunk and rejects invalid chunks before draining" {
  let compute = @duckdb.prepare_fixed_compute(
    duckdb_captured_input(),
    "held",
    native_compile_limits(),
  ).unwrap()
  let receiver = streamed_fixed_receiver(compute, chunk_rows=2)
  @duckdb.receive_fixed_compute_stream_chunk(receiver, 2, [
    input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
  ]).unwrap()
  assert_eq(
    @duckdb.drain_fixed_compute_stream_row(receiver).unwrap(),
    Some("[{\"id\":3}"),
  )
  assert_true(
    @duckdb.finish_fixed_compute_stream_receiving(receiver) is Err(InvalidState),
  )
  assert_eq(
    @duckdb.drain_fixed_compute_stream_row(receiver).unwrap(),
    Some(",{\"id\":2}"),
  )
  assert_true(@duckdb.drain_fixed_compute_stream_row(receiver).unwrap() is None)
  @duckdb.finish_fixed_compute_stream_receiving(receiver).unwrap() |> ignore
  let invalid = streamed_fixed_receiver(compute, chunk_rows=2)
  assert_true(
    @duckdb.receive_fixed_compute_stream_chunk(invalid, 2, [
      input_cursor("[\"4008000000000000\",\"7ff0000000000000\"]"),
    ])
    is Err(Physical(Cell(1, 0, _))),
  )
  assert_true(
    @duckdb.drain_fixed_compute_stream_row(invalid) is Err(InvalidState),
  )
}

///|
fn streamed_fixed_receiver(
  compute : @duckdb.FixedCompute,
  chunk_rows? : Int = 1,
  batch_bytes? : Int = 64,
  measurement? : @execution.FixedProducerMeasurement,
) -> @duckdb.FixedComputeReceiving {
  @duckdb.prepare_fixed_compute_stream_receiving(
    compute,
    [("id", @duckdb.Float64)],
    { max_rows: 2, max_cells: 2, max_nodes: 2, max_text_bytes: 0, },
    { max_nodes: 4, max_text_bytes: 4, max_depth: 2, max_work: 8, },
    100,
    {
      max_bytes: 100,
      max_nodes: 10,
      max_depth: 3,
      max_columns: 1,
      max_order_work: 100,
    },
    batch_bytes,
    chunk_rows,
    measurement?,
  ).unwrap()
}

///|
test "DuckDB streamed receiving drains exact canonical bytes without a row receipt" {
  let input = duckdb_captured_input()
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let receiver = streamed_fixed_receiver(compute)
  @duckdb.receive_fixed_compute_stream_chunk(receiver, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  // Backpressure must not overwrite the unconsumed chunk or publish its content.
  assert_true(
    @duckdb.receive_fixed_compute_stream_chunk(receiver, 1, [
      input_cursor("[\"4000000000000000\"]"),
    ])
    is Err(InvalidState),
  )
  assert_true(
    @duckdb.finish_fixed_compute_stream_receiving(receiver) is Err(InvalidState),
  )
  assert_eq(
    @duckdb.drain_fixed_compute_stream_row(receiver).unwrap(),
    Some("[{\"id\":3}"),
  )
  assert_true(@duckdb.drain_fixed_compute_stream_row(receiver).unwrap() is None)
  @duckdb.receive_fixed_compute_stream_chunk(receiver, 1, [
    input_cursor("[\"4000000000000000\"]"),
  ]).unwrap()
  assert_eq(
    @duckdb.drain_fixed_compute_stream_row(receiver).unwrap(),
    Some(",{\"id\":2}"),
  )
  let (receipt, tail) = @duckdb.finish_fixed_compute_stream_receiving(receiver).unwrap()
  assert_eq(tail, "]")
  let admitted = @duckdb.fixed_compute_stream_receipt_content(receipt).unwrap()
  let (cid, bytes, nodes, rows) = @execution.output_stream_identity(admitted)
  let expected = @encode.hashing_writer(100, 10, 3)
  @encode.emit_json(@json.parse("[{\"id\":3},{\"id\":2}]"), expected)
  assert_eq(cid, "sha256:" + @encode.finish_hash(expected))
  assert_eq((bytes, nodes, rows), (19, 5, 2))
  assert_true(
    @duckdb.finish_fixed_compute_receiving(receiver) is Err(InvalidState),
  )
  assert_true(@duckdb.fixed_compute_stream_receipt_matches(receipt, receiver))
  assert_false(
    @duckdb.fixed_compute_stream_receipt_matches(
      receipt,
      streamed_fixed_receiver(compute),
    ),
  )
  @duckdb.abort_fixed_compute_receiving(receiver)
  assert_true(@duckdb.fixed_compute_stream_receipt_content(receipt) is None)
  assert_true(@execution.producer_read_available(input))
}

///|
test "DuckDB stream physical and storage bounds are terminal without revoking the producer" {
  let input = duckdb_captured_input()
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let oversized = streamed_fixed_receiver(compute)
  assert_true(
    @duckdb.receive_fixed_compute_stream_chunk(oversized, 2, [
      input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
    ])
    is Err(Physical(RowLimit)),
  )
  assert_true(
    @duckdb.finish_fixed_compute_stream_receiving(oversized)
    is Err(InvalidState),
  )
  let short = streamed_fixed_receiver(compute, batch_bytes=4)
  @duckdb.receive_fixed_compute_stream_chunk(short, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  assert_true(@duckdb.drain_fixed_compute_stream_row(short) is Err(Stream(_)))
  assert_true(
    @duckdb.finish_fixed_compute_stream_receiving(short) is Err(InvalidState),
  )
  for payload in ["[null]", "[\"7ff0000000000000\"]"] {
    let invalid = streamed_fixed_receiver(compute)
    assert_true(
      @duckdb.receive_fixed_compute_stream_chunk(invalid, 1, [
        input_cursor(payload),
      ])
      is Err(Physical(_)),
    )
    assert_true(
      @duckdb.finish_fixed_compute_stream_receiving(invalid)
      is Err(InvalidState),
    )
  }
  let empty = streamed_fixed_receiver(compute)
  let (receipt, tail) = @duckdb.finish_fixed_compute_stream_receiving(empty).unwrap()
  assert_eq(tail, "[]")
  let (_, bytes, nodes, rows) = @execution.output_stream_identity(
    @duckdb.fixed_compute_stream_receipt_content(receipt).unwrap(),
  )
  assert_eq((bytes, nodes, rows), (2, 1, 0))
  assert_true(@execution.producer_read_available(input))
}
