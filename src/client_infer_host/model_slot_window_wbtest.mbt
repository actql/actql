///|
// Original checked Program/Run/Entry handles. Physical I/O, Store ACK and byte
// allowances are existing deterministic fixtures, not normal public funding.
// The accepted M2 window must permit the second eligible original Slot to
// start while the first remains pending. This is not a JS transport fan-out.
test "two original async Slots enter before the first response settles" {
  let calls = Ref(0)
  let polls = Ref(0)
  let ready = Ref(false)
  let io_closed = Ref(false)
  let released = Ref(false)
  let cleanup_calls : Array[Bool] = []
  let (active, prefix, ledger, read) = original_io_consumer_fixture(
    calls,
    ready,
    io_closed,
    released,
    polls~,
    cleanup_calls~,
  )
  // Strengthen the old counter with the same original read Ledger and an
  // actual shared nominal admission. A plain fresh fixture Ledger is not a
  // substitute for the installed window's original resource connection.
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 2, 2).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  @model.bind_prepared_model_io_access(
    prepared_call_set(active).unwrap(),
    access,
  ).unwrap()
  // This preparation-only accessor must be read before the physical phase;
  // the original handle is not reissued from a later in-flight state.
  assert_eq(
    @model.prepared_model_call_count(prepared_call_set(active).unwrap()),
    Some(2),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("original first Slot must await its original response")
  }
  // Preparing/entering the next Slot is real bounded work. Permit that work,
  // rather than requiring every advance after the first wait to remain idle.
  // A pure I/O wait still cannot invent work. Neither response becomes ready.
  let mut last_work = work
  for _ in 0..<64 {
    match advance(active, 1).unwrap() {
      Continue(work=actual) => {
        assert_true(actual >= last_work && actual - last_work <= 1L)
        last_work = actual
      }
      AwaitIo(work=actual) => assert_eq(actual, last_work)
      _ => abort("neither original response is available for adoption")
    }
    if calls.val == 2 {
      break
    }
  }
  if calls.val == 2 {
    for _ in 0..<8 {
      async_assert_wait(active, last_work)
    }
  }
  let starts_before_first_response = calls.val
  assert_true(polls.val > 0)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((2, 2)),
  )
  // Drain the same original fixture before reporting the unmet window. These
  // doubles perform no network or persistence and retain no physical debt.
  ready.val = true
  io_closed.val = true
  released.val = true
  async_io_stop_and_cleanup(active)
  original_preparation_test_release(ledger, read)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  assert_true(@resources.close_model_io_access(access).unwrap())
  assert_eq(calls.val, starts_before_first_response)
  assert_eq(
    starts_before_first_response,
    2,
    msg="both eligible original Slots must start before either response completes",
  )
}

///|
fn window_fixed_response(
  slot : Int,
  profile? : @environment.ModelResponseProfile = async_response_profile(),
) -> @model.ModelPhysicalCallPoll {
  @model.PhysicalResponse({
    ..async_response_observation(None),
    observation: {
      ..async_response_observation(None).observation,
      response_profile_cid: Some(
        @environment.model_response_profile_identity(profile),
      ),
    },
    value: @admitted.object_value([
      ("reason", @admitted.text_value("slot-" + slot.to_string(), 100).unwrap()),
      ("risk", @admitted.text_value("high", 100).unwrap()),
    ]).unwrap(),
  })
}

///|
// Explicit bounded fixture contracts, not changed product/normal limits.
// Reverse source rows also test that original typed-key order is independent
// from input arrival and physical response order.
fn window_sized_start(calls : Ref[Int], count : Int) -> Execution {
  let keys = ["a", "b", "c", "d", "e"]
  let rows = Json::array(
    Array::makei(count, index => {
      Json::object({
        "id": Json::string(keys[count - index - 1]),
        "text": Json::string("hello"),
      })
    }),
  ).stringify()
  contract_capacity_start(
    calls,
    count,
    66536L * count.to_int64(),
    asynchronous=true,
    rows~,
    token_reservation=33L * count.to_int64(),
    duration_ms=500L * count.to_int64(),
    environment_wire=infer_fixture_environment
      .replace(old="\"max_items\":2", new="\"max_items\":" + count.to_string())
      .replace(
        old="sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560",
        new=window_sized_task_cid(count),
      ),
  )
}

///|
// Independently hashed canonical admission inputs (Node crypto), not expected
// answers derived from product execution. The old two-item Task is unchanged.
fn window_sized_task_cid(count : Int) -> String {
  match count {
    4 =>
      "sha256:dfc1d8b7853961a861cc0df3c3433b677d3286f10cd442607d0eb1f4e4def953"
    5 =>
      "sha256:65925b20faf5aac4098f5f4d8b53e32893042e8d00b1a0f762ff0659cb0919a5"
    _ => abort("this independent fixture selects four or five items only")
  }
}

///|
fn window_sized_profile(count : Int) -> @environment.ModelResponseProfile {
  let profile_cid = match count {
    4 =>
      "sha256:1bd10cad38cb5dad9463cc27bd6c8b0b05a5b54573870cecafaaf118f8859681"
    5 =>
      "sha256:7fe1f5ebd535252976de21af8e3249d94baad47ce3364fa9f017f684d9fad0ef"
    _ => abort("this independent fixture selects four or five items only")
  }
  async_response_profile(task_cid=window_sized_task_cid(count), profile_cid~)
}

///|
fn window_cleanup_complete(
  active : Execution,
  ledger : @resources.Ledger,
  read : @publication_host.ClientModelReadPreparation,
) -> Unit raise {
  let mut retired = false
  for _ in 0..<10 {
    if cleanup(active).unwrap() {
      retired = true
      break
    }
  }
  assert_true(retired)
  original_preparation_test_release(ledger, read)
}

///|
fn window_assert_output(
  completed : @relation.CompletedOutput,
  slot : Int,
  key : String,
) -> Unit raise {
  assert_true(
    @relation.completed_cell(completed, slot, 0) is Some(@relation.Text(actual)) &&
    actual == key,
  )
  assert_true(
    @relation.completed_cell(completed, slot, 1) is Some(@relation.Text("ok")),
  )
  guard @relation.completed_cell(completed, slot, 2)
    is Some(@relation.Captured(@admitted.Object(fields))) else {
    abort("original logical Slot must have its checked object")
  }
  let mut reason = None
  for index in 0..<@admitted.element_count(fields) {
    let (name, value) = @admitted.element_at(fields, index).unwrap()
    if name == "reason" && value is @admitted.Text(text) {
      reason = Some(text)
    }
  }
  assert_eq(reason, Some("slot-" + slot.to_string()))
}

///|
// Original Common/Entry/read owners; physical completions, byte grants and
// Store settlement are doubles. This is not an installed IO/Provider result.
test "original Model window reverse response keeps Slot settlement and logical output order" {
  let calls = Ref(0)
  let ready = [false, false]
  let (active, prefix, ledger, read) = original_io_consumer_fixture(
    calls,
    Ref(true),
    Ref(true),
    Ref(true),
    per_slot=Some(slot => {
      if ready[slot] {
        window_fixed_response(slot)
      } else {
        @model.PhysicalPending
      }
    }),
  )
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 2, 2).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  @model.bind_prepared_model_io_access(
    prepared_call_set(active).unwrap(),
    access,
  ).unwrap()
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("both original physical calls must wait")
  }
  assert_eq(calls.val, 2)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 2)),
  )
  for _ in 0..<8 {
    async_assert_wait(active, work)
  }
  ready[1] = true
  guard fixture_finish(active, initial_work=work)
    is Settling(1, work=second_work) else {
    abort("second response must settle without waiting for the first")
  }
  let second = call_settlement(active).unwrap()
  assert_eq(@model.model_call_settlement_slot(second), Some(1))
  assert_true(invocation_evidence(active, 0) is None)
  assert_true(invocation_evidence(active, 1) is Some(_))
  let wire = async_settlement_wire(active)
  assert_true(wire.contains("slot-1"))
  assert_false(wire.contains("slot-0"))
  guard fixture_finish(active, initial_work=second_work)
    is Settling(1, work=still_second) else {
    abort("unacknowledged second Slot retains its own settlement")
  }
  assert_eq(still_second, second_work)
  assert_true(@model.acknowledge_model_call_settlement(second))
  assert_false(@model.acknowledge_model_call_settlement(second))
  guard fixture_finish(active, initial_work=second_work)
    is AwaitIo(work=first_work) else {
    abort("first response remains pending after the second cleanup")
  }
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 1)),
  )
  ready[0] = true
  guard fixture_finish(active, initial_work=first_work)
    is Settling(0, work=last_work) else {
    abort("first response has its distinct original settlement")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  guard fixture_finish(active, initial_work=last_work)
    is Complete(completed, ..) else {
    abort("ordered logical projection must complete")
  }
  assert_eq(@relation.completed_row_count(completed), 2)
  window_assert_output(completed, 0, "a")
  window_assert_output(completed, 1, "b")
  assert_eq(capture(active).unwrap().captures.map(record => record.slot), [1, 0])
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  let verified = acquire_capture(active).unwrap()
  assert_eq(@model.verified_model_capture_outcome(verified, 0), Some("ok"))
  assert_eq(@model.verified_model_capture_outcome(verified, 1), Some("ok"))
  assert_false(cleanup(active).unwrap())
  assert_true(@model.release_verified_model_capture(verified))
  let mut retired = false
  for _ in 0..<10 {
    if cleanup(active).unwrap() {
      retired = true
      break
    }
  }
  assert_true(retired)
  original_preparation_test_release(ledger, read)
  assert_true(@resources.close_model_io_access(access).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "original Model window four calls preserve logical output in all 24 arrival orders" {
  let orders = [
    [0, 1, 2, 3],
    [0, 1, 3, 2],
    [0, 2, 1, 3],
    [0, 2, 3, 1],
    [0, 3, 1, 2],
    [0, 3, 2, 1],
    [1, 0, 2, 3],
    [1, 0, 3, 2],
    [1, 2, 0, 3],
    [1, 2, 3, 0],
    [1, 3, 0, 2],
    [1, 3, 2, 0],
    [2, 0, 1, 3],
    [2, 0, 3, 1],
    [2, 1, 0, 3],
    [2, 1, 3, 0],
    [2, 3, 0, 1],
    [2, 3, 1, 0],
    [3, 0, 1, 2],
    [3, 0, 2, 1],
    [3, 1, 0, 2],
    [3, 1, 2, 0],
    [3, 2, 0, 1],
    [3, 2, 1, 0],
  ]
  assert_eq(orders.length(), 24)
  let distinct : Map[String, Bool] = Map([])
  for order in orders {
    let code = order.map(value => value.to_string()).join("")
    assert_false(distinct.contains(code))
    distinct[code] = true
    let calls = Ref(0)
    let ready = [false, false, false, false]
    let profile = window_sized_profile(4)
    let (active, prefix, ledger, read) = original_io_consumer_fixture(
      calls,
      Ref(true),
      Ref(true),
      Ref(true),
      slots=4,
      capacity=fixture_quantity_capacity(132L, 2000L),
      profile~,
      start_original=Some(() => window_sized_start(calls, 4)),
      run_id="window-order-" + code,
      per_slot=Some(slot => {
        if ready[slot] {
          window_fixed_response(slot, profile~)
        } else {
          @model.PhysicalPending
        }
      }),
    )
    let installation = Ref(0)
    let admission = @resources.issue_model_io_admission(installation, 4, 4).unwrap()
    let access = @resources.issue_model_io_access(admission, installation).unwrap()
    @model.bind_prepared_model_io_access(
      prepared_call_set(active).unwrap(),
      access,
    ).unwrap()
    guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
      abort("four original calls must enter before any response arrives")
    }
    assert_eq(calls.val, 4)
    assert_eq(
      @resources.model_io_admission_counts(admission, installation),
      Some((0, 4)),
    )
    let mut previous_work = work
    let mut completed : @relation.CompletedOutput? = None
    for index in 0..<4 {
      let slot = order[index]
      ready[slot] = true
      guard fixture_finish(active, initial_work=previous_work)
        is Settling(actual, work=settling_work) else {
        abort("each fixed observation must retain its own Slot settlement")
      }
      assert_eq(actual, slot)
      let settlement = call_settlement(active).unwrap()
      assert_eq(@model.model_call_settlement_slot(settlement), Some(slot))
      let exported = async_settlement_wire(active)
      assert_true(exported.contains("slot-" + slot.to_string()))
      assert_true(@model.acknowledge_model_call_settlement(settlement))
      match fixture_finish(active, initial_work=settling_work) {
        AwaitIo(work=next_work) if index < 3 => {
          previous_work = next_work
          async_assert_wait(active, next_work)
        }
        Complete(output, work=next_work) if index == 3 => {
          completed = Some(output)
          previous_work = next_work
        }
        _ => abort("only the last original settlement completes this Model")
      }
      assert_eq(calls.val, 4)
      assert_eq(
        @resources.model_io_admission_counts(admission, installation),
        Some((0, 3 - index)),
      )
    }
    let completed = completed.unwrap()
    assert_eq(@relation.completed_row_count(completed), 4)
    for slot in 0..<4 {
      window_assert_output(completed, slot, ["a", "b", "c", "d"][slot])
    }
    assert_eq(
      capture(active).unwrap().captures.map(record => record.slot),
      order,
    )
    window_cleanup_complete(active, ledger, read)
    assert_true(@resources.close_model_io_access(access).unwrap())
    assert_eq(calls.val, 4)
  }
  assert_eq(distinct.length(), 24)
}

///|
test "original Model window Store backpressure blocks fifth start after IO close" {
  let calls = Ref(0)
  let ready = [false, false, false, false, false]
  let release = Ref(false)
  let profile = window_sized_profile(5)
  let (active, prefix, ledger, read) = original_io_consumer_fixture(
    calls,
    Ref(true),
    Ref(true),
    release,
    slots=5,
    capacity=fixture_quantity_capacity(165L, 2500L),
    profile~,
    start_original=Some(() => window_sized_start(calls, 5)),
    per_slot=Some(slot => {
      if ready[slot] {
        window_fixed_response(slot, profile~)
      } else {
        @model.PhysicalPending
      }
    }),
  )
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 4, 4).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  @model.bind_prepared_model_io_access(
    prepared_call_set(active).unwrap(),
    access,
  ).unwrap()
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("initial four calls must await, with the fifth unentered")
  }
  assert_eq(calls.val, 4)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 4)),
  )
  for _ in 0..<8 {
    async_assert_wait(active, work)
  }
  ready[0] = true
  guard fixture_finish(active, initial_work=work)
    is Settling(0, work=settling_work) else {
    abort("first response waits for its original Store settlement")
  }
  let first = call_settlement(active).unwrap()
  assert_eq(calls.val, 4)
  assert_true(@model.acknowledge_model_call_settlement(first))
  guard fixture_finish(active, initial_work=settling_work)
    is AwaitIo(work=blocked_work) else {
    abort("Store ACK cannot retire failed SDK cleanup or start a fifth call")
  }
  assert_eq(calls.val, 4)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 4)),
  )
  release.val = true
  guard fixture_finish(active, initial_work=blocked_work)
    is AwaitIo(work=last_work) else {
    abort("same original fifth call starts only after full holding retirement")
  }
  assert_eq(calls.val, 5)
  for slot in 1..<5 {
    ready[slot] = true
  }
  async_io_stop_and_cleanup(active)
  assert_eq(calls.val, 5)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  assert_true(last_work >= blocked_work)
  original_preparation_test_release(ledger, read)
  assert_true(@resources.close_model_io_access(access).unwrap())
}

///|
test "original Model window cancelled sparse outcomes retain logical Slot and sibling duties" {
  let calls = Ref(0)
  let ready = Ref(false)
  let cancelled = Ref(false)
  let release = Ref(true)
  let cleaned : Array[Bool] = []
  let profile = window_sized_profile(4)
  let (active, prefix, ledger, read) = original_io_consumer_fixture(
    calls,
    Ref(true),
    Ref(true),
    release,
    slots=4,
    capacity=fixture_quantity_capacity(132L, 2000L),
    profile~,
    cleanup_calls=cleaned,
    start_original=Some(() => window_sized_start(calls, 4)),
    per_slot=Some(slot => {
      if slot == 3 && ready.val {
        window_fixed_response(slot, profile~)
      } else if cancelled.val {
        @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, })
      } else {
        @model.PhysicalPending
      }
    }),
  )
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 4, 4).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  @model.bind_prepared_model_io_access(
    prepared_call_set(active).unwrap(),
    access,
  ).unwrap()
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("four original calls wait before sparse adoption")
  }
  assert_eq(calls.val, 4)
  ready.val = true
  guard fixture_finish(active, initial_work=work) is Settling(3, work=settled) else {
    abort("only original logical Slot three has a response")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  guard fixture_finish(active, initial_work=settled) is AwaitIo(work=waiting) else {
    abort("the other original calls remain pending")
  }
  release.val = false
  cancel(active) |> ignore
  cancelled.val = true
  assert_true(fixture_finish(active, initial_work=waiting) is Stopped(_))
  assert_true(acquire_output(active) is None)
  assert_true(acquire_capture(active) is None)
  let outcomes = acquire_outcomes(active).unwrap()
  assert_false(@model.model_outcomes_accepted(outcomes))
  assert_eq(@model.model_outcomes_count(outcomes), Some(1))
  assert_eq(@model.model_outcomes_slot_at(outcomes, 0), Some(3))
  assert_eq(@model.model_outcomes_slot_at(outcomes, -1), None)
  assert_eq(@model.model_outcomes_slot_at(outcomes, 1), None)
  assert_eq(@model.model_outcomes_outcome(outcomes, 3), Some("ok"))
  assert_eq(@model.model_outcomes_outcome(outcomes, 0), None)
  assert_true(@model.model_outcomes_invocation_evidence(outcomes, 3) is Some(_))
  assert_false(cleanup(active).unwrap())
  assert_true(@model.release_model_outcomes(outcomes))
  assert_eq(@model.model_outcomes_slot_at(outcomes, 0), None)
  let before = cleaned.length()
  assert_false(cleanup(active).unwrap())
  assert_eq(cleaned.length() - before, 3)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 3)),
  )
  release.val = true
  window_cleanup_complete(active, ledger, read)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  assert_true(@resources.close_model_io_access(access).unwrap())
  assert_eq(calls.val, 4)
}
