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

///|
test "entry persistence carrier preserves pending absent unknown and saved" {
  for variant in ["absent", "unknown", "saved"] {
    let calls = Ref(0)
    let current = Ref(evidence_account(@authorization.Allow))
    let now = Ref("2026-10-02T00:00:00.000Z")
    let egress = Ref(Some(egress_fixture_observation()))
    let (active, prepared, admission, prefix_work) = entry_gate_fixture(
      calls, current, now, egress,
    )
    let checks : Array[Bool] = []
    let polls = Ref(0)
    let pending = Ref(true)
    let operations : Array[@model.ModelCallEntryPersistence] = []
    let entries : Array[@model.ModelCallEntry] = []
    bind_model_dispatch(active, prepared, admission, entry => {
      entries.push(entry)
      let operation = @model.model_call_entry_persistence(entry, prepared, () => {
        polls.val += 1
        if pending.val {
          return @model.Pending
        }
        match variant {
          "absent" => @model.NotRecorded
          "unknown" => @model.Unknown
          _ =>
            @model.Saved(
              @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
            )
        }
      }).unwrap()
      operations.push(operation)
      checks.push(
        physical_equal(
          operation,
          @model.model_call_entry_persistence(entry, prepared, () => {
            // Re-opening cannot install or retain a second poll closure.
            polls.val += 1000
            @model.Unknown
          }).unwrap(),
        ),
      )
      for _ in 0..<2 {
        checks.push(
          @model.poll_model_call_entry_persistence(operation, entry, prepared)
          is Ok(@model.Pending),
        )
      }
      pending.val = false
      // A late physical save is not made invalid by current revocation.
      current.val = evidence_account(@authorization.Deny)
      let result = @model.poll_model_call_entry_persistence(
        operation, entry, prepared,
      )
      checks.push(
        match variant {
          "absent" => result is Ok(@model.NotRecorded)
          "unknown" => result is Ok(@model.Unknown)
          _ => result is Ok(@model.Saved(_))
        },
      )
      pending.val = true
      checks.push(
        match
          @model.poll_model_call_entry_persistence(operation, entry, prepared) {
          Ok(@model.NotRecorded) => variant == "absent"
          Ok(@model.Unknown) => variant == "unknown"
          Ok(@model.Saved(_)) => variant == "saved"
          _ => false
        },
      )
      // Carrier tests do not replace the old Bool entry contract with a new
      // async dispatcher. The old adapter still explicitly refuses here.
      false
    }).unwrap()
    assert_true(
      fixture_finish(active, initial_work=prefix_work)
      is Failed(Model(@model.CallEntryRefused), ..),
    )
    assert_eq(polls.val, 3)
    assert_eq(checks.length(), 5)
    for check in checks {
      assert_true(check)
    }
    assert_eq(calls.val, 0)
    assert_true(
      @model.poll_model_call_entry_persistence(
        operations[0],
        entries[0],
        prepared,
      )
      is Err(@model.CallEntryRefused),
    )
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 0)
  }
}

///|
test "entry persistence carrier rejects a foreign acknowledgement" {
  let calls = Ref(0)
  let current = Ref(evidence_account(@authorization.Allow))
  let now = Ref("2026-10-02T00:00:00.000Z")
  let egress = Ref(Some(egress_fixture_observation()))
  let (active, prepared, admission, prefix_work) = entry_gate_fixture(
    calls, current, now, egress,
  )
  let (foreign, other, foreign_admission, other_work) = entry_gate_fixture(
    calls, current, now, egress,
  )
  let checks : Array[Bool] = []
  let acknowledgements : Array[@model.ModelCallEntryAcknowledgement] = []
  bind_model_dispatch(active, prepared, admission, entry => {
    acknowledgements.push(
      @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
    )
    false
  }).unwrap()
  assert_true(
    fixture_finish(active, initial_work=prefix_work)
    is Failed(Model(@model.CallEntryRefused), ..),
  )
  bind_model_dispatch(foreign, other, foreign_admission, entry => {
    let operation = @model.model_call_entry_persistence(entry, other, () => {
      @model.Saved(acknowledgements[0])
    }).unwrap()
    checks.push(
      @model.poll_model_call_entry_persistence(operation, entry, other)
      is Err(@model.CallEntryRefused),
    )
    false
  }).unwrap()
  assert_true(
    fixture_finish(foreign, initial_work=other_work)
    is Failed(Model(@model.CallEntryRefused), ..),
  )
  assert_eq(checks.length(), 1)
  assert_true(checks[0])
  assert_eq(calls.val, 0)
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(foreign).unwrap())
}

///|
test "persistence originals keep the same owned evidence after stop without observing current twice" {
  let calls = Ref(0)
  let current = Ref(evidence_account(@authorization.Allow))
  let now = Ref("2026-10-02T00:00:00.000Z")
  let egress = Ref(Some(egress_fixture_observation()))
  let observations = Ref(0)
  let (active, prepared, admission, prefix_work) = entry_gate_fixture(
    calls,
    current,
    now,
    egress,
    current_observations=Some(observations),
  )
  let (foreign, foreign_prepared, foreign_admission, foreign_work) = entry_gate_fixture(
    Ref(0),
    current,
    now,
    egress,
  )
  let entries : Array[@model.ModelCallEntry] = []
  let checks : Array[Bool] = []
  bind_model_dispatch(active, prepared, admission, entry => {
    entries.push(entry)
    let observed = observations.val
    let before = @model.model_call_entry_persistence_originals(
      entry, prepared, admission,
    ).unwrap()
    checks.push(before.0 == 2 && before.1 == 0)
    checks.push(
      @model.model_call_entry_persistence_originals(
        entry, foreign_prepared, admission,
      )
      is None,
    )
    checks.push(
      @model.model_call_entry_persistence_originals(
        entry, prepared, foreign_admission,
      )
      is None,
    )
    cancel(active) |> ignore
    current.val = evidence_account(@authorization.Deny)
    let after = @model.model_call_entry_persistence_originals(
      entry, prepared, admission,
    ).unwrap()
    checks.push(
      physical_equal(before.2, after.2) &&
      physical_equal(before.3, after.3) &&
      physical_equal(before.4, after.4) &&
      physical_equal(before.5, after.5),
    )
    checks.push(observations.val == observed)
    checks.push(@model.model_call_entry_originals(entry) is None)
    checks.push(
      @model.model_call_entry_acknowledgement_current(
        @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
        prepared,
      ) ==
      false,
    )
    true
  }).unwrap()
  assert_true(fixture_finish(active, initial_work=prefix_work) is Stopped(_))
  assert_eq(checks.length(), 7)
  for check in checks {
    assert_true(check)
  }
  assert_eq(calls.val, 0)
  assert_true(
    @model.model_call_entry_persistence_originals(
      entries[0],
      prepared,
      admission,
    )
    is None,
  )
  assert_true(cleanup(active).unwrap())
  cancel(foreign) |> ignore
  assert_true(fixture_finish(foreign, initial_work=foreign_work) is Stopped(_))
  assert_true(cleanup(foreign).unwrap())
}
