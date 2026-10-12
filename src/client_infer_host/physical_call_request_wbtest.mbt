///|
// Real ordinary Program, Entry and request owners. Only physical response and
// synchronous persistence observations are deterministic fixture callbacks.
fn original_request_call_fixture(
  calls : Ref[Int],
  copied : Bool,
  entries : Array[@model.ModelCallEntry],
  requests : Array[@model.ModelRequest],
  cleaned : Array[Bool],
) -> (Execution, Int64) raise {
  let (active, prepared, admission, work) = entry_gate_fixture(
    calls,
    Ref(evidence_account(@authorization.Allow)),
    Ref("2026-10-02T00:00:00.000Z"),
    Ref(Some(egress_fixture_observation())),
    asynchronous=true,
    configure=active => {
      bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L)).unwrap()
      bind_physical_preflight(active, request => {
        Ok({
          advance: () => {
            @model.model_async_physical_request_plan(
              request,
              1000L,
              { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
              async_response_profile(),
              async_response_installation(),
              entry => {
                entries.push(entry)
                requests.push(request)
                let selected = if copied {
                  { ..request, slot_cid: request.slot_cid, }
                } else {
                  request
                }
                let call = @model.model_physical_call_for_request(
                  entry,
                  selected,
                  () => {
                    @model.PhysicalResponse(async_response_observation(None))
                  },
                  () => (),
                  acknowledged => {
                    cleaned.push(acknowledged)
                    true
                  },
                )
                if call is Some(_) {
                  calls.val += 1
                }
                call
              },
            ).map(value => Some(value))
          },
          cleanup: () => true,
        })
      }).unwrap()
    },
  )
  bind_model_dispatch(active, prepared, admission, _ => true).unwrap()
  (active, work)
}

///|
test "physical call original request needs no adapter prepared-call-set binding" {
  let calls = Ref(0)
  let entries : Array[@model.ModelCallEntry] = []
  let requests : Array[@model.ModelRequest] = []
  let cleaned : Array[Bool] = []
  let (active, prefix) = original_request_call_fixture(
    calls, false, entries, requests, cleaned,
  )
  let mut work = prefix
  for slot in 0..<2 {
    guard fixture_finish(active, initial_work=work)
      is Settling(actual, work=next) else {
      abort("original request response must settle")
    }
    assert_eq(actual, slot)
    work = next
    assert_eq(calls.val, slot + 1)
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
  }
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  assert_eq(calls.val, 2)
  assert_eq(cleaned, [true, true])
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  for slot in 0..<2 {
    assert_true(
      @model.model_physical_call_for_request(
        entries[slot],
        requests[slot],
        () => @model.PhysicalPending,
        () => (),
        _ => true,
      )
      is None,
    )
  }
  assert_eq(calls.val, 2)
}

///|
test "physical call copied original request cannot register custody or dispatch" {
  let calls = Ref(0)
  let entries : Array[@model.ModelCallEntry] = []
  let requests : Array[@model.ModelRequest] = []
  let cleaned : Array[Bool] = []
  let (active, prefix) = original_request_call_fixture(
    calls, true, entries, requests, cleaned,
  )
  assert_true(
    fixture_finish(active, initial_work=prefix)
    is Failed(Model(@model.CallEntryRefused), ..),
  )
  assert_eq(calls.val, 0)
  assert_eq(entries.length(), 1)
  assert_eq(cleaned, [])
  assert_true(acquire_output(active) is None)
  assert_eq(@model.stopped_model_attempt_count(active.model.unwrap()), Some(1))
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}
