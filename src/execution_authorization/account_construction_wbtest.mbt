///|
test "prepared Account refuses before preflight and preserves public wire admission" {
  let calls = Ref(0)
  let malformed = "not JSON"
  assert_true(
    admit_account_configuration_json_prepared(malformed, _ => {
      calls.val += 1
      false
    })
    is None,
  )
  assert_eq(calls.val, 1)
  assert_true(
    admit_account_configuration_json(malformed) is Err(MalformedWire(_)),
  )
}

///|
test "prepared Account funds canonical and admission before their first child" {
  let wire = account_inventory_wire([account_inventory_entry(0)])
  let requests : Array[AccountConfigurationConstruction] = []
  let admitted = admit_account_configuration_json_prepared(wire, request => {
      requests.push(request)
      true
    })
    .unwrap()
    .unwrap()
  assert_eq(
    admitted.configuration_cid(),
    admit_account_configuration_json(wire).unwrap().configuration_cid(),
  )
  assert_true(admitted.retains_original_bytes(@utf8.encode(wire)))
  assert_true(requests.length() >= 6)
  let canonical = requests[requests.length() - 2]
  assert_true(canonical.retained.record_headers > 0L)
  assert_true(canonical.retained.owned_utf16_units >= 71L)
  assert_true(
    canonical.execution.reference_slots > canonical.retained.reference_slots,
  )
  // Refuse at the final, canonical/admission reservation. It cannot fall back
  // to the public unprepared constructor or publish an admitted Account.
  let calls = Ref(0)
  assert_true(
    admit_account_configuration_json_prepared(wire, _ => {
      calls.val += 1
      calls.val < requests.length() - 1
    })
    is None,
  )
  assert_eq(calls.val, requests.length() - 1)
}

///|
test "prepared Account retains beyond old one MiB and preserves deny and wire refusal" {
  let wire = " ".repeat(1048577) + account_inventory_wire([])
  let admitted = admit_account_configuration_json_prepared(wire, _ => true)
    .unwrap()
    .unwrap()
  assert_true(admitted.retains_original_bytes(@utf8.encode(wire)))
  assert_true(
    evaluate_account(admitted, account_inventory_at("resource"))
    is Deny(NoMatch),
  )
  assert_true(
    admit_account_configuration_json_prepared("{}", _ => true).unwrap()
    is Err(MalformedWire(_)),
  )
}

///|
test "prepared Account overlap quote follows same-outcome skip and exact mixed conflict" {
  let last_request = fn(count : Int) {
    let latest : Ref[AccountConfigurationConstruction?] = Ref(None)
    let wire = account_inventory_wire(
      Array::makei(count, account_inventory_entry),
    )
    let admitted = admit_account_configuration_json_prepared(wire, request => {
        latest.val = Some(request)
        true
      })
      .unwrap()
      .unwrap()
    (admitted.entry_count(), latest.val.unwrap().execution.reference_slots)
  }
  let (small_count, small) = last_request(32)
  let (larger_count, larger) = last_request(64)
  assert_eq(small_count, 32)
  assert_eq(larger_count, 64)
  assert_true(larger < 3L * small)
  let wire = account_inventory_wire([
    account_inventory_entry(0),
    account_inventory_entry(1),
  ]).replace_all(
    old="\"entry_id\":\"entry-0001\",\"outcome\":\"allow\"",
    new="\"entry_id\":\"entry-0001\",\"outcome\":\"deny\"",
  )
  let prepared = admit_account_configuration_json_prepared(wire, _ => true).unwrap()
  assert_true(prepared is Err(ConflictingOutcomes(_)))
  match (prepared, admit_account_configuration_json(wire)) {
    (Err(left), Err(right)) => assert_eq(left, right)
    _ => fail("same original conflict refusal required")
  }
}
