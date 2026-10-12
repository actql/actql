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
            @model.model_provider_synchronous_invoke(provider).unwrap()(request)
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
fn physical_work_fixture(
  calls : Ref[Int],
  budget : Int,
  prepare : @model.ModelPhysicalPreflight,
) -> (@input.ClientInferInputExecution, @model.ModelExecution) raise {
  let (input, rows, _, fixed) = call_identity_fixture(fixture_prepared())
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Ok({
      value: @admitted.object_value([
        ("reason", @admitted.null_value()),
        ("risk", @admitted.text_value("high", 100).unwrap()),
      ]).unwrap(),
      provider_model: "fixture-risk-model",
      provider_request_id: "physical-work",
      input_tokens: 1L,
      output_tokens: 2L,
      observed_at: "2026-10-01T00:00:00.000Z",
    })
  }).unwrap()
  let limits = standard_limits().model
  let active = @model.start_model_execution(
    rows,
    provider,
    fixed,
    { ..limits, max_work: budget, },
    quantity_capacity=Some(fixture_quantity_capacity(33L, 500L)),
    physical_preflight=Some(prepare),
  ).unwrap()
  (input, active)
}

///|
test "physical byte work respects quantum and the independent exact Model budget" {
  // The existing one-row fixture uses 18 Model work: reserve 1, request 8,
  // dispatch 1 and response 8. This preflight adds start 1, byte validation 3,
  // plan completion 1 and the all-plans barrier 1, for exactly 24.
  let mut expected_total : Int64? = None
  for quantum in [1, 2, 256] {
    for budget in [24, 23, 11] {
      let calls = Ref(0)
      let bytes = Ref(0)
      let blocked = Ref(true)
      let (input, active) = physical_work_fixture(calls, budget, request => {
        Ok({
          advance: () => {
            if bytes.val < 3 {
              bytes.val += 1
              return Ok(None)
            }
            let result = @model.model_physical_request_plan(
              request,
              1000L,
              { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
              () => {
                calls.val += 1
                Ok({
                  value: @admitted.object_value([
                    ("reason", @admitted.null_value()),
                    ("risk", @admitted.text_value("high", 100).unwrap()),
                  ]).unwrap(),
                  provider_model: "fixture-risk-model",
                  provider_request_id: "physical-work",
                  input_tokens: 1L,
                  output_tokens: 2L,
                  observed_at: "2026-10-01T00:00:00.000Z",
                })
              },
            ).map(value => Some(value))
            result
          },
          cleanup: () => !blocked.val,
        })
      })
      let mut last = 0L
      let mut terminal = false
      for _ in 0..<2000 {
        let poll = @model.advance_model_execution(active, quantum).unwrap()
        let work = match poll {
          @model.Continue(_, work)
          | @model.Waiting(_, work)
          | @model.Settling(_, _, work)
          | @model.Completed(_, _, work)
          | @model.Failed(_, _, work)
          | @model.Stopped(_, _, work) => work
        }
        assert_true(work >= last && work - last <= quantum.to_int64())
        last = work
        if poll is @model.Continue(_, _) {
          continue
        }
        terminal = true
        if budget == 24 {
          assert_true(poll is @model.Completed(_, _, _))
          assert_eq(work, 24L)
          assert_eq(bytes.val, 3)
          assert_eq(calls.val, 1)
          match expected_total {
            None => expected_total = Some(work)
            Some(expected) => assert_eq(work, expected)
          }
        } else {
          assert_true(poll is @model.Failed(@model.WorkLimit, _, _))
          assert_eq(calls.val, if budget == 11 { 0 } else { 1 })
          assert_eq(bytes.val, if budget == 11 { 1 } else { 3 })
        }
        break
      }
      assert_true(terminal)
      let held = @model.model_execution_resource_usage(active)
      assert_false(@model.cleanup_model_execution(active).unwrap())
      assert_eq(@model.model_execution_resource_usage(active), held)
      blocked.val = false
      assert_true(@model.cleanup_model_execution(active).unwrap())
      assert_true(@model.cleanup_model_execution(active).unwrap())
      assert_eq(
        @model.model_execution_quantity_usage(active).reserved.tokens,
        0L,
      )
      assert_true(@input.cleanup_client_infer_input(input).unwrap())
    }
  }
}

///|
test "invalid physical work reports stop without dispatch and keep cleanup custody" {
  for reported in [0, -1, 2] {
    let calls = Ref(0)
    let blocked = Ref(true)
    let (input, active) = physical_work_fixture(calls, 100000, _ => {
      Ok(
        @node_fixture.client_program_model_content_request_preflight(
          _ => (Ok((false, None)), reported),
          () => !blocked.val,
        ),
      )
    })
    let mut terminal = false
    for _ in 0..<2000 {
      let poll = @model.advance_model_execution(active, 1).unwrap()
      if poll is @model.Continue(_, _) {
        continue
      }
      assert_true(poll is @model.Failed(@model.InvalidProvider, _, _))
      terminal = true
      break
    }
    assert_true(terminal)
    assert_eq(calls.val, 0)
    assert_false(@model.cleanup_model_execution(active).unwrap())
    blocked.val = false
    assert_true(@model.cleanup_model_execution(active).unwrap())
    assert_eq(@model.model_execution_quantity_usage(active).reserved.tokens, 0L)
    assert_true(@input.cleanup_client_infer_input(input).unwrap())
  }
}

///|
test "typed physical failure keeps consumed work through failed cleanup and retry" {
  let calls = Ref(0)
  let blocked = Ref(true)
  let (input, active) = physical_work_fixture(calls, 24, _ => {
    let steps = Ref(0)
    Ok({
      advance: () => {
        steps.val += 1
        if steps.val < 3 {
          return Ok(None)
        }
        Err(@model.Content(@model.ContentIdentity))
      },
      cleanup: () => !blocked.val,
    })
  })
  let mut terminal = false
  for _ in 0..<2000 {
    let poll = @model.advance_model_execution(active, 256).unwrap()
    if poll is @model.Continue(_, _) {
      continue
    }
    // Reserve 1 + request 8 + physical start 1 + failed validation 3.
    assert_true(
      poll is @model.Failed(@model.Content(@model.ContentIdentity), _, 13L),
    )
    terminal = true
    break
  }
  assert_true(terminal)
  assert_eq(calls.val, 0)
  let held = @model.model_execution_resource_usage(active)
  assert_false(@model.cleanup_model_execution(active).unwrap())
  assert_eq(@model.model_execution_resource_usage(active), held)
  blocked.val = false
  assert_true(@model.cleanup_model_execution(active).unwrap())
  assert_true(@model.cleanup_model_execution(active).unwrap())
  assert_eq(calls.val, 0)
  assert_eq(@model.model_execution_quantity_usage(active).reserved.tokens, 0L)
  assert_true(@input.cleanup_client_infer_input(input).unwrap())
}

///|
test "evaluation retains the invoked physical originals only while the adopted owner is live" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  guard active.source is Physical(provider) else { abort("physical fixture") }
  let sent : Array[String] = []
  bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L)).unwrap()
  bind_physical_preflight(active, request => {
    let rendered = "é\r\n" + request.slot.to_string()
    let context = "{\"provider_internals\":\"unknown\",\"selected\":[]}"
    Ok({
      advance: () => {
        @model.model_physical_request_plan(
          request,
          1000L,
          { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
          () => {
            sent.push(rendered)
            @model.model_provider_synchronous_invoke(provider).unwrap()(request)
          },
          evidence={ rendered_input: rendered, context_manifest: context, },
        ).map(value => Some(value))
      },
      cleanup: () => true,
    })
  }).unwrap()
  assert_true(evaluation_request(active, 0) is None)
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 2)
  for slot in 0..<2 {
    let (request, original) = evaluation_request(active, slot).unwrap()
    assert_eq(request.slot, slot)
    assert_eq(original.rendered_input, sent[slot])
    assert_eq(
      original.context_manifest,
      "{\"provider_internals\":\"unknown\",\"selected\":[]}",
    )
  }
  assert_true(evaluation_request(active, 2) is None)
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(evaluation_request(active, 0) is None)
  assert_eq(calls.val, 2)
}

///|
test "prepared physical originals can be retained without invoking or granting a call" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  guard active.source is Physical(provider) else { abort("physical fixture") }
  require_model_call_entry(active).unwrap()
  bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L)).unwrap()
  bind_physical_preflight(active, request => {
    Ok({
      advance: () => {
        @model.model_physical_request_plan(
          request,
          1000L,
          { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
          () => {
            @model.model_provider_synchronous_invoke(provider).unwrap()(request)
          },
          evidence={
            rendered_input: "é\r\n" + request.slot.to_string(),
            context_manifest: "{\"unknown\":true}",
          },
        ).map(value => Some(value))
      },
      cleanup: () => true,
    })
  }).unwrap()
  guard fixture_finish(active) is Waiting(work~) else {
    abort("prepared call set must wait before any send")
  }
  let prepared = prepared_call_set(active).unwrap()
  for slot in 0..<2 {
    let (request, original) = @model.prepared_model_physical_request(
      prepared, slot,
    ).unwrap()
    assert_eq(request.slot, slot)
    assert_eq(original.rendered_input, "é\r\n" + slot.to_string())
    assert_eq(original.context_manifest, "{\"unknown\":true}")
    assert_true(
      physical_equal(
        request,
        @model.prepared_model_request(prepared, slot).unwrap(),
      ),
    )
  }
  assert_eq(calls.val, 0)
  assert_true(@model.prepared_model_request(prepared, 2) is None)
  assert_true(@model.prepared_model_physical_request(prepared, 2) is None)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=work) is Stopped(_))
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(@model.prepared_model_request(prepared, 0) is None)
  assert_true(@model.prepared_model_physical_request(prepared, 0) is None)
  assert_eq(calls.val, 0)
}

///|
test "optional physical Evidence overflow stays missing without changing ordinary calls" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  guard active.source is Physical(provider) else { abort("physical fixture") }
  bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L)).unwrap()
  bind_physical_preflight(active, request => {
    Ok({
      advance: () => {
        @model.model_physical_request_plan(
          request,
          1L,
          { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
          () => {
            @model.model_provider_synchronous_invoke(provider).unwrap()(request)
          },
          evidence={ rendered_input: "é", context_manifest: "{}", },
        ).map(value => Some(value))
      },
      cleanup: () => true,
    })
  }).unwrap()
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 2)
  assert_true(evaluation_request(active, 0) is None)
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
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
test "typed Content preflight refusal preserves stop and pending physical cleanup" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  let blocked = Ref(true)
  let starts = Ref(0)
  bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L)).unwrap()
  bind_physical_preflight(active, _ => {
    starts.val += 1
    Ok({
      advance: () => Err(@model.Content(@model.ContentIdentity)),
      cleanup: () => !blocked.val,
    })
  }).unwrap()
  assert_true(
    fixture_finish(active)
    is Failed(Model(@model.Content(@model.ContentIdentity)), ..),
  )
  assert_true(execution_stopped(active))
  assert_true(acquire_output(active) is None)
  assert_eq(starts.val, 1)
  assert_eq(calls.val, 0)
  let before = execution_quantity_usage(active).unwrap().reserved.tokens
  assert_eq(before, 66L)
  assert_false(cleanup(active).unwrap())
  assert_eq(execution_quantity_usage(active).unwrap().reserved.tokens, before)
  blocked.val = false
  assert_true(cleanup(active).unwrap())
  assert_eq(execution_quantity_usage(active).unwrap().reserved.tokens, 0L)
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
