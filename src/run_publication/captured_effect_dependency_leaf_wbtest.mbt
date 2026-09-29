///|
test "logical Relation dependency preserves tagged identity and recovery bytes" {
  // Independent Node crypto hashes, not expectations issued by this reader.
  let wire = "{\"sort\":\"relation\",\"value\":[{\"id\":1}]}"
  let cid = "sha256:581c1ad7ac48237df5c669e328275ed013a700f7308143a32557810117210089"
  let logical = admit_hashed_effect_dependency_body(
    "relation_value", cid, wire, 10000, 1000, 32,
  ).unwrap()
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 1,
    max_total_bytes: 10000,
    max_depth: 8,
    max_references: 1,
  }
  let inventory = issue_captured_effect_dependency_inventory(
    [logical],
    [logical],
    limits,
    1000,
    32,
  ).unwrap()
  let expected = "[{\"body\":" +
    wire +
    " ,\"cid\":\"" +
    cid +
    "\",\"kind\":\"relation_value\"}]"
  // Deliberately noncanonical envelope cannot be repaired on restart.
  assert_true(
    admit_captured_effect_dependency_inventory(
      expected,
      [logical],
      limits,
      1000,
      32,
    )
    is Err(InvalidBody),
  )
  let restored = admit_captured_effect_dependency_inventory(
    inventory.wire,
    [logical],
    limits,
    1000,
    32,
  ).unwrap()
  assert_eq(restored.bodies[0].wire, wire)
  for
    (identity, text) in [
      (
        "sha256:bb41eeeedb7789a3482cc74a1ac8d84effb2a508b753948130e3958c39004120",
        "[{\"id\":1}]",
      ),
      (
        "sha256:781823acd403c6329976a1f031db7962c2830c7fc1f729a109da7ada345ebf8c",
        "{\"sort\":\"other\",\"value\":[]}",
      ),
      (cid, "{\"sort\":\"relation\",\"value\":[]}"),
    ] {
    assert_true(
      admit_hashed_effect_dependency_body(
        "relation_value", identity, text, 10000, 1000, 32,
      )
      is Err(InvalidBody),
    )
  }
}

///|
test "equal canonical bodies retain distinct checked dependency roles" {
  // Independent Node crypto SHA-256 of the two-byte UTF-8 text {}.
  let cid = "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
  let declarations = admit_hashed_effect_dependency_body(
    "parameter_declarations", cid, "{}", 10000, 1000, 32,
  ).unwrap()
  let request = admit_hashed_effect_dependency_body(
    "request_values", cid, "{}", 10000, 1000, 32,
  ).unwrap()
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 2,
    max_total_bytes: 10000,
    max_depth: 8,
    max_references: 2,
  }
  let inventory = issue_captured_effect_dependency_inventory(
    [request, declarations],
    [request, declarations],
    limits,
    1000,
    32,
  ).unwrap()
  let expected = "[{\"body\":{},\"cid\":\"" +
    cid +
    "\",\"kind\":\"parameter_declarations\"},{\"body\":{},\"cid\":\"" +
    cid +
    "\",\"kind\":\"request_values\"}]"
  assert_eq(inventory.wire, expected)
  let restored = admit_captured_effect_dependency_inventory(
    expected,
    [request, declarations],
    limits,
    1000,
    32,
  ).unwrap()
  assert_eq(restored.bodies.length(), 2)
  assert_eq(
    validate_captured_effect_dependency_bodies(
      [declarations],
      [request],
      0,
      limits,
    ),
    Err(WrongDependencyKind),
  )
  assert_true(
    issue_captured_effect_dependency_inventory(
      [declarations, declarations],
      [declarations],
      limits,
      1000,
      32,
    )
    is Err(DuplicateIdentity),
  )
  for wire in [" {}", "{\"x\":1}", "[]"] {
    assert_true(
      admit_hashed_effect_dependency_body(
        "parameter_declarations", cid, wire, 10000, 1000, 32,
      )
      is Err(InvalidBody),
    )
  }
  assert_true(
    admit_hashed_effect_dependency_body(
      "caller_edges", cid, "{}", 10000, 1000, 32,
    )
    is Err(WrongDependencyKind),
  )
}
