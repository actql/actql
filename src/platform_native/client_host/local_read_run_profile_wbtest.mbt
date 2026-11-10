///|
test "Native read selection requires an explicit exclusive finite profile alternative" {
  let cid = "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243"
  let absolute = "\"expires_at\":\"2026-10-12T00:00:00.000Z\""
  let finite = "\"run_policy_profile_cid\":\"" +
    cid +
    "\",\"run_file\":\"custom-run.json\",\"retention_file\":\"custom-retention.json\",\"store_file\":\"custom-store.json\""
  let legacy = admit_native_local_read_selection(local_read_original_wire).unwrap()
  assert_true(legacy.expiry is Absolute("2026-10-12T00:00:00.000Z"))
  let selected = admit_native_local_read_selection(
    local_read_original_wire.replace(old=absolute, new=finite),
  ).unwrap()
  guard selected.expiry is AcceptedRunProfile(roles) else {
    fail("finite roles missing")
  }
  assert_eq(roles.profile_cid, cid)
  assert_eq(roles.run_file, "custom-run.json")
  assert_eq(roles.retention_file, "custom-retention.json")
  assert_eq(roles.store_file, "custom-store.json")
  assert_eq(selected.max_bytes, 65536)
  assert_eq(selected.max_uses, 1)
  assert_eq(selected.purpose, "inspection")
  for
    replacement in [
      absolute + "," + finite,
      finite + "," + finite,
      "\"run_policy_profile_cid\":null",
      "\"run_policy_profile_cid\":\"copied\"",
    ] {
    assert_true(
      admit_native_local_read_selection(
        local_read_original_wire.replace(old=absolute, new=replacement),
      )
      is Err(_),
    )
  }
}

///|
test "Native finite read roles are complete exclusive literal selected-file names" {
  let profile = "\"run_policy_profile_cid\":\"sha256:" + "a".repeat(64) + "\""
  let absolute = "\"expires_at\":\"2026-10-12T00:00:00.000Z\""
  let roles = [
    "\"run_file\":\"custom-run.json\"", "\"retention_file\":\"custom-retention.json\"",
    "\"store_file\":\"custom-store.json\"",
  ]
  for count in 0..<3 {
    assert_true(
      admit_native_local_read_selection(
        local_read_original_wire.replace(
          old=absolute,
          new=[profile, ..roles[:count]].join(","),
        ),
      )
      is Err(InvalidOriginal),
    )
  }
  for role in roles {
    assert_true(
      admit_native_local_read_selection(
        local_read_original_wire.replace(
          old=absolute,
          new=absolute + "," + role,
        ),
      )
      is Err(InvalidOriginal),
    )
  }
  let finite = [profile, ..roles].join(",")
  for invalid in ["", ".", "..", "a/b", "a\\\\b", "a".repeat(129)] {
    assert_true(
      admit_native_local_read_selection(
        local_read_original_wire.replace(
          old=absolute,
          new=finite.replace(old="custom-run.json", new=invalid),
        ),
      )
      is Err(InvalidOriginal),
    )
  }
}

///|
test "Native read selection without an expiry alternative cannot issue unbounded read" {
  assert_true(
    admit_native_local_read_selection(
      local_read_original_wire.replace(
        old=",\"expires_at\":\"2026-10-12T00:00:00.000Z\"",
        new="",
      ),
    )
    is Err(InvalidOriginal),
  )
}

///|
test "accepted Run Policy selection is explicit finite exclusive and closed" {
  let literal = "\"data_policy_cids\":[\"sha256:" + "a".repeat(64) + "\"]"
  let finite = local_read_original_wire.replace(
    old="\"expires_at\":\"2026-10-12T00:00:00.000Z\"",
    new="\"run_policy_profile_cid\":\"sha256:" +
      "b".repeat(64) +
      "\",\"run_file\":\"run.json\",\"retention_file\":\"retention.json\",\"store_file\":\"store.json\"",
  )
  let accepted = finite.replace(old=literal, new="\"accepted_run_policy\":true")
  assert_true(
    admit_native_local_read_selection(accepted).unwrap().policy
    is AcceptedRunPolicy,
  )
  assert_true(
    admit_native_local_read_selection(finite).unwrap().policy
    is ExplicitPolicyCids(_),
  )
  assert_true(
    admit_native_local_read_selection(local_read_original_wire).unwrap().policy
    is ExplicitPolicyCids(_),
  )
  for
    replacement in [
      "\"accepted_run_policy\":false",
      "\"accepted_run_policy\":null",
      "\"accepted_run_policy\":1",
      "\"accepted_run_policy\":\"true\"",
      "\"accepted_run_policy\":true," + literal,
      "\"data_policy_cids\":[]",
      "\"unknown_policy\":true",
      "\"accepted_run_policy\":true,\"accepted_run_policy\":true",
    ] {
    assert_true(
      admit_native_local_read_selection(
        finite.replace(old=literal, new=replacement),
      )
      is Err(_),
    )
  }
  assert_true(
    admit_native_local_read_selection(
      local_read_original_wire.replace(
        old=literal,
        new="\"accepted_run_policy\":true",
      ),
    )
    is Err(InvalidOriginal),
  )
}
