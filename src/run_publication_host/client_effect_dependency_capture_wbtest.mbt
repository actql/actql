///|
test "dependency body funding precedes parsing and fences actual callback reentry" {
  let calls = Ref(0)
  let dimensions = Ref((0, 0, 0))
  assert_true(
    admit_client_effect_dependency_capture_body(
      "data_policy",
      None,
      "{",
      100,
      100,
      32,
      Some((bytes, nodes, depth) => {
        calls.val += 1
        dimensions.val = (bytes, nodes, depth)
        false
      }),
      () => true,
    )
    is Err(ConstructionRefused),
  )
  assert_eq(calls.val, 1)
  assert_eq(dimensions.val, (1, 1, 1))
  assert_true(
    admit_client_effect_dependency_capture_body(
      "data_policy",
      None,
      "{",
      0,
      100,
      32,
      Some((_, _, _) => {
        calls.val += 1
        true
      }),
      () => true,
    )
    is Err(Dependency(@publication.ByteLimit)),
  )
  assert_eq(calls.val, 1)
  let current = Ref(true)
  assert_true(
    admit_client_effect_dependency_capture_body(
      "data_policy",
      None,
      "{",
      100,
      100,
      32,
      Some((_, _, _) => {
        current.val = false
        true
      }),
      () => current.val,
    )
    is Err(ForeignInput),
  )
  // Without a storage refusal/reentry the SAME invalid JSON reaches its
  // original typed decoder; storage success never blesses a body.
  assert_true(
    admit_client_effect_dependency_capture_body(
      "data_policy",
      None,
      "{",
      100,
      100,
      32,
      Some((_, _, _) => true),
      () => true,
    )
    is Err(Dependency(@publication.InvalidBody)),
  )
}

///|
test "funded dependency admission preserves an independent original policy identity" {
  let wire = "{\"classification\":\"public\",\"minimum_classification\":null,\"source_data_policy_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"source_ref\":\"connector://fixture/rows\",\"source_view_contract_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"actql-source-response-policy/0.1\"}"
  // The SHA is independently fixed in the existing publication policy corpus.
  let cid = "sha256:265c083ea20b8e64985c3b6f945e0ee9b6eb941aae6c5acd243cd082fe0deb23"
  let calls = Ref(0)
  let checked = Ref(0)
  let (body, bytes) = admit_client_effect_dependency_capture_body(
    "data_policy",
    Some(cid),
    wire,
    10000,
    1000,
    32,
    Some((bytes, nodes, depth) => {
      calls.val += 1
      bytes == wire.length() && nodes == bytes && depth == 32
    }),
    () => {
      checked.val += 1
      true
    },
  ).unwrap()
  assert_eq(bytes, wire.length())
  assert_eq(@publication.captured_effect_dependency_body_cid(body), cid)
  assert_eq((calls.val, checked.val), (1, 1))
  let (unfunded, _) = admit_client_effect_dependency_capture_body(
    "data_policy",
    Some(cid),
    wire,
    10000,
    1000,
    32,
    None,
    () => {
      checked.val += 1
      false
    },
  ).unwrap()
  assert_eq(@publication.captured_effect_dependency_body_cid(unfunded), cid)
  assert_eq(checked.val, 1)
}
