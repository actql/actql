///|
fn contract_capacity_start(
  calls : Ref[Int],
  attempts : Int,
  wire_bytes : Int64,
  limits? : Limits = standard_limits(),
) -> Execution {
  let source = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  let prepared = fixture_prepared(source~)
  let plan = call_identity_plan(prepared, attempts~, wire_bytes~)
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Ok({
      value: @admitted.object_value([
        ("reason", @admitted.null_value()),
        ("risk", @admitted.text_value("high", 100).unwrap()),
      ]).unwrap(),
      provider_model: "fixture",
      provider_request_id: "request-" + calls.val.to_string(),
      input_tokens: 1L,
      output_tokens: 2L,
      observed_at: "2026-10-02T00:00:00.000Z",
    })
  }).unwrap()
  start(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    plan=Some(plan),
  ).unwrap()
}

///|
test "selected model contract enforces exact and one-short physical capacities" {
  let calls = Ref(0)
  // Two requests require two attempts and two 1000 + 65536 wire envelopes.
  let exact = contract_capacity_start(calls, 2, 133072L)
  assert_true(fixture_finish(exact) is Complete(_, ..))
  assert_eq(calls.val, 2)
  let exact_model = exact.model.unwrap()
  assert_eq(
    @model.model_execution_resource_usage(exact_model).uncertain_transfer_bytes,
    133072L,
  )
  assert_true(cleanup(exact).unwrap())
  for
    (attempts, wire, issue) in [
      (1, 133072L, @resources.AttemptLimit),
      (2, 133071L, @resources.TransferLimit),
    ] {
    let calls = Ref(0)
    let active = contract_capacity_start(calls, attempts, wire)
    guard fixture_finish(active) is Failed(Model(@model.Ledger(actual)), ..) else {
      abort("the selected contract must reject before physical dispatch")
    }
    assert_eq(actual, issue)
    assert_eq(calls.val, 0)
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    let model = active.model.unwrap()
    let before = @model.model_execution_resource_usage(model)
    assert_eq(before.attempts, 1)
    assert_eq(before.reserved_transfer_bytes, 66536L)
    assert_eq(before.uncertain_transfer_bytes, 0L)
    assert_true(cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    let after = @model.model_execution_resource_usage(model)
    assert_eq(after.reserved_transfer_bytes, 0L)
    assert_eq(after.reserved_retention_bytes, 0L)
    assert_eq(after.reserved_execution_bytes, 0L)
    assert_eq(after.uncertain_transfer_bytes, 0L)
    assert_eq(calls.val, 0)
  }
}

///|
test "selected model contract cannot widen a smaller installed physical budget" {
  let base = standard_limits()
  for
    (ledger, issue) in [
      ({ ..base.model.ledger, attempts: 1, }, @resources.AttemptLimit),
      (
        { ..base.model.ledger, transfer_bytes: 133071L, },
        @resources.TransferLimit,
      ),
    ] {
    let calls = Ref(0)
    let active = contract_capacity_start(calls, 4, 133072L, limits={
      ..base,
      model: { ..base.model, ledger, },
    })
    guard fixture_finish(active) is Failed(Model(@model.Ledger(actual)), ..) else {
      abort("installed capacity remains an independent ceiling")
    }
    assert_eq(actual, issue)
    assert_eq(calls.val, 0)
    assert_true(cleanup(active).unwrap())
  }
}
