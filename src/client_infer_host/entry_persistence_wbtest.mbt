///|
test "saved entry acknowledgement is a late observation not current permission" {
  for variant in ["cancel", "authority", "egress", "expiry"] {
    let calls = Ref(0)
    let current = Ref(evidence_account(@authorization.Allow))
    let now = Ref("2026-10-02T00:00:00.000Z")
    let egress = Ref(Some(egress_fixture_observation()))
    let (active, prepared, admission, prefix_work) = entry_gate_fixture(
      calls, current, now, egress,
    )
    let saved : Array[@model.ModelCallEntryAcknowledgement] = []
    let originals : Array[@model.ModelCallEntry] = []
    let checks : Array[Bool] = []
    bind_model_dispatch(active, prepared, admission, entry => {
      // The fixture retains the journal's original entry before delivery of
      // a concurrent stop/change. This is not a durable Store acceptance test.
      originals.push(entry)
      checks.push(@model.model_call_entry_originals(entry) is Some(_))
      match variant {
        "cancel" => cancel(active) |> ignore
        "authority" => current.val = evidence_account(@authorization.Deny)
        "egress" =>
          egress.val = Some({
            ..egress_fixture_observation(),
            region: "changed-region",
          })
        _ => now.val = "2100-01-01T00:00:00.000Z"
      }
      // The historical immediate-current API keeps its original refusal.
      checks.push(@model.acknowledge_model_call_entry(entry, prepared) is None)
      let acknowledgement = @model.acknowledge_saved_model_call_entry(
        entry, prepared,
      ).unwrap()
      checks.push(
        physical_equal(
          acknowledgement,
          @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
        ),
      )
      checks.push(
        !@model.model_call_entry_acknowledgement_current(
          acknowledgement, prepared,
        ),
      )
      saved.push(acknowledgement)
      true
    }).unwrap()
    let result = fixture_finish(active, initial_work=prefix_work)
    match variant {
      "cancel" => assert_true(result is Stopped(_))
      "egress" => assert_true(result is Failed(Model(@model.Egress(_)), ..))
      _ => assert_true(result is Failed(Model(@model.Authorization(_)), ..))
    }
    assert_eq(calls.val, 0)
    assert_eq(saved.length(), 1)
    assert_eq(checks.length(), 4)
    for check in checks {
      assert_true(check)
    }
    assert_true(
      @model.acknowledge_saved_model_call_entry(originals[0], prepared) is None,
    )
    assert_true(cleanup(active).unwrap())
    assert_true(
      @model.acknowledge_saved_model_call_entry(originals[0], prepared) is None,
    )
    assert_eq(calls.val, 0)
  }
}

///|
test "saved entry acknowledgement refuses a same-value foreign prepared owner" {
  let calls = Ref(0)
  let current = Ref(evidence_account(@authorization.Allow))
  let now = Ref("2026-10-02T00:00:00.000Z")
  let egress = Ref(Some(egress_fixture_observation()))
  let (active, prepared, admission, prefix_work) = entry_gate_fixture(
    calls, current, now, egress,
  )
  let foreign_calls = Ref(0)
  let (foreign, foreign_prepared, _, foreign_work) = entry_gate_fixture(
    foreign_calls, current, now, egress,
  )
  assert_true(
    @model.prepared_model_identities(prepared) ==
    @model.prepared_model_identities(foreign_prepared),
  )
  let checks : Array[Bool] = []
  bind_model_dispatch(active, prepared, admission, entry => {
    checks.push(
      @model.acknowledge_saved_model_call_entry(entry, foreign_prepared) is None,
    )
    checks.push(
      @model.acknowledge_saved_model_call_entry(entry, prepared) is Some(_),
    )
    cancel(active) |> ignore
    true
  }).unwrap()
  assert_true(fixture_finish(active, initial_work=prefix_work) is Stopped(_))
  assert_eq(checks.length(), 2)
  for check in checks {
    assert_true(check)
  }
  assert_eq(calls.val, 0)
  assert_true(cleanup(active).unwrap())
  cancel(foreign) |> ignore
  assert_true(fixture_finish(foreign, initial_work=foreign_work) is Stopped(_))
  assert_true(cleanup(foreign).unwrap())
  assert_eq(foreign_calls.val, 0)
}
