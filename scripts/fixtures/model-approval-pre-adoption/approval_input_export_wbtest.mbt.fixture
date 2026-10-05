///|
test "approval input export preserves exact values and the original prepared receipt" {
  let calls = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    rows="[{\"id\":\"a\",\"text\":\"e\\u0301\\r\\n\"}]",
    defer_dispatch=true,
    enter_call=Some(_ => true),
  )
  invocation_fixture_compiled(active) |> ignore
  assert_true(prepare_model_approval_input_export(active, 16384) is Err(_))
  let mut ready = false
  for _ in 0..<2000 {
    let poll = advance(active, 1).unwrap()
    if poll is Waiting(_) {
      ready = true
      break
    }
    assert_true(poll is Continue(_))
  }
  assert_true(ready)
  let set = prepared_model_call_set(active).unwrap()
  let original = @model.prepared_model_call_set_input_receipt(set).unwrap()
  let input = @input.client_infer_completed_input(active.input).unwrap()
  let exporter = prepare_model_approval_input_export(active, 16384).unwrap()
  let mut wire = ""
  while @relation.next_completed_output_export(exporter).unwrap() is Some(row) {
    wire += row
  }
  let (receipt, suffix) = @relation.finish_completed_relation_export(exporter).unwrap()
  wire += suffix
  // Independent submitted bytes: preserve decomposed Unicode and CR/LF.
  assert_true(wire.contains("e\u{0301}\\r\\n"))
  assert_true(!wire.contains("é"))
  assert_eq(
    @relation.logical_relation_cid(
      @relation.completed_relation_export_identity(receipt),
    ),
    @relation.logical_relation_cid(
      @relation.completed_relation_export_identity(original),
    ),
  )
  assert_true(
    @relation.completed_relation_export_matches_output(original, input),
  )
  @relation.cancel_completed_relation_export_receipt(receipt)
  assert_true(
    @relation.completed_relation_export_matches_output(original, input),
  )
  assert_true(prepared_model_call_set(active) is Some(_))
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  for _ in 0..<2000 {
    if advance(active, 1).unwrap() is Stopped(_) {
      break
    }
  }
  assert_true(prepare_model_approval_input_export(active, 16384) is Err(_))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}

///|
test "cancelled approval export cannot consume the prepared call input" {
  let calls = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    defer_dispatch=true,
    enter_call=Some(_ => true),
  )
  invocation_fixture_compiled(active) |> ignore
  let mut ready = false
  for _ in 0..<2000 {
    if advance(active, 1).unwrap() is Waiting(_) {
      ready = true
      break
    }
  }
  assert_true(ready)
  let set = prepared_model_call_set(active).unwrap()
  let original = @model.prepared_model_call_set_input_receipt(set).unwrap()
  let input = @input.client_infer_completed_input(active.input).unwrap()
  let exporter = prepare_model_approval_input_export(active, 1).unwrap()
  // A small physical batch cannot widen the owner's original value bounds.
  assert_true(@relation.next_completed_output_export(exporter) is Err(_))
  @relation.cancel_completed_output_export(exporter)
  assert_true(
    @relation.completed_relation_export_matches_output(original, input),
  )
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  for _ in 0..<2000 {
    if advance(active, 1).unwrap() is Stopped(_) {
      break
    }
  }
  assert_true(cleanup(active).unwrap())
}
