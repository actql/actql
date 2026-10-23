///|
test "stored index keeps its exact completed admission original" {
  // This is a real admitted Index envelope; full graph validation remains in
  // the separate stored-publication blackbox controls.
  let fixture = commit_cursor_fixture(["answer"])
  let index = fixture.reference_inputs.index_entry
  let wire = publication_contract_json(index)
  let admitted = admit_publication_contract(
    "public_index_entry", wire, 65536, 4096, 32,
  ).unwrap()
  let kept = admit_stored_contract_original(
    "public_index_entry", wire, admitted, wire, 65536, 4096, 32,
  ).unwrap()
  assert_eq(kept.wire, admitted.wire)
  assert_eq(kept.identity, admitted.identity)
  assert_true(physical_equal(kept, admitted))
  assert_true(physical_equal(kept.value, admitted.value))
}

///|
test "stored index different wire missing usage and tighter limits keep full admission" {
  let index = commit_cursor_fixture(["answer"]).reference_inputs.index_entry
  let wire = publication_contract_json(index)
  let admitted = admit_publication_contract(
    "public_index_entry", wire, 65536, 4096, 32,
  ).unwrap()
  let copied = admit_stored_contract_original(
    "public_index_entry",
    wire + " ",
    admitted,
    wire,
    65536,
    4096,
    32,
  ).unwrap()
  assert_false(physical_equal(copied, admitted))
  assert_eq(copied.wire, admitted.wire)
  assert_eq(copied.identity, admitted.identity)
  let missing = { ..admitted, wire_usage: None, }
  let readmitted = admit_stored_contract_original(
    "public_index_entry", wire, missing, wire, 65536, 4096, 32,
  ).unwrap()
  assert_false(physical_equal(readmitted, missing))
  assert_eq(readmitted.wire, admitted.wire)
  for
    (bytes, nodes, depth) in [
      (@utf8.encode(wire).length() - 1, 4096, 32),
      (65536, 1, 32),
      (65536, 4096, 1),
      (0, 4096, 32),
    ] {
    assert_true(
      admit_stored_contract_original(
        "public_index_entry", wire, admitted, wire, bytes, nodes, depth,
      )
      is Err(_),
    )
  }
  assert_true(
    admit_stored_contract_original(
      "run_receipt", wire, admitted, wire, 65536, 4096, 32,
    )
    is Err(_),
  )
  assert_true(
    admit_stored_contract_original(
      "public_index_entry", "{}", admitted, wire, 65536, 4096, 32,
    )
    is Err(_),
  )
}
