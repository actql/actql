///|
let signing_bootstrap_policy_wire : String = "{\"max_issue_interval_ms\":300000,\"max_uses\":1,\"version\":\"actql-local-signing-bootstrap-policy/0.1\"}"

///|
let signing_bootstrap_policy_cid : String = "sha256:8fe727ecd855e06e0bcb07262c31f9b4e2f211292c3393b5e3f4b7e5cf1501e1"

///|
test "default signing policy preserves independent exact packaged bytes and identity" {
  let policy = client_local_default_signing_bootstrap_policy()
  assert_eq(policy.original_wire(), signing_bootstrap_policy_wire)
  assert_eq(policy.cid(), signing_bootstrap_policy_cid)
  assert_eq(policy.max_uses(), 1)
  let saved = admit_client_local_signing_bootstrap_policy(
    signing_bootstrap_policy_wire, signing_bootstrap_policy_cid,
  ).unwrap()
  assert_eq(saved.original_wire(), policy.original_wire())
}

///|
test "default signing saved policy refuses replaced incomplete noncanonical and foreign DATA" {
  for
    altered in [
      " " + signing_bootstrap_policy_wire,
      signing_bootstrap_policy_wire.replace(old="300000", new="300001"),
      signing_bootstrap_policy_wire.replace(
        old="\"max_uses\":1",
        new="\"max_uses\":2",
      ),
      signing_bootstrap_policy_wire.replace(old="\"max_uses\":1,", new=""),
      signing_bootstrap_policy_wire.replace(
        old="{",
        new="{\"issuer_allow\":true,",
      ),
    ] {
    assert_true(
      admit_client_local_signing_bootstrap_policy(altered, product_cid(altered))
      is Err(ForeignPolicy),
    )
  }
  assert_true(
    admit_client_local_signing_bootstrap_policy(
      signing_bootstrap_policy_wire,
      "sha256:" + "a".repeat(64),
    )
    is Err(ForeignPolicy),
  )
}

///|
test "default signing issuer identity uses original initialization not later Host or key identity" {
  let original = initialization_fixture_body()
  let policy = client_local_default_signing_bootstrap_policy()
  let intent = "sha256:" + @sha.hex(original)
  assert_eq(
    policy.issuer_identity(intent).unwrap(),
    "local-signing/sha256:d7b077fa3a803302e5a5374ca5dc71ea879876760af126b7e1c0eaf16d9cf46b",
  )
  assert_eq(initialization_fixture_body(), original)
  assert_true(
    policy.issuer_identity("sha256:" + "b".repeat(64)).unwrap() !=
    policy.issuer_identity(intent).unwrap(),
  )
  // Both are DATA identities. The physical Host must authenticate which
  // original initialization it owns; this helper admits no issuer capability.
}

///|
test "default signing issuer identity rejects malformed or normalized intent CID spelling" {
  let policy = client_local_default_signing_bootstrap_policy()
  for
    value in [
      "",
      "host",
      "sha256:" + "A".repeat(64),
      "sha256:" + "a".repeat(63),
      " sha256:" + "a".repeat(64),
    ] {
    assert_true(
      policy.issuer_identity(value) is Err(InvalidInitializationIdentity),
    )
  }
}

///|
test "default signing first issue caps original validity and checks exact Int64 interval" {
  let policy = client_local_default_signing_bootstrap_policy()
  for
    (sample, bound, expected) in [
      (0L, None, 300000L),
      (1000L, Some(1500L), 1500L),
      (1000L, Some(301000L), 301000L),
      (1000L, Some(9223372036854775807L), 301000L),
      (9223372036854475807L, None, 9223372036854775807L),
    ] {
    let issued = policy.prepare_first_issue(sample, bound).unwrap()
    assert_eq(issued.sampled_at(), sample)
    assert_eq(issued.expires_at(), expected)
  }
}

///|
test "default signing first issue refuses negative overflowing expired and equal validity" {
  let policy = client_local_default_signing_bootstrap_policy()
  for
    (sample, bound) in [
      (-1L, None),
      (9223372036854475808L, None),
      (1000L, Some(1000L)),
      (1000L, Some(999L)),
    ] {
    assert_true(
      policy.prepare_first_issue(sample, bound) is Err(InvalidIssueTime),
    )
  }
}

///|
test "default signing issue candidate keeps its first absolute values without renewing another candidate" {
  let policy = client_local_default_signing_bootstrap_policy()
  let original = policy.prepare_first_issue(1000L, None).unwrap()
  let other_candidate = policy.prepare_first_issue(2000L, None).unwrap()
  assert_eq(original.sampled_at(), 1000L)
  assert_eq(original.expires_at(), 301000L)
  assert_eq(other_candidate.expires_at(), 302000L)
  // Creating candidate DATA is not another permitted issue. Only the actual
  // original journal may select/persist once and refuse a claimed/Unknown use.
}
