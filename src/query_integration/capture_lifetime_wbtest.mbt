///|
// Common acceptance cases for observation-bound producer inputs. No backend
// can substitute bind-time verification for execution-time liveness.
fn assert_capture_input_lifetime(
  receiver : @lower.BoundPrepared,
  bind : () -> @execution.BoundProducerInput?,
  revoke : () -> Unit,
  before_binding? : Bool = false,
) -> Unit raise {
  if before_binding {
    revoke()
    assert_true(bind() is None)
    return
  }
  let bound = bind().unwrap()
  let read = @execution.prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let imported = @duckdb.prepare_fixed_import(read, "owned", 100, 10000).unwrap()
  let generated = compute_test_sequence(receiver)
  let pending = @execution.prepare_local_compute_attempt(generated, [bound], 3).unwrap()
  let completed = @execution.execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
    produced=[bound],
  ).unwrap()
  let output = @execution.completed_output(completed, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  revoke()
  assert_true(bind() is None)
  assert_true(
    @execution.prepare_producer_read(receiver, bound, 100, 10000) is Err(_),
  )
  assert_false(@execution.producer_read_available(read))
  assert_true(
    @duckdb.prepare_fixed_import(read, "new", 100, 10000)
    is Err(InputUnavailable),
  )
  assert_true(
    @duckdb.fixed_import_parameter(imported, 0, 0) is Err(InputUnavailable),
  )
  assert_true(
    @execution.execute_local_compute_attempt(pending, compute_test_limits())
    is Err(Execution(InputOwnership)),
  )
  let fresh = @execution.prepare_local_compute_attempt(generated, [bound], 3).unwrap()
  assert_true(
    @execution.execute_local_compute_attempt(fresh, compute_test_limits())
    is Err(Execution(InputOwnership)),
  )
  // Finished downstream results are independent, including new consumers of them.
  let next = typed_receiver(receiver, "[{\"select\":[\"id\"]}]", target=Step(0))
  let next_bound = @execution.bind_completed_input(next, 0, receiver, output).unwrap()
  assert_true(
    @execution.execute_generated_sequence(
      compute_test_sequence(next),
      [],
      compute_test_limits(),
      produced=[next_bound],
    )
    is Ok(_),
  )
}

///|
test "broad pre-capture diagnostics carry no consumer handle and disappear on abort" {
  let f = broad_issuer_fixture()
  let attempt = broad_issued_attempt(f)
  broad_issued_run(f, attempt)
  assert_eq(@duckdb_query.duckdb_broad_attempt_row_count(attempt), Some(2))
  let records = @duckdb_query.issue_duckdb_broad_records(
    attempt,
    query_material_limits(),
  ).unwrap()
  assert_eq(@duckdb_query.duckdb_broad_attempt_row_count(attempt), Some(2))
  @duckdb_query.abort_duckdb_broad_attempt(attempt)
  assert_true(@duckdb_query.duckdb_broad_attempt_row_count(attempt) is None)
  assert_true(
    @duckdb_query.capture_duckdb_broad_query(
      f.issuer,
      attempt,
      records,
      query_capture_limits(),
    )
    is Err(_),
  )
}

///|
test "captured source logical export remains bound to issuer lifetime" {
  let f = broad_issuer_fixture()
  let attempt = broad_issued_attempt(f)
  broad_issued_run(f, attempt)
  let records = @duckdb_query.issue_duckdb_broad_records(
    attempt, query_material_limits(),
  ).unwrap()
  let observation = @duckdb_query.capture_duckdb_broad_query(
    f.issuer, attempt, records, query_capture_limits(),
  ).unwrap()
  let source = @duckdb_query.broad_captured_source(
    f.issuer, attempt, observation,
  ).unwrap()
  let stream = @query.prepare_captured_source_relation_export(
    source,
    100,
    run_limits().output_values,
    row_wire_limits(),
    row_wire_limits(),
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    128,
  ).unwrap()
  let body = StringBuilder()
  while @execution.next_completed_output_export(stream).unwrap() is Some(part) {
    body.write_string(part)
  }
  let (receipt, tail) = @execution.finish_completed_relation_export(stream).unwrap()
  body.write_string(tail)
  assert_eq(@execution.completed_relation_export_field_names(receipt), ["id"])
  assert_eq(body.to_string(), "[{\"id\":3},{\"id\":2}]")
  assert_true(
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(receipt),
    ).has_prefix("sha256:"),
  )
  @execution.cancel_completed_relation_export_receipt(receipt)
  @duckdb_query.close_duckdb_query_issuer(f.issuer)
  assert_true(
    @query.prepare_captured_source_relation_export(
      source,
      100,
      run_limits().output_values,
      row_wire_limits(),
      row_wire_limits(),
      { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      128,
    ) is Err(Unavailable),
  )
}

///|
test "captured broad bindings retain issuer and exact transport liveness" {
  for
    (close_issuer, before_binding) in [
      (true, true),
      (true, false),
      (false, false),
    ] {
    let f = broad_issuer_fixture()
    let attempt = broad_issued_attempt(f)
    broad_issued_run(f, attempt)
    let records = @duckdb_query.issue_duckdb_broad_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let observation = @duckdb_query.capture_duckdb_broad_query(
      f.issuer,
      attempt,
      records,
      query_capture_limits(),
    ).unwrap()
    let owner = @query.query_sequence_owner(f.sequence)
    let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
    let shared = @duckdb_query.broad_captured_source(
      f.issuer,
      attempt,
      observation,
    ).unwrap()
    assert_eq(@query.captured_source_row_count(shared), Some(2))
    assert_capture_input_lifetime(
      receiver,
      fn() {
        match @query.bind_captured_source(shared, receiver, 0) {
          Ok(bound) => Some(bound)
          Err(_) => None
        }
      },
      fn() {
        if close_issuer {
          @duckdb_query.close_duckdb_query_issuer(f.issuer)
        } else {
          f.transport.clear()
        }
      },
      before_binding~,
    )
  }
}

///|
test "captured mock bindings retain issuer liveness for both realizations" {
  for
    (strategy, before_binding) in [
      (@mock.NativeQuery, true),
      (@mock.NativeQuery, false),
      (@mock.BroadWithResidual, true),
      (@mock.BroadWithResidual, false),
    ] {
    let (issuer, sequence) = query_issuer_fixture()
    let owner = @query.query_sequence_owner(sequence)
    let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
    let attempt = query_issuer_attempt(issuer, sequence, strategy)
    query_issuer_run(attempt)
    let records = @mock.issue_mock_query_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let observation = @mock.capture_mock_query(
      issuer,
      attempt,
      records,
      query_capture_limits(),
    ).unwrap()
    let shared = @mock.mock_captured_source(issuer, attempt, observation).unwrap()
    assert_eq(@query.captured_source_row_count(shared), Some(2))
    assert_capture_input_lifetime(
      receiver,
      fn() {
        match @query.bind_captured_source(shared, receiver, 0) {
          Ok(bound) => Some(bound)
          Err(_) => None
        }
      },
      fn() { @mock.close_mock_query_issuer(issuer) },
      before_binding~,
    )
  }
}

///|
test "captured native bindings obey the same issuer and transport lifetime cases" {
  for
    (close_issuer, before_binding) in [
      (true, true),
      (true, false),
      (false, false),
    ] {
    let f = native_issuer_fixture()
    let attempt = native_issued_attempt(f)
    native_attempt_receive_fixture(attempt)
    f.transport.push(attempt)
    let observation = @duckdb_query.complete_duckdb_native_capture(
      f.issuer,
      attempt,
      native_completion_limits(),
    ).unwrap()
    let material = @duckdb_query.materialize_duckdb_native_output(
      f.issuer,
      attempt,
      observation,
      100,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    ).unwrap()
    let shared = @duckdb_query.native_captured_source(material, 100, 10000).unwrap()
    let owner = @execution.admitted_output_owner(
      @duckdb_query.duckdb_native_output_rows(material).unwrap(),
    )
    let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
    assert_capture_input_lifetime(
      receiver,
      fn() {
        match @query.bind_captured_source(shared, receiver, 0) {
          Ok(bound) => Some(bound)
          Err(_) => None
        }
      },
      fn() {
        if close_issuer {
          @duckdb_query.close_duckdb_native_issuer(f.issuer)
        } else {
          f.transport.clear()
        }
      },
      before_binding~,
    )
  }
}
