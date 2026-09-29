///|
test "dependency inventory preserves canonical bodies and counts envelope bytes" {
  // Independent Node crypto over the canonical empty acquisition scope.
  let cid = "sha256:58aca71c9645edf63bfebadb8d0717cccebbc1a7092ad6f12ee9192304401bc3"
  let body_wire = "{\"self_cid\":\"" +
    cid +
    "\",\"sources\":[],\"version\":\"actql-acquisition-scope/0.1\"}"
  let expected = "[{\"body\":" +
    body_wire +
    ",\"cid\":\"" +
    cid +
    "\",\"kind\":\"acquisition_scope\"}]"
  let body = admit_publication_effect_dependency_body(
    "acquisition_scope", body_wire, 10000, 1000, 32,
  ).unwrap()
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 1,
    max_total_bytes: @utf8.encode(expected).length(),
    max_depth: 1,
    max_references: 1,
  }
  let issued = issue_captured_effect_dependency_inventory(
    [body],
    [body],
    limits,
    1000,
    32,
  ).unwrap()
  assert_eq(captured_effect_dependency_inventory_json(issued), expected)
  let restored = admit_captured_effect_dependency_inventory(
    expected,
    [body],
    limits,
    1000,
    32,
  ).unwrap()
  assert_eq(captured_effect_dependency_inventory_json(restored), expected)
  assert_eq(captured_effect_dependency_inventory_count(restored), 1)
  assert_true(
    issue_captured_effect_dependency_inventory(
      [body],
      [body],
      { ..limits, max_total_bytes: limits.max_total_bytes - 1, },
      1000,
      32,
    )
    is Err(ByteLimit),
  )
  assert_true(
    admit_captured_effect_dependency_inventory(
      expected,
      [body],
      { ..limits, max_total_bytes: limits.max_total_bytes - 1, },
      1000,
      32,
    )
    is Err(_),
  )
  for
    invalid in [
      "{}",
      " " + expected,
      expected.replace(old="acquisition_scope", new="unknown"),
      expected.replace(
        old="\"cid\":\"" + cid,
        new="\"cid\":\"" + relation_fixture_cid("e"),
      ),
      expected.replace(old="\"kind\":", new="\"edges\":[],\"kind\":"),
      expected.replace(old="\"sources\":[]", new="\"sources\":[{}]"),
    ] {
    assert_true(
      admit_captured_effect_dependency_inventory(
        invalid,
        [body],
        { ..limits, max_total_bytes: 10000, },
        1000,
        32,
      )
      is Err(_),
    )
  }
  assert_true(
    admit_captured_effect_dependency_inventory("[]", [body], limits, 1000, 32)
    is Err(MissingDependency),
  )
  assert_true(
    admit_captured_effect_dependency_inventory(expected, [], limits, 1000, 32)
    is Err(UnusedDependency),
  )
  assert_eq(
    captured_effect_dependency_inventory_json(
      issue_captured_effect_dependency_inventory([], [], limits, 1000, 32).unwrap(),
    ),
    "[]",
  )
  assert_true(
    issue_captured_effect_dependency_inventory(
      [body, body],
      [body],
      { ..limits, max_entries: 2, max_total_bytes: 10000, },
      1000,
      32,
    )
    is Err(DuplicateIdentity),
  )
}
