///|
// Ordinary Program preparation issues the original Entry and all authority.
// The polling variant is a deterministic ACK double, not real Store I/O.
test "physical diagnostic callback cannot reuse a pre-callback send permission" {
  for polling in [false, true] {
    for variant in ["cancel", "revoke", "egress", "expiry", "original-current"] {
      let calls = Ref(0)
      let current = Ref(evidence_account(@authorization.Allow))
      let now = Ref("2026-10-02T00:00:00.000Z")
      let egress = Ref(Some(egress_fixture_observation()))
      let (active, prepared, admission, prefix_work) = entry_gate_fixture(
        calls, current, now, egress,
      )
      let events : Array[String] = []
      let original_current = Ref(true)
      assert_true(
        @model.bind_prepared_model_observation(prepared, observation => {
          let (_, _, event, _) = @model.model_physical_observation_facts(
            observation,
          )
          events.push(event)
          if events.length() == 1 {
            match variant {
              "cancel" => cancel(active) |> ignore
              "revoke" => current.val = evidence_account(@authorization.Deny)
              "egress" =>
                egress.val = Some({
                  ..egress_fixture_observation(),
                  region: "changed-region",
                })
              "expiry" => now.val = "2100-01-01T00:00:00.000Z"
              "original-current" =>
                // Installed original current predicate after diagnostics
                // requests this SAME Owner's existing stop. Host graceful
                // closing itself is not this current-loss observation.
                original_current.val = false
              _ => abort("fixed mutation")
            }
          }
          if !original_current.val {
            cancel(active) |> ignore
          }
        }),
      )
      let entries = Ref(0)
      if polling {
        bind_model_entry_persistence(active, prepared, admission, entry => {
          entries.val += 1
          @model.model_call_entry_persistence(entry, prepared, () => {
            @model.Saved(
              @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
            )
          })
        }).unwrap()
      } else {
        bind_model_dispatch(active, prepared, admission, _ => {
          entries.val += 1
          true
        }).unwrap()
      }
      let mut result = fixture_finish(active, initial_work=prefix_work)
      for _ in 0..<4 {
        if result is AwaitIo(work~) {
          result = fixture_finish(active, initial_work=work)
        }
      }
      assert_eq(calls.val, 0)
      assert_eq(entries.val, 1)
      assert_eq(events, ["before_invoke"])
      match variant {
        "cancel" | "original-current" => assert_true(result is Stopped(_))
        "egress" => assert_true(result is Failed(Model(@model.Egress(_)), ..))
        _ => assert_true(result is Failed(Model(@model.Authorization(_)), ..))
      }
      assert_true(acquire_output(active) is None)
      assert_true(acquire_capture(active) is None)
      let model = active.model.unwrap()
      assert_eq(@model.stopped_model_attempt_count(model), Some(1))
      assert_true(cleanup(active).unwrap())
      assert_true(cleanup(active).unwrap())
      assert_eq(calls.val, 0)
    }
  }
}

///|
test "final gate starts original fixed invocation once and retains unknown entry on refusal" {
  for polling in [false, true] {
    let calls = Ref(0)
    let current = Ref(evidence_account(@authorization.Allow))
    let now = Ref("2026-10-02T00:00:00.000Z")
    let egress = Ref(Some(egress_fixture_observation()))
    let (active, prepared, admission, prefix_work) = entry_gate_fixture(
      calls, current, now, egress,
    )
    let events : Array[String] = []
    let handles : Array[@model.ModelCallEntry] = []
    let actual_entry_counts : Array[(Int, Int)] = []
    assert_true(
      @model.bind_prepared_model_observation(prepared, observation => {
        let (_, _, event, _) = @model.model_physical_observation_facts(
          observation,
        )
        events.push(event)
        if event == "before_invoke" {
          actual_entry_counts.push((calls.val, handles.length() - 1))
        } else {
          actual_entry_counts.push((calls.val, handles.length()))
        }
      }),
    )
    if polling {
      bind_model_entry_persistence(active, prepared, admission, entry => {
        handles.push(entry)
        @model.model_call_entry_persistence(entry, prepared, () => {
          @model.Saved(
            @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
          )
        })
      }).unwrap()
    } else {
      bind_model_dispatch(active, prepared, admission, entry => {
        handles.push(entry)
        true
      }).unwrap()
    }
    let mut work = prefix_work
    for slot in 0..<2 {
      let mut result = fixture_finish(active, initial_work=work)
      for _ in 0..<4 {
        if result is AwaitIo(work~) {
          result = fixture_finish(active, initial_work=work)
        }
      }
      guard result is Settling(actual, work=observed) else {
        abort("original call must settle without re-entry")
      }
      assert_eq(actual, slot)
      work = observed
      assert_eq(calls.val, slot + 1)
      // The original consumed entry cannot issue another acknowledgement or
      // reconstruct a fresh gate, even before the owner is reclaimed.
      assert_true(
        @model.acknowledge_model_call_entry(handles[slot], prepared) is None,
      )
      for _ in 0..<3 {
        assert_true(advance(active, 1).unwrap() is Settling(_, ..))
        assert_eq(calls.val, slot + 1)
      }
      assert_true(
        @model.acknowledge_model_call_settlement(
          call_settlement(active).unwrap(),
        ),
      )
    }
    assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
    assert_eq(events, [
      "before_invoke", "started", "returned", "before_invoke", "started", "returned",
    ])
    for (actual, expected) in actual_entry_counts {
      assert_eq(actual, expected)
    }
    assert_true(cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 2)
  }
}
