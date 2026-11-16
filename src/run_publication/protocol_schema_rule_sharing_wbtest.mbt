///|
test "generated protocol table shares identical immutable rules without merging constraints" {
  let first = generated_protocol_schema_nodes()
  let second = generated_protocol_schema_nodes()
  // Sharing must preserve the registered descriptors and their constraints;
  // adding an unrelated protocol does not change this constructor contract.
  assert_true(first.length() > 3)
  assert_eq(second.length(), first.length())
  for
    name in [
      "control_profile", "native_file_lookup_adoption", "installed_row_source_read",
    ] {
    for complete in [false, true] {
      let root = generated_protocol_schema_root(name, complete).unwrap()
      assert_true(root >= 0 && root < first.length())
      assert_true(root < second.length())
    }
  }
  // Slots 1 and 3 describe the same nonempty String rule. The CID
  // pattern at slot 2 is distinct, and another construction owns its own data.
  guard first[1] is StringRule(None, choices, 0, 1) else {
    fail("original nonempty String rule")
  }
  assert_true(choices.is_empty())
  assert_false(physical_equal(first[1], first[2]))
  assert_false(physical_equal(first[1], second[1]))
  assert_true(physical_equal(first[1], first[3]))
}

///|
test "shared generated rules preserve per-cursor validation work and cancellation" {
  let nodes = protocol_schema_nodes()
  for wire in ["\"x\"", "\"\"", "null", "1"] {
    for quantum in [1, 7] {
      let first = protocol_test_start(wire, nodes, 1, 1)
      let second = protocol_test_start(wire, nodes, 3, 1)
      let result = protocol_test_finish(first, quantum)
      assert_eq(result, protocol_test_finish(second, quantum))
      assert_eq(result.0, wire == "\"x\"")
      assert_eq(first.budget.remaining, 0)
      assert_eq(second.budget.remaining, 0)
    }
  }
  let cancelled = protocol_test_start("\"x\"", nodes, 1, 1)
  let live = protocol_test_start("\"x\"", nodes, 3, 1)
  cancelled.cancel()
  assert_eq(live.budget.remaining, 1)
  assert_eq(protocol_test_finish(live, 1).0, true)
  assert_eq(
    protocol_test_finish(protocol_test_start("\"x\"", nodes, 3, 0), 1).0,
    false,
  )
}
