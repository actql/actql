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
fn window_fixed_response(slot : Int) -> @model.ModelPhysicalCallPoll {
  @model.PhysicalResponse({
    ..async_response_observation(None),
    value: @admitted.object_value([
      ("reason", @admitted.text_value("slot-" + slot.to_string(), 100).unwrap()),
      ("risk", @admitted.text_value("high", 100).unwrap()),
    ]).unwrap(),
  })
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
