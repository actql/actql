///|
test "Native read selection requires an explicit exclusive finite profile alternative" {
  let cid = "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243"
  let absolute = "\"expires_at\":\"2026-10-12T00:00:00.000Z\""
  let finite = "\"run_policy_profile_cid\":\"" + cid + "\""
  let legacy = admit_native_local_read_selection(local_read_original_wire).unwrap()
  assert_true(legacy.expiry is Absolute("2026-10-12T00:00:00.000Z"))
  let selected = admit_native_local_read_selection(
    local_read_original_wire.replace(old=absolute, new=finite),
  ).unwrap()
  assert_true(selected.expiry is AcceptedRunProfile(actual) && actual == cid)
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
