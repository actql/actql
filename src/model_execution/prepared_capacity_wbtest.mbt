///|
fn prepared_capacity_test_ledger(
  retained : Int64,
  execution : Int64,
) -> @resources.Ledger {
  let ledger = @resources.create_ledger({
    planning_work: 1,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 40L,
    retained_bytes: retained,
    execution_bytes: execution,
  }).unwrap()
  @resources.configure_quantities(ledger, {
    tokens: 2L,
    cost_units: 0L,
    duration_ms: 10L,
  }).unwrap()
  ledger
}

///|
fn prepared_capacity_test_cursor(wire : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(wire, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn prepared_capacity_test_rows(
  empty? : Bool = false,
) -> @relation.PreparedInferRows raise {
  let pipeline = @pipeline.check(
    prepared_capacity_test_cursor(
      if empty {
        (
          #|[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[]},"as":"input"}]
        )
      } else {
        (
          #|[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"b","text":null},{"id":"a","text":"urgent"}]},"as":"input"}]
        )
      },
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let producer = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(producer),
    @pipeline.Step(0),
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let key = @evidence.declare_primary_key(
    prepared_capacity_test_cursor("[\"id\"]"),
    carrier,
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  let checked = @infer.check(
    prepared_capacity_test_cursor(
      (
        #|{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}}
      ),
    ),
    carrier,
    Some(@evidence.singleton_key(key)),
    model_execution_test_tasks(),
    None,
    {
      max_work: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
      max_tokens: 1000,
      max_key_fields: 1,
      max_input_roles: 1,
    },
  ).unwrap()
  let prepared = @lower.prepare_infer_inputs(checked, None, {
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }).unwrap()
  let source = @relation.capture_values(producer, 0, max_rows=2, {
    max_nodes: 100,
    max_text_bytes: 100,
    max_work: 10000,
    max_depth: 10,
  }).unwrap()
  let input = @relation.bind_infer_captured_input(
    prepared,
    producer,
    @pipeline.Step(0),
    source,
  ).unwrap()
  let preparation = @relation.start_infer_rows_preparation(
    @bounded.control(),
    input,
    {
      max_items: 2,
      max_work: 10000,
      max_frames: 100,
      max_workspace_slots: 1000,
      values: { max_nodes: 4, max_text_bytes: 8, max_depth: 0, },
      logical: {
        max_input_rows: 2L,
        max_value_bytes: 1000L,
        max_live_value_bytes: 10000L,
        max_work: 10000L,
      },
    },
  ).unwrap()
  for _ in 0..<10000 {
    match @relation.advance_infer_rows_preparation(preparation, 1).unwrap() {
      @relation.InferRowsComplete(rows, ..) => {
        assert_true(
          @relation.cleanup_infer_rows_preparation(preparation).unwrap(),
        )
        return rows
      }
      @relation.InferRowsContinue(..) => ()
      _ => abort("Unexpected preparation terminal")
    }
  }
  abort("Finite prepared-capacity fixture did not finish")
}

///|
fn prepared_capacity_test_limits(retained : Int64) -> ModelExecutionLimits {
  {
    max_items: 2,
    max_work: 10000,
    max_request_bytes: 1000L,
    max_response_bytes: 1000L,
    value_limits: { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
    ledger: {
      planning_work: 10000,
      attempts: 2,
      holdings: 2,
      transfer_bytes: 4000L,
      retained_bytes: retained,
      execution_bytes: 1000L,
    },
  }
}

///|
test "Model prepared capacity: original owner holds through output use and pending cleanup" {
  let rows = prepared_capacity_test_rows()
  let sends = Ref(0)
  let provider = install_model_provider("models/fixture", _ => {
    sends.val += 1
    Err(ProviderError)
  }).unwrap()
  let active = start_model_owned(
    rows,
    Provider(provider),
    "sha256:" + "a".repeat(64),
    prepared_capacity_test_limits(100L),
    None,
    durable_calls=true,
    send_mask=Some([false, false]),
    prepared_capacity=Some({
      prepared_rows: 2,
      retained_bytes: 100L,
      execution_bytes: 5L,
    }),
  ).unwrap()
  let claim = active.state.prepared_capacity.unwrap()
  assert_eq(@resources.ledger_usage(active.state.ledger).attempts, 0)
  assert_eq(
    model_execution_resource_usage(active).reserved_retention_bytes,
    100L,
  )
  assert_eq(model_execution_resource_usage(active).reserved_execution_bytes, 5L)
  assert_false(@relation.cleanup_prepared_infer_rows(rows))
  let physical_done = Ref(false)
  let cleanups = Ref(0)
  // This explicit cursor double isolates the existing physical cleanup
  // boundary; no public transport or successful response is fabricated.
  active.state.physical_cursors.push({
    advance: () => Err(InvalidProvider),
    cleanup: () => {
      cleanups.val += 1
      physical_done.val
    },
  })
  assert_true(request_model_cancel(active))
  assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
  // Whitebox output-use guard, not a manufactured public capture.
  active.state.output_uses = 1
  assert_false(cleanup_model_execution(active).unwrap())
  assert_eq(cleanups.val, 0)
  assert_true(@resources.capacity_reservation_open(claim))
  active.state.output_uses = 0
  assert_false(cleanup_model_execution(active).unwrap())
  assert_eq(cleanups.val, 1)
  assert_true(@bounded.cleanup_pending(active.session))
  assert_true(@resources.capacity_reservation_open(claim))
  assert_eq(
    model_execution_resource_usage(active).reserved_retention_bytes,
    100L,
  )
  assert_false(@relation.cleanup_prepared_infer_rows(rows))
  physical_done.val = true
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(cleanups.val, 2)
  assert_true(active.state.reclaimed)
  assert_true(active.state.prepared_capacity is None)
  assert_false(@resources.capacity_reservation_open(claim))
  assert_eq(model_execution_resource_usage(active).reserved_retention_bytes, 0L)
  assert_eq(model_execution_resource_usage(active).reserved_execution_bytes, 0L)
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(cleanups.val, 2)
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
  assert_eq(sends.val, 0)
}

///|
test "Model prepared capacity: admission failure cannot acquire the original input" {
  for (count, retained) in [(2, 99L), (1, 100L)] {
    let rows = prepared_capacity_test_rows()
    let sends = Ref(0)
    let provider = install_model_provider("models/fixture", _ => {
      sends.val += 1
      Err(ProviderError)
    }).unwrap()
    let result = start_model_owned(
      rows,
      Provider(provider),
      "sha256:" + "a".repeat(64),
      prepared_capacity_test_limits(retained),
      None,
      prepared_capacity=Some({
        prepared_rows: count,
        retained_bytes: 100L,
        execution_bytes: 5L,
      }),
    )
    assert_true(
      if count == 1 {
        result is Err(InvalidLimits)
      } else {
        result is Err(Ledger(@resources.RetentionLimit))
      },
    )
    assert_eq(sends.val, 0)
    assert_true(@relation.cleanup_prepared_infer_rows(rows))
  }
}

///|
test "Model prepared capacity: all-row byte claim grants no send or quantities" {
  // An independent synthetic envelope of 2 * 40 + 20 control and 5 scratch
  // units, not the unadopted Model total or a measurement of physical bytes.
  // Both masked rows remain prepared: neither 0 nor 1 eligible send is R=2.
  for mask in [[false, false], [true, false]] {
    let ledger = prepared_capacity_test_ledger(100L, 5L)
    let quantities = @resources.quantity_usage(ledger)
    let claim = reserve_prepared_model_capacity(
        ledger,
        mask.length(),
        Some({ prepared_rows: 2, retained_bytes: 100L, execution_bytes: 5L, }),
      )
      .unwrap()
      .unwrap()
    let usage = @resources.ledger_usage(ledger)
    assert_eq(usage.attempts, 0)
    assert_eq(usage.holdings, 0)
    assert_eq(usage.reserved_transfer_bytes, 0L)
    assert_eq(usage.uncertain_transfer_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 100L)
    assert_eq(usage.reserved_execution_bytes, 5L)
    assert_eq(@resources.quantity_usage(ledger), quantities)
    assert_true(@resources.capacity_reservation_open(claim))
    @resources.settle_capacity(ledger, claim).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    assert_true(
      @resources.settle_capacity(ledger, claim)
      is Err(@resources.ClosedReservation),
    )
  }
}

///|
test "Model prepared capacity: one-short and foreign counts fail without materialization" {
  for (retained, execution) in [(99L, 5L), (100L, 4L)] {
    let ledger = prepared_capacity_test_ledger(retained, execution)
    let before = @resources.ledger_usage(ledger)
    let result = reserve_prepared_model_capacity(
      ledger,
      2,
      Some({ prepared_rows: 2, retained_bytes: 100L, execution_bytes: 5L, }),
    )
    assert_true(
      if retained == 99L {
        result is Err(Ledger(@resources.RetentionLimit))
      } else {
        result is Err(Ledger(@resources.ExecutionLimit))
      },
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  let ledger = prepared_capacity_test_ledger(100L, 5L)
  let before = @resources.ledger_usage(ledger)
  for
    (rows, bound_rows, retained, execution) in [
      (2, 0, 100L, 5L),
      (2, 1, 100L, 5L),
      (-1, -1, 100L, 5L),
      (2, 2, 0L, 5L),
      (2, 2, -1L, 5L),
      (2, 2, 100L, -1L),
    ] {
    assert_true(
      reserve_prepared_model_capacity(
        ledger,
        rows,
        Some({
          prepared_rows: bound_rows,
          retained_bytes: retained,
          execution_bytes: execution,
        }),
      )
      is Err(InvalidLimits),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  // Existing callers retain their existing behavior until the complete extra
  // envelope and original-key extension are reviewed and connected together.
  assert_true(reserve_prepared_model_capacity(ledger, 2, None) is Ok(None))
  assert_eq(@resources.ledger_usage(ledger), before)
}
