///|
/// Independent transport vectors only: no live Owner, Account Allow or HTTP
/// result is manufactured by these tests.
fn cloud_host_test_expected() -> CloudHostIdentityExpected {
  {
    dispatch_cid: "sha256:" + "d".repeat(64),
    run_cid: "sha256:" + "e".repeat(64),
    task_key: "consumer-original",
    runtime_cid: "sha256:" + "f".repeat(64),
  }
}

///|
fn cloud_host_test_scope() -> NativeEffectCloudHostIdentityScope {
  {
    site_key: "site-original",
    site_generation: 4L,
    workspace_id: "workspace-original",
    authority_scope_cid: "sha256:" + "7".repeat(64),
    installation: "local",
    expires_ms: 2000L,
  }
}

///|
fn cloud_host_test_body() -> String {
  (
    #|{"version":"actql-cloud-effect-host-identity-current/0.1","queryId":"identity-original","dispatchCid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","taskKey":"consumer-original","workspaceId":"workspace-original","authorityScopeCid":"sha256:7777777777777777777777777777777777777777777777777777777777777777","runDefinitionCid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","principalId":"p_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","siteKey":"site-original","siteGeneration":4,"runtimeBundleCid":"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","installation":"local","observedAt":"1970-01-01T00:00:01.000Z","expiresAt":"1970-01-01T00:00:02.000Z"}
  )
}

///|
fn cloud_host_test_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 128, max_depth: 5, }
}

///|
fn cloud_host_test_read(
  body : String,
  now_ms : Int64,
) -> NativeEffectCloudHostIdentity? {
  cloud_host_identity_reply(
    @utf8.encode(body),
    cloud_host_test_expected(),
    "identity-original",
    cloud_host_test_scope(),
    now_ms,
    cloud_host_test_limits(),
  )
}

///|
test "Host identity query contains correlation only and no proposed authority" {
  let query = cloud_host_identity_query(
    cloud_host_test_expected(),
    "identity-original",
    cloud_host_test_limits(),
  ).unwrap()
  assert_eq(
    @utf8.decode(query),
    "{\"version\":\"actql-cloud-effect-host-identity-query/0.1\",\"queryId\":\"identity-original\",\"dispatchCid\":\"sha256:" +
    "d".repeat(64) +
    "\"}",
  )
  for label in ["", "bad\nquery", "é".repeat(129)] {
    assert_true(
      cloud_host_identity_query(
        cloud_host_test_expected(),
        label,
        cloud_host_test_limits(),
      )
      is None,
    )
  }
}

///|
test "Host identity framing returns original principal independently of any permission" {
  let identity = cloud_host_test_read(cloud_host_test_body(), 1001L).unwrap()
  assert_eq(identity.principal_id(), "p_" + "b".repeat(32))
  assert_eq(identity.expires_ms, 2000L)
}

///|
test "Host identity framing rejects foreign original coordinates and replay" {
  for
    (before, after) in [
      ("identity-original", "identity-previous"),
      ("sha256:" + "d".repeat(64), "sha256:" + "a".repeat(64)),
      ("sha256:" + "e".repeat(64), "sha256:" + "a".repeat(64)),
      ("sha256:" + "f".repeat(64), "sha256:" + "a".repeat(64)),
      ("consumer-original", "producer-original"),
      ("workspace-original", "workspace-foreign"),
      ("site-original", "site-foreign"),
      ("sha256:" + "7".repeat(64), "sha256:" + "a".repeat(64)),
      ("\"siteGeneration\":4", "\"siteGeneration\":5"),
      ("\"installation\":\"local\"", "\"installation\":\"foreign\""),
      ("p_" + "b".repeat(32), "reviewer-original"),
    ] {
    assert_true(
      cloud_host_test_read(
        cloud_host_test_body().replace(old=before[:], new=after[:]),
        1001L,
      )
      is None,
    )
  }
}

///|
test "Host identity framing rejects additional permission or malformed body" {
  for
    body in [
      "{}",
      "not-json",
      cloud_host_test_body().replace(
        old="\"queryId\":",
        new="\"queryId\":\"duplicate\",\"queryId\":",
      ),
      cloud_host_test_body().replace(
        old="\"taskKey\":",
        new="\"permission\":\"allow\",\"taskKey\":",
      ),
      cloud_host_test_body().replace(
        old="\"taskKey\":",
        new="\"accountId\":\"original\",\"taskKey\":",
      ),
    ] {
    assert_true(cloud_host_test_read(body, 1001L) is None)
  }
}

///|
test "Host identity framing enforces timestamp Owner and trusted local lifetime" {
  for now in [-1L, 999L, 2000L, 9007199254740992L] {
    assert_true(cloud_host_test_read(cloud_host_test_body(), now) is None)
  }
  for
    (before, after) in [
      ("1970-01-01T00:00:02.000Z", "1970-01-01T00:00:03.000Z"),
      ("1970-01-01T00:00:01.000Z", "1970-02-30T00:00:01.000Z"),
      ("1970-01-01T00:00:01.000Z", "1970-01-01T00:00:01.002Z"),
      ("1970-01-01T00:00:01.000Z", "1970-01-01T00:00:02.000Z"),
    ] {
    assert_true(
      cloud_host_test_read(
        cloud_host_test_body().replace(old=before[:], new=after[:]),
        1001L,
      )
      is None,
    )
  }
}

///|
test "Host identity framing respects bounded decoder limits" {
  assert_true(
    cloud_host_identity_reply(
      @utf8.encode(cloud_host_test_body()),
      cloud_host_test_expected(),
      "identity-original",
      cloud_host_test_scope(),
      1001L,
      { max_wire_bytes: 1, max_nodes: 128, max_depth: 5, },
    )
    is None,
  )
  assert_true(
    cloud_host_identity_reply(
      @utf8.encode(cloud_host_test_body()),
      cloud_host_test_expected(),
      "identity-original",
      cloud_host_test_scope(),
      1001L,
      { max_wire_bytes: 65537, max_nodes: 128, max_depth: 5, },
    )
    is None,
  )
}
