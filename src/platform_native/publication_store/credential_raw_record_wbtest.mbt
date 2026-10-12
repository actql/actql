///|
// Authored existing grant/use literals and independent standard-library
// JSON/UTF-8/SHA-256 expectations. No Store or Provider permission is issued.
let raw_test_grant_wire : String =
  #|{"account_configuration_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","account_id":"account-a","attempt_id":"observe-original","authority_scope_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","connector_registration":"salesforce-a","connector_revision":"salesforce-a/1","expires_unix_ms":"2000000000000","host_adoption_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","issuer_authority":"local-authority-a","max_uses":2,"operation":"salesforce:record:observe","operation_occurrence_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","preparation_fence_cid":"sha256:25682af870e2978302b45578ce9aca8d560549c3c510a073242669a5a3efbf34","principal":"operator","request_body_cid":"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","request_cid":"sha256:6666666666666666666666666666666666666666666666666666666666666666","request_method":"GET","request_path":"/services/data/v61.0/sobjects/Account/001-original","resource_origin":"https://resource.example","run_invocation_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","submission_scope_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","unit_definition_cid":"sha256:5555555555555555555555555555555555555555555555555555555555555555","version":"actql-local-preparation-credential-grant/0.1"}

///|
let raw_test_use_wire : String =
  #|{"grant_cid":"sha256:f94a8a51a980cc764a6bc45f2e10805537effe1dc89e73991d119d8986ae41d2","use_id":"observe-use","use_ordinal":1,"version":"actql-local-credential-use/0.1"}

///|
fn raw_test_credentials() -> (
  @credential.LocalPreparationCredentialGrant,
  @credential.LocalPreparationCredentialUse,
) {
  let cid = (digit : String) => "sha256:" + digit.repeat(64)
  let fence = @credential.prepare_local_preparation_fence_identity({
    client_request_intent_cid: cid("1"),
    client_request_scope_cid: cid("2"),
    operation_occurrence_cid: cid("3"),
    run_invocation_cid: cid("4"),
    unit_definition_cid: cid("5"),
  }).unwrap()
  let grant = @credential.admit_local_preparation_credential_grant_json(
    raw_test_grant_wire, "sha256:f94a8a51a980cc764a6bc45f2e10805537effe1dc89e73991d119d8986ae41d2",
    fence,
  ).unwrap()
  let original_use = @credential.admit_local_preparation_credential_use_json(
    grant, raw_test_use_wire, "sha256:17f393ef1ac8c8fd7d86ddb27ae3f62869b6d3391bf1a1c040b10df8169443f8",
  ).unwrap()
  (grant, original_use)
}

///|
fn raw_test_binding(limit : Int64) -> LocalPreparationRawBinding {
  let (grant, original_use) = raw_test_credentials()
  local_preparation_raw_binding(
    grant,
    original_use,
    "sha256:" + "c".repeat(64),
    limit,
  ).unwrap()
}

///|
test "raw binding independent preimage includes original grant and use, not response or capacity" {
  let binding = raw_test_binding(4096L)
  assert_eq(
    binding.holding,
    "sha256:31b4f53329f31c997452b6f9dda6c382bcd05656e83b0fad97dfdf252ecf4ff2",
  )
  assert_eq(
    raw_observation_strings(binding.fields, 1048576).unwrap(),
    "[\"actql-native-local-preparation-raw-response/0.1\",\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"sha256:f94a8a51a980cc764a6bc45f2e10805537effe1dc89e73991d119d8986ae41d2\",\"sha256:17f393ef1ac8c8fd7d86ddb27ae3f62869b6d3391bf1a1c040b10df8169443f8\",\"{\\\"account_configuration_cid\\\":\\\"sha256:1111111111111111111111111111111111111111111111111111111111111111\\\",\\\"account_id\\\":\\\"account-a\\\",\\\"attempt_id\\\":\\\"observe-original\\\",\\\"authority_scope_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"connector_registration\\\":\\\"salesforce-a\\\",\\\"connector_revision\\\":\\\"salesforce-a/1\\\",\\\"expires_unix_ms\\\":\\\"2000000000000\\\",\\\"host_adoption_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"issuer_authority\\\":\\\"local-authority-a\\\",\\\"max_uses\\\":2,\\\"operation\\\":\\\"salesforce:record:observe\\\",\\\"operation_occurrence_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"preparation_fence_cid\\\":\\\"sha256:25682af870e2978302b45578ce9aca8d560549c3c510a073242669a5a3efbf34\\\",\\\"principal\\\":\\\"operator\\\",\\\"request_body_cid\\\":\\\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\\\",\\\"request_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"request_method\\\":\\\"GET\\\",\\\"request_path\\\":\\\"/services/data/v61.0/sobjects/Account/001-original\\\",\\\"resource_origin\\\":\\\"https://resource.example\\\",\\\"run_invocation_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"submission_scope_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"unit_definition_cid\\\":\\\"sha256:5555555555555555555555555555555555555555555555555555555555555555\\\",\\\"version\\\":\\\"actql-local-preparation-credential-grant/0.1\\\"}\",\"{\\\"grant_cid\\\":\\\"sha256:f94a8a51a980cc764a6bc45f2e10805537effe1dc89e73991d119d8986ae41d2\\\",\\\"use_id\\\":\\\"observe-use\\\",\\\"use_ordinal\\\":1,\\\"version\\\":\\\"actql-local-credential-use/0.1\\\"}\"]",
  )
  assert_eq(raw_test_binding(16L).holding, binding.holding)
}

///|
test "raw observations preserve non2xx and projection rejection without Catalog admission" {
  let binding = raw_test_binding(4096L)
  for
    (status, body) in [
      (401, b"denied"),
      (503, b"unavailable"),
      (200, b"not a Catalog"),
      (0, b"unclassified status"),
      (2147483647, b"original physical status"),
    ] {
    let wire = local_preparation_raw_record(binding, status, body).unwrap()
    let restored = restore_local_preparation_raw_record(wire, binding).unwrap()
    assert_eq(restored.status, status)
    assert_eq(restored.body, body)
  }
}

///|
test "raw observations preserve empty bodies and exact binary bytes" {
  let binding = raw_test_binding(4096L)
  for body in [b"", Bytes::from_array([0, 255, 128, 13, 10])] {
    let restored = restore_local_preparation_raw_record(
      local_preparation_raw_record(binding, 204, body).unwrap(),
      binding,
    ).unwrap()
    assert_eq(restored.body, body)
    assert_eq(restored.status, 204)
  }
}

///|
test "raw observations preserve composed decomposed and newline originals" {
  let binding = raw_test_binding(4096L)
  let bodies = [
    @utf8.encode("e\u0301"),
    @utf8.encode("é"),
    b"\r",
    b"\n",
    b"\r\n",
    @utf8.encode("{\"nested\":[\"e\u0301\",null]}"),
  ]
  let wires = bodies.map(body => {
    local_preparation_raw_record(binding, 200, body).unwrap()
  })
  for index, wire in wires {
    assert_eq(
      restore_local_preparation_raw_record(wire, binding).unwrap().body,
      bodies[index],
    )
    for prior in 0..<index {
      assert_true(wires[prior] != wire)
    }
  }
}

///|
test "raw restoration rejects another original use and foreign Store authority" {
  let (grant, original_use) = raw_test_credentials()
  let scope = @credential.local_preparation_credential_grant_scope(grant)
  let second = @credential.prepare_local_preparation_credential_use(
    grant, "second-use", 1999999999999L, 1, false, scope,
  ).unwrap()
  let binding = raw_test_binding(4096L)
  let wire = local_preparation_raw_record(binding, 200, b"original").unwrap()
  let foreign_use = local_preparation_raw_binding(
    grant,
    second,
    "sha256:" + "c".repeat(64),
    4096L,
  ).unwrap()
  let foreign_store = local_preparation_raw_binding(
    grant,
    original_use,
    "sha256:" + "d".repeat(64),
    4096L,
  ).unwrap()
  assert_true(
    restore_local_preparation_raw_record(wire, foreign_use)
    is Err(StateCollision),
  )
  assert_true(
    restore_local_preparation_raw_record(wire, foreign_store)
    is Err(StateCollision),
  )
}

///|
test "raw binding rejects a valid use from another admitted grant" {
  let (grant, original_use) = raw_test_credentials()
  let foreign_grant = @credential.prepare_local_preparation_credential_grant(
    "foreign-authority",
    @credential.local_preparation_credential_grant_scope(grant),
    2000000000000L,
    2,
  ).unwrap()
  assert_true(
    local_preparation_raw_binding(
      foreign_grant,
      original_use,
      "sha256:" + "c".repeat(64),
      4096L,
    )
    is Err(StateCollision),
  )
}

///|
test "raw record closed decoder refuses altered digest, body spelling, status and shape" {
  let binding = raw_test_binding(4096L)
  let wire = local_preparation_raw_record(binding, 200, b"original").unwrap()
  let fields = [
    "actql-native-local-preparation-raw-response/0.1",
    "sha256:" + "c".repeat(64),
    "sha256:f94a8a51a980cc764a6bc45f2e10805537effe1dc89e73991d119d8986ae41d2",
    "sha256:17f393ef1ac8c8fd7d86ddb27ae3f62869b6d3391bf1a1c040b10df8169443f8",
    raw_test_grant_wire,
    raw_test_use_wire,
    "4096",
    "200",
    "sha256:0682c5f2076f099c34cfdd15a9e063849ed437a49677e6fcc5b4198c76575be5",
    "b3JpZ2luYWw=",
  ]
  let altered = (fields : Array[String]) => {
    raw_observation_strings(fields, 16384).unwrap()
  }
  assert_eq(wire, altered(fields))
  for index in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] {
    let changed = fields.map(value => value)
    changed[index] = "foreign"
    assert_true(
      restore_local_preparation_raw_record(altered(changed), binding)
      is Err(StateCollision),
    )
  }
  let changed = fields.map(value => value)
  changed[7] = "0200"
  assert_true(
    restore_local_preparation_raw_record(altered(changed), binding)
    is Err(StateCollision),
  )
  changed[7] = "200"
  changed.push("extra")
  assert_true(
    restore_local_preparation_raw_record(altered(changed), binding)
    is Err(StateCollision),
  )
  assert_true(
    restore_local_preparation_raw_record(" " + wire, binding)
    is Err(StateCollision),
  )
}

///|
test "raw preflight accounts for descriptor and envelope before body allocation" {
  let binding = raw_test_binding(16L)
  let cost = local_preparation_raw_reservation_bytes(binding).unwrap()
  // Independent JSON lengths and base64 expansion; AES-GCM envelope overhead
  // is exactly 128 bytes in the unchanged private-evidence representation.
  assert_eq(cost, 5728L)
  assert_true(
    local_preparation_raw_record(binding, 200, Bytes::make(16, 1)) is Ok(_),
  )
  assert_true(
    local_preparation_raw_record(binding, 200, Bytes::make(17, 1))
    is Err(InvalidConfiguration),
  )
  assert_true(
    local_preparation_raw_binding(
      raw_test_credentials().0,
      raw_test_credentials().1,
      "sha256:" + "c".repeat(64),
      -1L,
    )
    is Err(InvalidConfiguration),
  )
  assert_true(
    local_preparation_raw_binding(
      raw_test_credentials().0,
      raw_test_credentials().1,
      "sha256:" + "c".repeat(64),
      2147483647L,
    )
    is Err(InvalidConfiguration),
  )
}
