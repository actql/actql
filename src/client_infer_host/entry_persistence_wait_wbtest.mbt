///|
// All original handles come from ordinary checked Program/input preparation.
// These deterministic polls are not real Store ACK or asynchronous I/O proof.
test "pending entry keeps original work and resumes each saved attempt once" {
  let total_work : Ref[Int64?] = Ref(None)
  for quantum in [1, 7] {
    let calls = Ref(0)
    let current = Ref(evidence_account(@authorization.Allow))
    let now = Ref("2026-10-02T00:00:00.000Z")
    let egress = Ref(Some(egress_fixture_observation()))
    let (active, prepared, admission, prefix_work) = entry_gate_fixture(
      calls, current, now, egress,
    )
    let ready = Ref(false)
    let begins = Ref(0)
    let polls = Ref(0)
    let entries : Array[@model.ModelCallEntry] = []
    let views : Array[@model.ModelCallEntryPersistence] = []
    bind_model_entry_persistence(active, prepared, admission, entry => {
      begins.val += 1
      entries.push(entry)
      let view = @model.model_call_entry_persistence(entry, prepared, () => {
        polls.val += 1
        if ready.val {
          @model.Saved(
            @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
          )
        } else {
          @model.Pending
        }
      }).unwrap()
      views.push(view)
      Some(view)
    }).unwrap()
    let mut work = prefix_work
    for slot in 0..<2 {
      ready.val = false
      work = match fixture_finish(active, initial_work=work) {
        AwaitIo(work~) => work
        _ => abort("original entry must suspend before provider I/O")
      }
      assert_eq(calls.val, slot)
      assert_eq(begins.val, slot + 1)
      let before = @model.model_execution_resource_usage(active.model.unwrap())
      for _ in 0..<3 {
        guard advance(active, quantum).unwrap() is AwaitIo(work=observed) else {
          abort("pending poll cannot advance a bounded token")
        }
        assert_eq(observed, work)
        assert_eq(calls.val, slot)
        assert_true(!cleanup(active).unwrap())
        let after = @model.model_execution_resource_usage(active.model.unwrap())
        assert_eq(after.reserved_transfer_bytes, before.reserved_transfer_bytes)
        assert_eq(
          after.uncertain_transfer_bytes,
          before.uncertain_transfer_bytes,
        )
        assert_eq(
          after.reserved_retention_bytes,
          before.reserved_retention_bytes,
        )
        assert_eq(
          after.reserved_execution_bytes,
          before.reserved_execution_bytes,
        )
      }
      ready.val = true
      work = match fixture_finish(active, initial_work=work) {
        Settling(actual, work~) => {
          assert_eq(actual, slot)
          work
        }
        _ => abort("one original saved attempt must settle")
      }
      assert_eq(calls.val, slot + 1)
      assert_true(
        @model.acknowledge_model_call_settlement(
          call_settlement(active).unwrap(),
        ),
      )
    }
    guard fixture_finish(active, initial_work=work)
      is Complete(_, work=final_work) else {
      abort("saved original attempts must complete normally")
    }
    if total_work.val is Some(original) {
      assert_eq(final_work, original)
    } else {
      total_work.val = Some(final_work)
    }
    assert_eq(begins.val, 2)
    assert_eq(polls.val, 10)
    for index in 0..<2 {
      assert_true(
        @model.poll_model_call_entry_persistence(
          views[index],
          entries[index],
          prepared,
        )
        is Err(@model.CallEntryRefused),
      )
    }
    let model = active.model.unwrap()
    assert_true(cleanup(active).unwrap())
    let released = @model.model_execution_resource_usage(model)
    assert_eq(released.reserved_transfer_bytes, 0L)
    assert_eq(released.reserved_retention_bytes, 0L)
    assert_eq(released.reserved_execution_bytes, 0L)
    assert_eq(calls.val, 2)
    assert_eq(polls.val, 10)
  }
}

///|
test "pending save drains after stop changes without granting transport" {
  for
    variant in ["cancel", "authority", "egress", "expiry", "absent", "unknown"] {
    let calls = Ref(0)
    let current = Ref(evidence_account(@authorization.Allow))
    let now = Ref("2026-10-02T00:00:00.000Z")
    let egress = Ref(Some(egress_fixture_observation()))
    let (active, prepared, admission, prefix_work) = entry_gate_fixture(
      calls, current, now, egress,
    )
    let ready = Ref(false)
    let begins = Ref(0)
    bind_model_entry_persistence(active, prepared, admission, entry => {
      begins.val += 1
      @model.model_call_entry_persistence(entry, prepared, () => {
        if !ready.val {
          @model.Pending
        } else {
          match variant {
            "absent" => @model.NotRecorded
            "unknown" => @model.Unknown
            _ =>
              @model.Saved(
                @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
              )
          }
        }
      })
    }).unwrap()
    let work = match fixture_finish(active, initial_work=prefix_work) {
      AwaitIo(work~) => work
      _ => abort("pending persistence required")
    }
    match variant {
      "cancel" => assert_true(cancel(active))
      "authority" => current.val = evidence_account(@authorization.Deny)
      "egress" =>
        egress.val = Some({
          ..egress_fixture_observation(),
          region: "changed-region",
        })
      "expiry" => now.val = "2100-01-01T00:00:00.000Z"
      _ => ()
    }
    guard advance(active, 7).unwrap() is AwaitIo(work=observed) else {
      abort("pending observation remains held after current changes")
    }
    assert_eq(observed, work)
    assert_true(!cleanup(active).unwrap())
    ready.val = true
    let result = fixture_finish(active, initial_work=work)
    match variant {
      "cancel" => assert_true(result is Stopped(_))
      "authority" | "expiry" =>
        assert_true(result is Failed(Model(@model.Authorization(_)), ..))
      "egress" => assert_true(result is Failed(Model(@model.Egress(_)), ..))
      "absent" =>
        assert_true(result is Failed(Model(@model.CallEntryRefused), ..))
      _ => assert_true(result is Failed(Model(@model.UnknownCalls), ..))
    }
    assert_eq(calls.val, 0)
    assert_eq(begins.val, 1)
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    let model = active.model.unwrap()
    assert_eq(
      @model.stopped_model_attempt_count(model),
      Some(if variant == "absent" { 0 } else { 1 }),
    )
    if variant == "unknown" {
      let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
      assert_true(
        @publication.run_evidence_value_json(
          @model.model_attempt_outcome(proof),
        ).contains("\"category\":\"result_unknown\""),
      )
    }
    assert_true(cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 0)
  }
}

///|
test "persistence poll cannot reenter the original bounded execution" {
  let calls = Ref(0)
  let current = Ref(evidence_account(@authorization.Allow))
  let now = Ref("2026-10-02T00:00:00.000Z")
  let egress = Ref(Some(egress_fixture_observation()))
  let (active, prepared, admission, prefix_work) = entry_gate_fixture(
    calls, current, now, egress,
  )
  let refused = Ref(false)
  bind_model_entry_persistence(active, prepared, admission, entry => {
    @model.model_call_entry_persistence(entry, prepared, () => {
      let model = active.model.unwrap()
      refused.val = @model.advance_model_execution(model, 1)
        is Err(@model.Session(@bounded.ConcurrentResume)) &&
        @model.cleanup_model_execution(model)
        is Err(@model.Session(@bounded.ConcurrentResume)) &&
        advance(active, 1) is Err(InvalidAdvance)
      @model.Unknown
    })
  }).unwrap()
  assert_true(
    fixture_finish(active, initial_work=prefix_work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  assert_true(refused.val)
  assert_eq(calls.val, 0)
  assert_true(cleanup(active).unwrap())
}

///|
test "malformed returned handle cannot drop a known pending save" {
  let calls = Ref(0)
  let current = Ref(evidence_account(@authorization.Allow))
  let now = Ref("2026-10-02T00:00:00.000Z")
  let egress = Ref(Some(egress_fixture_observation()))
  let (active, prepared, admission, prefix_work) = entry_gate_fixture(
    calls, current, now, egress,
  )
  let ready = Ref(false)
  let begins = Ref(0)
  bind_model_entry_persistence(active, prepared, admission, entry => {
    begins.val += 1
    @model.model_call_entry_persistence(entry, prepared, () => {
      if ready.val {
        @model.Saved(
          @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
        )
      } else {
        @model.Pending
      }
    })
    |> ignore
    // Deliberately violate the adapter return contract after starting a save.
    None
  }).unwrap()
  let work = match fixture_finish(active, initial_work=prefix_work) {
    AwaitIo(work~) => work
    _ => abort("known save responsibility must remain held")
  }
  assert_true(!cleanup(active).unwrap())
  assert_eq(calls.val, 0)
  ready.val = true
  assert_true(
    fixture_finish(active, initial_work=work)
    is Failed(Model(@model.CallEntryRefused), ..),
  )
  assert_eq(begins.val, 1)
  assert_eq(calls.val, 0)
  assert_eq(@model.stopped_model_attempt_count(active.model.unwrap()), Some(1))
  assert_true(acquire_output(active) is None)
  assert_true(cleanup(active).unwrap())
}
