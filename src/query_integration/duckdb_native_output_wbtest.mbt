///|
test "native captured output converts without replay and preserves success across conversion exhaustion" {
  let f = native_issuer_fixture()
  let attempt = native_issued_attempt(f)
  native_attempt_receive_fixture(attempt)
  f.transport.push(attempt)
  let observation = @duckdb_query.complete_duckdb_native_capture(
    f.issuer,
    attempt,
    native_completion_limits(),
  ).unwrap()
  // Two {id:number} rows: one object and scalar each; id contributes 2 bytes
  // and 2 work plus one scalar visit per row. Numeric values add no text bytes.
  let exact : @execution.ValueLimits = {
    max_nodes: 4,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 8,
  }
  for
    limits in [
      { ..exact, max_nodes: 3, },
      { ..exact, max_text_bytes: 3, },
      { ..exact, max_work: 7, },
      { ..exact, max_depth: 1, },
    ] {
    assert_true(
      @duckdb_query.materialize_duckdb_native_output(
        f.issuer,
        attempt,
        observation,
        2,
        limits,
      )
      is Err(NativeOutput(Retention(CaptureLimit))),
    )
    assert_true(
      @duckdb_query.verify_duckdb_native_observation(
        f.issuer,
        attempt,
        observation,
      )
      is Ok(_),
    )
  }
  assert_true(
    @duckdb_query.materialize_duckdb_native_output(
      f.issuer,
      attempt,
      observation,
      1,
      exact,
    )
    is Err(NativeOutput(Retention(CaptureLimit))),
  )
  let output = @duckdb_query.materialize_duckdb_native_output(
    f.issuer,
    attempt,
    observation,
    2,
    exact,
  ).unwrap()
  let rows = @duckdb_query.duckdb_native_output_rows(output).unwrap()
  assert_true(
    physical_equal(
      @execution.admitted_output_owner(rows),
      @duckdb.native_query_owner(
        @duckdb.native_scan_query(
          @duckdb_query.duckdb_native_preparation_scan(
            @duckdb_query.duckdb_native_attempt_preparation(attempt),
          ),
        ),
      ),
    ),
  )
  assert_eq(@execution.admitted_output_target(rows), @pipeline.Step(1))
  assert_eq(@execution.admitted_output_row_count(rows), 2)
  assert_true(
    @execution.admitted_output_cell(rows, 0, 0) is Some(@admitted.Number(3.0)),
  )
  assert_true(
    @execution.admitted_output_cell(rows, 1, 0) is Some(@admitted.Number(2.0)),
  )
  assert_eq(@execution.admitted_output_usage(rows), {
    nodes: 4,
    text_bytes: 4,
    work: 8,
  })
  let other = native_issuer_fixture()
  let completed = @duckdb_query.complete_duckdb_native_output(
    output, 100, 10000,
  ).unwrap()
  let owner = @execution.admitted_output_owner(rows)
  let generated = @query.query_generated_sequence(
    @planning.query_material_owner(
      @planning.query_requirement_material(f.requirement),
    ),
  )
  assert_true(
    @duckdb_query.complete_duckdb_native_output(output, 0, 10000) is Err(Limit),
  )
  assert_true(
    @duckdb_query.complete_duckdb_native_output(output, 100, 0) is Err(Limit),
  )
  assert_true(
    @duckdb_query.complete_duckdb_native_output(output, -1, 10000)
    is Err(InvalidLimits),
  )
  let unavailable = @execution.prepare_trusted_output_port(
    @execution.generated_completion_preparation(generated),
    @pipeline.Step(1),
    100,
    10000,
    (_ : Unit) => None,
  ).unwrap()
  assert_true(
    @execution.complete_trusted_output(unavailable, ()) is Err(Unverified),
  )
  let foreign_generated = @query.query_generated_sequence(
    @planning.query_material_owner(
      @planning.query_requirement_material(other.requirement),
    ),
  )
  // Even trusted verifier wiring cannot substitute a content-equal preparation
  // for the exact owner of the retained material.
  let foreign_port = @execution.prepare_trusted_output_port(
    @execution.generated_completion_preparation(foreign_generated),
    @pipeline.Step(1),
    100,
    10000,
    (_ : Unit) => Some(rows),
  ).unwrap()
  assert_true(
    @execution.complete_trusted_output(foreign_port, ()) is Err(ForeignOutput),
  )
  assert_true(
    @execution.prepare_trusted_output_port(
      @execution.generated_completion_preparation(generated),
      @pipeline.Step(0),
      100,
      10000,
      (_ : Unit) => Some(rows),
    )
    is Err(InvalidTarget),
  )
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let bound = @execution.bind_completed_input(receiver, 0, owner, completed).unwrap()
  let consumer = compute_test_sequence(receiver)
  let result = @execution.execute_generated_sequence(
    consumer,
    [],
    compute_test_limits(),
    produced=[bound],
  ).unwrap()
  let downstream = @execution.completed_output(result, @pipeline.Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(downstream), 2)
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(3)))
  assert_true(@execution.completed_cell(downstream, 1, 0) is Some(Number(2)))
  assert_true(
    @duckdb_query.materialize_duckdb_native_output(
      other.issuer,
      attempt,
      observation,
      2,
      exact,
    )
    is Err(_),
  )
  let compute_owner = typed_receiver(
    owner, "[{\"filter\":\"id > 0\"},{\"select\":[\"id\"]}]",
  )
  let compute_bound = @execution.bind_completed_input(
    compute_owner, 0, owner, completed,
  ).unwrap()
  let compute_input = @execution.prepare_producer_read(
    compute_owner, compute_bound, 100, 1000,
  ).unwrap()
  let compute_plan = @duckdb.prepare_fixed_compute(
    compute_input,
    "owned",
    native_compile_limits(),
  ).unwrap()
  let physical : @duckdb.PhysicalResultLimits = {
    max_rows: 2,
    max_cells: 2,
    max_nodes: 2,
    max_text_bytes: 0,
  }
  let receiving = @duckdb.prepare_fixed_compute_receiving(
    compute_plan,
    [("id", @duckdb.Float64)],
    physical,
    exact,
    100,
  ).unwrap()
  @duckdb.receive_fixed_compute_chunk(receiving, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  @duckdb_query.close_duckdb_native_issuer(f.issuer)
  assert_false(@execution.producer_read_available(compute_input))
  assert_true(
    @duckdb.finish_fixed_compute_receiving(receiving) is Err(InputUnavailable),
  )
  assert_true(
    @duckdb.finish_fixed_compute_receiving(receiving) is Err(InvalidState),
  )
  assert_true(
    @duckdb.prepare_fixed_compute_receiving(
      compute_plan,
      [("id", @duckdb.Float64)],
      physical,
      exact,
      100,
    )
    is Err(InputUnavailable),
  )
  assert_true(
    @duckdb.prepare_fixed_import(compute_input, "owned", 100, 1000)
    is Err(InputUnavailable),
  )
  assert_true(
    @duckdb.fixed_import_parameter(
      @duckdb.fixed_compute_import(compute_plan, 0).unwrap(),
      0,
      0,
    )
    is Err(InputUnavailable),
  )
  assert_true(
    @connector.prepare_fixed_compute_request([compute_input], {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    })
    is Err(InputUnavailable),
  )
  assert_true(
    @duckdb_query.duckdb_native_output_rows(output) is Err(IssuerClosed),
  )
  assert_true(
    @duckdb_query.complete_duckdb_native_output(output, 100, 10000)
    is Err(Unverified),
  )
  assert_true(
    @execution.bind_completed_input(receiver, 0, owner, completed)
    is Err(ProducerUnavailable),
  )
  assert_true(
    @execution.execute_generated_sequence(consumer, [], compute_test_limits(), produced=[
      bound,
    ])
    is Err(InputOwnership),
  )
  // A finished downstream computation owns its result independently.
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(3)))
}
