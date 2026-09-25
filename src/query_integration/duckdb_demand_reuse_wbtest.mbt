///|
/// The same native capture with no qualifying rows: validation sees only 1.
fn empty_native_retained_receive(
  attempt : @duckdb_query.DuckDBNativeAttempt,
) -> @execution.AdmittedOutputStreamReceipt {
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
  for role in [@duckdb.ValidationScan, @duckdb.NativeResult] {
    let port = @duckdb_query.begin_duckdb_native_receipt(attempt, role, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    if role == @duckdb.ValidationScan {
      @duckdb_query.accept_duckdb_native_chunk(attempt, port, 1, [
        input_cursor("[\"3ff0000000000000\"]"),
      ]).unwrap()
    }
    @duckdb_query.finish_duckdb_native_receipt(attempt, port).unwrap()
  }
  let (receipt, _) = @duckdb_query.finish_duckdb_native_output_stream(attempt)
    .unwrap()
    .unwrap()
  receipt
}

///|
fn demand_reuse_input(
  f : NativeIssuerFixture,
  empty? : Bool = false,
) -> @execution.ProducerRead raise {
  let attempt = native_issued_attempt(f)
  let receipt = if empty {
    empty_native_retained_receive(attempt)
  } else {
    native_retained_receive(attempt)
  }
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
  @execution.prepare_producer_read(
    receiver,
    @execution.bind_completed_input(receiver, 0, owner, output).unwrap(),
    100,
    10000,
  ).unwrap()
}

///|
fn demand_value_issue_text(issue : @duckdb.NativeValueIssue) -> String {
  match issue {
    MeasurementWork => "work"
    Measurement(InvalidStructure) => "measurement:structure"
    Measurement(InvalidUnicode) => "measurement:unicode"
    Measurement(InvalidNumber) => "measurement:number"
    Measurement(OutputLimit) => "measurement:output-limit"
    Measurement(ClosedWriter) => "measurement:closed"
    ValueBytes => "value-bytes"
    OutputRows => "output-rows"
  }
}

///|
fn demand_outcome_text(
  measured : Result[@duckdb.FixedComputeDemand, @duckdb.NativeDemandIssue],
) -> String {
  match measured {
    Ok(value) =>
      match @duckdb.fixed_compute_demand_usage(value) {
        Comparison(u) =>
          "ok \{u.rows} \{u.field_bytes} \{u.rhs_bytes.unwrap_or(-1)} \{u.true_rows} \{u.false_rows} \{u.null_rows} \{u.predicate_bytes} \{u.physical_work} \{u.physical_bytes} \{u.physical_nodes}"
        _ => "other-usage"
      }
    Err(Operand(row, rhs, issue)) =>
      "operand \{row} \{rhs} \{demand_value_issue_text(issue)}"
    Err(Predicate(issue)) => "predicate \{demand_value_issue_text(issue)}"
    Err(InvalidState) => "invalid-state"
    Err(InvalidLimits) => "invalid-limits"
    Err(InvalidLayout) => "invalid-layout"
    Err(InvalidResultCount) => "invalid-result-count"
    Err(InputRepresentationRequired) => "representation-required"
  }
}

///|
/// One consumer of the reused material. `summary` selects the per-value facts;
/// otherwise (or when they are declined) the ordered one-column scan runs.
fn demand_reuse_outcome(
  input : @execution.ProducerRead,
  ceiling : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
  summary : Bool,
  live? : Ref[Bool] = Ref(true),
) -> (Bool, String) raise {
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "streamed",
    native_compile_limits(),
  ).unwrap()
  let fixed = @duckdb.fixed_compute_import(compute, 0).unwrap()
  let stream = @duckdb.prepare_fixed_import_stream(
    fixed,
    100,
    native_retained_values(),
    native_completion_limits().receipts,
    1000,
  ).unwrap()
  @duckdb.attach_fixed_import_demand(stream, compute, ceiling, physical).unwrap()
  let proof = @execution.prepare_trusted_retained_scan_reuse(
    @duckdb.fixed_import_input(fixed),
    live,
    (live, _) => live.val,
  ).unwrap()
  assert_true(@duckdb.reuse_fixed_import_identity(stream, proof))
  assert_true(@duckdb.reuse_fixed_import_values(stream))
  let used = summary && @duckdb.reuse_fixed_import_demand_measurement(stream)
  if used {
    // A discharged demand cannot be discharged again or mixed with a scan.
    assert_false(@duckdb.reuse_fixed_import_demand_measurement(stream))
    assert_true(
      @duckdb.prepare_fixed_import_reused_demand_physical(
        stream,
        [("id", @duckdb.Float64)],
        { max_rows: 2, max_cells: 2, max_nodes: 10, max_text_bytes: 100, },
        1000,
      )
      is Err(_),
    )
  } else {
    let column = @duckdb.prepare_fixed_import_reused_demand_physical(
      stream,
      [("id", @duckdb.Float64)],
      { max_rows: 2, max_cells: 2, max_nodes: 10, max_text_bytes: 100, },
      1000,
    ).unwrap()
    @duckdb.verify_fixed_import_reused_demand_chunk(stream, column, 2, [
      input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
    ]).unwrap()
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
  (
    used,
    demand_outcome_text(
      @duckdb.measure_fixed_compute_demand(
        compute,
        received,
        ceiling,
        physical,
        input_demand=demand,
      ),
    ),
  )
}

///|
test "reused comparison demand facts equal the ordered demand scan" {
  let f = native_issuer_fixture()
  let input = demand_reuse_input(f)
  let exact : @execution.FixedInputGuardMeasureLimits = {
    max_work: 7,
    max_bytes: 3,
    max_nodes: 3,
    max_depth: 10,
  }
  let cases : Array[(Int, @execution.FixedInputGuardMeasureLimits, Bool)] = [
    // Work, bytes and nodes exactly suffice: the scan is not needed.
    (5, exact, true),
    // One unit short: the first failing operand must be located by the scan.
    (5, { ..exact, max_bytes: 2, }, false),
    (5, { ..exact, max_nodes: 2, }, false),
    (5, { ..exact, max_work: 6, }, false),
    // Scalar operands have depth 0, so the scan and the facts both succeed.
    (5, { ..exact, max_depth: 0, }, true),
    // A predicate failure after complete operand measurement is the same rule.
    (4, exact, true),
    // Operand bytes above the per-value ceiling keep the ordered failure.
    (0, exact, false),
  ]
  for item in cases {
    let (ceiling, physical, expected) = item
    let (scanned_used, scanned) = demand_reuse_outcome(
      input, ceiling, physical, false,
    )
    let (used, summarized) = demand_reuse_outcome(
      input, ceiling, physical, true,
    )
    assert_false(scanned_used)
    assert_eq(used, expected)
    assert_eq(summarized, scanned)
  }
  let (_, success) = demand_reuse_outcome(input, 5, exact, true)
  assert_eq(success, "ok 2 2 1 1 1 0 9 7 3 3")
  // A revoked generation lease cannot supply facts; the scan then refuses too.
  let live = Ref(true)
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "streamed",
    native_compile_limits(),
  ).unwrap()
  let fixed = @duckdb.fixed_compute_import(compute, 0).unwrap()
  let stream = @duckdb.prepare_fixed_import_stream(
    fixed,
    100,
    native_retained_values(),
    native_completion_limits().receipts,
    1000,
  ).unwrap()
  @duckdb.attach_fixed_import_demand(stream, compute, 5, exact).unwrap()
  let proof = @execution.prepare_trusted_retained_scan_reuse(
    @duckdb.fixed_import_input(fixed),
    live,
    (live, _) => live.val,
  ).unwrap()
  assert_true(@duckdb.reuse_fixed_import_identity(stream, proof))
  assert_true(@duckdb.reuse_fixed_import_values(stream))
  live.val = false
  assert_false(@duckdb.reuse_fixed_import_demand_measurement(stream))
  assert_true(@duckdb.finish_fixed_import_stream(stream) is Err(_))
  @duckdb_query.close_duckdb_native_issuer(f.issuer)
}

///|
test "an empty reused read discharges its demand once and never mixes a scan" {
  let f = native_issuer_fixture()
  let input = demand_reuse_input(f, empty=true)
  assert_eq(@execution.producer_read_row_count(input), 0)
  let exact : @execution.FixedInputGuardMeasureLimits = {
    max_work: 7,
    max_bytes: 3,
    max_nodes: 3,
    max_depth: 10,
  }
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "streamed",
    native_compile_limits(),
  ).unwrap()
  let fixed = @duckdb.fixed_compute_import(compute, 0).unwrap()
  let stream = @duckdb.prepare_fixed_import_stream(
    fixed,
    100,
    native_retained_values(),
    native_completion_limits().receipts,
    1000,
  ).unwrap()
  @duckdb.attach_fixed_import_demand(stream, compute, 5, exact).unwrap()
  let proof = @execution.prepare_trusted_retained_scan_reuse(
    @duckdb.fixed_import_input(fixed),
    (),
    (_, _) => true,
  ).unwrap()
  assert_true(@duckdb.reuse_fixed_import_identity(stream, proof))
  assert_true(@duckdb.reuse_fixed_import_values(stream))
  assert_true(@duckdb.reuse_fixed_import_demand_measurement(stream))
  assert_false(@duckdb.reuse_fixed_import_demand_measurement(stream))
  assert_true(
    @duckdb.prepare_fixed_import_reused_demand_physical(
      stream,
      [("id", @duckdb.Float64)],
      { max_rows: 0, max_cells: 0, max_nodes: 10, max_text_bytes: 100, },
      1000,
    )
    is Err(_),
  )
  @duckdb.finish_fixed_import_stream(stream).unwrap() |> ignore
  assert_true(@duckdb.fixed_import_verified_demand(stream) is Some(_))
  // Same as the ordered scan of zero operands: no RHS and nothing charged.
  let (_, scanned) = demand_reuse_outcome_empty(input, exact, false)
  let (used, summarized) = demand_reuse_outcome_empty(input, exact, true)
  assert_true(used)
  assert_eq(summarized, scanned)
  @duckdb_query.close_duckdb_native_issuer(f.issuer)
}

///|
fn demand_reuse_outcome_empty(
  input : @execution.ProducerRead,
  physical : @execution.FixedInputGuardMeasureLimits,
  summary : Bool,
) -> (Bool, String) raise {
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "streamed",
    native_compile_limits(),
  ).unwrap()
  let fixed = @duckdb.fixed_compute_import(compute, 0).unwrap()
  let stream = @duckdb.prepare_fixed_import_stream(
    fixed,
    100,
    native_retained_values(),
    native_completion_limits().receipts,
    1000,
  ).unwrap()
  @duckdb.attach_fixed_import_demand(stream, compute, 5, physical).unwrap()
  let proof = @execution.prepare_trusted_retained_scan_reuse(
    @duckdb.fixed_import_input(fixed),
    (),
    (_, _) => true,
  ).unwrap()
  assert_true(@duckdb.reuse_fixed_import_identity(stream, proof))
  assert_true(@duckdb.reuse_fixed_import_values(stream))
  let used = summary && @duckdb.reuse_fixed_import_demand_measurement(stream)
  if !used {
    @duckdb.prepare_fixed_import_reused_demand_physical(
      stream,
      [("id", @duckdb.Float64)],
      { max_rows: 0, max_cells: 0, max_nodes: 10, max_text_bytes: 100, },
      1000,
    ).unwrap()
    |> ignore
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
  let received = @duckdb.finish_fixed_compute_receiving(receiving).unwrap()
  (
    used,
    demand_outcome_text(
      @duckdb.measure_fixed_compute_demand(
        compute,
        received,
        5,
        physical,
        input_demand=demand,
      ),
    ),
  )
}
