///|
fn physical_preflight_fixture(
  active : Execution,
  events : Array[String],
  fail_slot? : Int = -1,
  foreign? : Bool = false,
  wire_bytes? : Int64 = 1000L,
  tokens? : Int64 = 33L,
  cleanup_blocked? : Ref[Bool] = Ref(false),
) -> Unit {
  guard active.source is Physical(provider) else { abort("physical fixture") }
  bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L)).unwrap()
  bind_physical_preflight(active, request => {
    events.push("start:" + request.slot.to_string())
    let steps = Ref(0)
    Ok({
      advance: () => {
        events.push("prepare:" + request.slot.to_string())
        steps.val += 1
        if steps.val < 3 {
          return Ok(None)
        }
        if request.slot == fail_slot {
          return Err(@model.InvalidProvider)
        }
        let bound = if foreign {
          { ..request, slot: request.slot + 1, }
        } else {
          request
        }
        @model.model_physical_request_plan(
          bound,
          wire_bytes,
          { tokens, cost_units: 0L, duration_ms: 500L, },
          () => {
            events.push("invoke:" + request.slot.to_string())
            (provider.invoke)(request)
          },
        ).map(value => Some(value))
      },
      cleanup: () => {
        events.push("cleanup:" + request.slot.to_string())
        !cleanup_blocked.val
      },
    })
  }).unwrap()
}

///|
test "all exact physical plans precede the first model dispatch" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let events = []
  physical_preflight_fixture(active, events)
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 2)
  assert_eq(events, [
    "start:0", "prepare:0", "prepare:0", "prepare:0", "start:1", "prepare:1", "prepare:1",
    "prepare:1", "invoke:0", "invoke:1",
  ])
  // Cleanup advances one retained physical cursor, not another Compute.
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 2)
  assert_eq(events[10], "cleanup:0")
  assert_eq(events[11], "cleanup:1")
  assert_true(cleanup(active).unwrap())
  assert_eq(events.length(), 12)
}

///|
test "a later physical preflight refusal dispatches no earlier slot" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let events = []
  physical_preflight_fixture(active, events, fail_slot=1)
  assert_true(
    fixture_finish(active) is Failed(Model(@model.InvalidProvider), ..),
  )
  assert_eq(calls.val, 0)
  assert_true(acquire_output(active) is None)
  let model = active.model.unwrap()
  assert_eq(@model.model_execution_quantity_usage(model).reserved.tokens, 66L)
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.model_execution_quantity_usage(model).reserved.tokens, 0L)
  assert_eq(@model.model_execution_quantity_usage(model).uncertain.tokens, 0L)
  assert_eq(calls.val, 0)
}

///|
test "physical plans reject foreign requests and one-short envelopes" {
  for
    (foreign, bytes, tokens, expected) in [
      (true, 1000L, 33L, @model.RequestIdentity),
      (false, 1001L, 33L, @model.RequestLimit),
      (false, 1000L, 34L, @model.Ledger(@resources.TokenLimit)),
      (false, 1000L, 31L, @model.InvalidLimits),
    ] {
    let calls = Ref(0)
    let active = contract_capacity_start(calls, 2, 133072L)
    let events = []
    physical_preflight_fixture(
      active,
      events,
      foreign~,
      wire_bytes=bytes,
      tokens~,
    )
    guard fixture_finish(active) is Failed(Model(issue), ..) else {
      abort("physical request admission must fail before dispatch")
    }
    assert_eq(issue, expected)
    assert_eq(calls.val, 0)
    assert_true(acquire_output(active) is None)
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 0)
  }
}

///|
test "physical preflight cancellation retains failed cleanup without redispatch" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let events = []
  let blocked = Ref(true)
  physical_preflight_fixture(active, events, cleanup_blocked=blocked)
  let mut observed = false
  for _ in 0..<2000 {
    assert_true(advance(active, 1).unwrap() is Continue(_))
    if events.length() == 2 {
      observed = true
      break
    }
  }
  assert_true(observed)
  assert_true(cancel(active))
  assert_true(advance(active, 1).unwrap() is Stopped(_))
  assert_true(execution_stopped(active))
  assert_eq(calls.val, 0)
  assert_true(acquire_output(active) is None)
  let model = active.model.unwrap()
  let before = @model.model_execution_resource_usage(model)
  assert_true(!cleanup(active).unwrap())
  assert_eq(@model.model_execution_resource_usage(model), before)
  assert_eq(events, ["start:0", "prepare:0", "cleanup:0"])
  blocked.val = false
  assert_true(cleanup(active).unwrap())
  assert_eq(events, ["start:0", "prepare:0", "cleanup:0", "cleanup:0"])
  let after = @model.model_execution_resource_usage(model)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.reserved_transfer_bytes, 0L)
  assert_eq(@model.model_execution_quantity_usage(model).reserved.tokens, 0L)
  assert_eq(calls.val, 0)
}

///|
test "physical preflight reserves buffer and metadata before creating cursors" {
  // Independent envelope: two 256-byte metadata owners, separate from the
  // existing two (1000 request + 65536 response) retained buffer envelopes.
  for (workspace, allowed) in [(512L, true), (511L, false)] {
    let calls = Ref(0)
    let base = standard_limits()
    let active = contract_capacity_start(calls, 2, 133072L, limits={
      ..base,
      model: {
        ..base.model,
        ledger: { ..base.model.ledger, execution_bytes: workspace, },
      },
    })
    let events = []
    physical_preflight_fixture(active, events)
    let result = fixture_finish(active)
    if allowed {
      assert_true(result is Complete(_, ..))
      assert_eq(calls.val, 2)
      assert_true(!cleanup(active).unwrap())
    } else {
      assert_true(
        result is Failed(Model(@model.Ledger(@resources.ExecutionLimit)), ..),
      )
      assert_eq(calls.val, 0)
      assert_eq(events.length(), 0)
    }
    assert_true(cleanup(active).unwrap())
    assert_eq(execution_quantity_usage(active).unwrap().reserved.tokens, 0L)
  }
}
