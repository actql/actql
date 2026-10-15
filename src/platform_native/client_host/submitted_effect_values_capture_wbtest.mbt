///|
fn submitted_values_capture_limits() -> (
  @execution.RetainedRowDecodeLimits,
  @host.PublicationOutputExportLimits,
) {
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 1000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  (
    { max_bytes: 10000, max_nodes: 1000, max_depth: 20, max_text_bytes: 10000, },
    {
      max_result_fields: 10,
      max_result_mapping_work: 100,
      max_result_order_work: 1000,
      max_result_workspace_entries: 20,
      max_rows: 10,
      values: {
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 10000,
      },
      payload_wire: wire,
      logical_wire: wire,
      schema: {
        max_fields: 10,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      max_batch_bytes: 64,
    },
  )
}

///|
fn submitted_values_capture_result(
  inputs : @strategy.CapturedEffectInputs,
) -> Int raise {
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
    let occurrence = @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    )
    if @execution.managed_result_occurrence_name(occurrence) == "out" {
      return index
    }
  }
  fail("capture.original.out")
}

///|
fn submitted_values_capture_finish(
  exported : @strategy.CapturedEffectLocalResultExport,
) -> (@execution.CompletedRelationExportReceipt, Array[String]) raise {
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  let mut complete = false
  for _ in 0..<100 {
    if @execution.advance_completed_result_relation_export(preparation, 64).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  let rows : Array[String] = []
  while @execution.next_completed_output_export_canonical_row(
          stream, 1000, 20, 1000,
        ).unwrap()
        is Some((_, _, row)) {
    rows.push(@canonical.stringify_value(row, 10000, 1000, 20))
  }
  let (receipt, _) = @execution.finish_completed_relation_export(stream).unwrap()
  (receipt, rows)
}

///|
test "Native submitted Values capture exports the original local Result without another claim" {
  let (host, work) = submitted_values_invocation_fixture(
    "values-capture-original",
  )
  defer host.close() |> ignore
  defer work.close() |> ignore
  let request = work.binding.request
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  let inputs = work.pin_original_capture_inputs(1).unwrap()
  defer @strategy.release_captured_effect_inputs(inputs) |> ignore
  let index = submitted_values_capture_result(inputs)
  let (rows, limits) = submitted_values_capture_limits()
  let value = work
    .prepare_original_result_export(inputs, index, rows, 100, 10000, limits)
    .unwrap()
  defer value.close()
  let exported = value.captured_export().unwrap()
  let (receipt, actual) = submitted_values_capture_finish(exported)
  defer @execution.cancel_completed_relation_export_receipt(receipt)
  // The independently authored fixture contains one exact decomposed string,
  // including CR/LF. No returned payload or digest supplies this expectation.
  assert_eq(actual, ["{\"value\":\"e\u0301\\r\\n\"}"])
  assert_eq(
    @execution.completed_relation_export_measurement(receipt).row_count,
    1,
  )
  assert_true(
    @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ),
  )
  assert_true(
    physical_equal(work.run_for_capture().unwrap(), work.work.captured),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  assert_false(host.journal.claim_physical_start(request, true).unwrap())
  value.close()
  assert_true(value.captured_export() is None)
  assert_true(
    @strategy.captured_effect_inputs_match_run(inputs, work.work.captured),
  )
  assert_true(work.work.execution.material() is Some(_))
}

///|
test "Native submitted Values capture refuses same-byte foreign pins and nonlocal Result indexes" {
  let (host, work) = submitted_values_invocation_fixture("values-capture-local")
  defer host.close() |> ignore
  defer work.close() |> ignore
  let (foreign_host, foreign) = submitted_values_invocation_fixture(
    "values-capture-foreign",
  )
  defer foreign_host.close() |> ignore
  defer foreign.close() |> ignore
  let inputs = work.pin_original_capture_inputs(1).unwrap()
  defer @strategy.release_captured_effect_inputs(inputs) |> ignore
  let foreign_inputs = foreign.pin_original_capture_inputs(1).unwrap()
  defer @strategy.release_captured_effect_inputs(foreign_inputs) |> ignore
  let (rows, limits) = submitted_values_capture_limits()
  assert_true(
    work.prepare_original_result_export(
      foreign_inputs, 0, rows, 100, 10000, limits,
    )
    is Err(Export(@local.ForeignInput)),
  )
  assert_true(
    work.prepare_original_result_export(inputs, -1, rows, 100, 10000, limits)
    is Err(Export(@local.MissingResult)),
  )
  assert_true(work.work.execution.material() is Some(_))
  assert_true(foreign.work.execution.material() is Some(_))
}

///|
test "Native submitted Values capture retains pin row and field bounds and caller cleanup" {
  let (host, work) = submitted_values_invocation_fixture(
    "values-capture-bounds",
  )
  defer host.close() |> ignore
  defer work.close() |> ignore
  assert_true(work.pin_original_capture_inputs(0) is Err(Pin(_)))
  let inputs = work.pin_original_capture_inputs(1).unwrap()
  defer @strategy.release_captured_effect_inputs(inputs) |> ignore
  let index = submitted_values_capture_result(inputs)
  let (rows, limits) = submitted_values_capture_limits()
  assert_true(
    work.prepare_original_result_export(
      inputs,
      index,
      { ..rows, max_bytes: 1, },
      100,
      10000,
      limits,
    )
    is Err(Export(_)),
  )
  assert_true(
    work.prepare_original_result_export(inputs, index, rows, 100, 10000, {
      ..limits,
      max_result_fields: 0,
    })
    is Err(Export(_)),
  )
  let value = work
    .prepare_original_result_export(inputs, index, rows, 100, 10000, limits)
    .unwrap()
  value.close()
  assert_true(work.work.execution.material() is Some(_))
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(work.close())
  assert_eq(work.usage().held_bytes, 0L)
  assert_eq(work.usage().reserved_retention_bytes, 0L)
  assert_eq(work.usage().reserved_execution_bytes, 0L)
}

///|
test "Native submitted Values capture releases only new pins after terminal Work retirement" {
  let armed = Ref(false)
  let calls = Ref(0)
  let original : Ref[NativeClientSubmittedEffectValuesWork?] = Ref(None)
  let (host, work) = submitted_values_invocation_fixture(
    "values-capture-retired",
    utc=() => {
      if armed.val {
        calls.val += 1
        if calls.val == 2 && original.val is Some(work) {
          work.close() |> ignore
        }
      }
      "2026-10-10T00:00:01.000Z"
    },
  )
  defer host.close() |> ignore
  defer work.close() |> ignore
  original.val = Some(work)
  armed.val = true
  let result = work.pin_original_capture_inputs(1)
  original.val = None
  assert_eq(calls.val, 2)
  assert_true(result is Err(Work(Work(Unavailable))))
  assert_eq(work.usage().held_bytes, 0L)
  assert_true(
    host.journal.retained(work.binding.request).unwrap().unwrap().physical_start_claimed,
  )
}

///|
test "Native submitted Values capture observes input retirement after the final current callback" {
  let armed = Ref(false)
  let calls = Ref(0)
  let original : Ref[@strategy.CapturedEffectInputs?] = Ref(None)
  let (host, work) = submitted_values_invocation_fixture(
    "values-capture-alias-retired",
    utc=() => {
      if armed.val {
        calls.val += 1
        if calls.val == 2 && original.val is Some(inputs) {
          @strategy.release_captured_effect_inputs(inputs) |> ignore
        }
      }
      "2026-10-10T00:00:01.000Z"
    },
  )
  defer host.close() |> ignore
  defer work.close() |> ignore
  let inputs = work.pin_original_capture_inputs(1).unwrap()
  defer @strategy.release_captured_effect_inputs(inputs) |> ignore
  let index = submitted_values_capture_result(inputs)
  let (rows, limits) = submitted_values_capture_limits()
  original.val = Some(inputs)
  armed.val = true
  let result = work.prepare_original_result_export(
    inputs, index, rows, 100, 10000, limits,
  )
  original.val = None
  armed.val = false
  assert_eq(calls.val, 2)
  assert_true(result is Err(Export(@local.MissingOutput)))
  assert_true(work.work.execution.material() is Some(_))
  assert_false(
    @strategy.captured_effect_inputs_match_run(inputs, work.work.captured),
  )
}

///|
test "Native submitted Values capture refuses expiry and cancellation after export preparation" {
  for cancel in [false, true] {
    let armed = Ref(false)
    let calls = Ref(0)
    let original : Ref[
      (NativeLocalHostConnection, NativeClientSubmittedEffectValuesWork)?,
    ] = Ref(None)
    let (host, work) = submitted_values_invocation_fixture(
      if cancel {
        "values-capture-cancelled"
      } else {
        "values-capture-expired"
      },
      utc=() => {
        if armed.val {
          calls.val += 1
          if calls.val == 2 {
            if cancel && original.val is Some((host, work)) {
              host.journal
              .transaction(() => {
                let row = host.journal
                  .retained(work.binding.request)
                  .unwrap()
                  .unwrap()
                host.journal
                .save({ ..row, cancellation_requested: true, })
                .map(_ => ())
              })
              .unwrap()
            }
            if !cancel {
              return "2026-10-11T00:00:00.000Z"
            }
          }
        }
        "2026-10-10T00:00:01.000Z"
      },
    )
    defer host.close() |> ignore
    defer work.close() |> ignore
    let inputs = work.pin_original_capture_inputs(1).unwrap()
    defer @strategy.release_captured_effect_inputs(inputs) |> ignore
    let index = submitted_values_capture_result(inputs)
    let (rows, limits) = submitted_values_capture_limits()
    original.val = Some((host, work))
    armed.val = true
    let result = work.prepare_original_result_export(
      inputs, index, rows, 100, 10000, limits,
    )
    original.val = None
    assert_eq(calls.val, 2)
    assert_true(
      if cancel {
        result is Err(Work(Work(Start(_))))
      } else {
        result is Err(Work(Work(OriginalRunNotCurrent)))
      },
    )
    assert_true(
      @strategy.captured_effect_inputs_match_run(inputs, work.work.captured),
    )
    @strategy.release_captured_effect_inputs(inputs) |> ignore
    assert_true(work.close())
    assert_eq(work.usage().held_bytes, 0L)
    host.close().unwrap()
  }
}
