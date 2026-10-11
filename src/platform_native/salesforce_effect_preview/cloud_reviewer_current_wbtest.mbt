///|
fn cloud_reviewer_test_scope() -> NativeEffectCloudReviewerScope {
  {
    site_key: "site-a",
    site_generation: 3L,
    workspace_id: "workspace-original",
    authority_scope_cid: "sha256:" + "1".repeat(64),
    installation: "local",
  }
}

///|
/// Same independent fixture as spec/fixtures/cloud-effect-reviewer-current.json
/// and the Cloud framing consumer; no live authority or HTTP is asserted.
fn cloud_reviewer_test_reply() -> String {
  (
    #|{"version":"actql-cloud-effect-resume-reviewer-current/0.1","siteKey":"site-a","siteGeneration":3,"current":{"version":"actql-cloud-effect-resume-current/0.1","queryId":"fresh-query","dispatchCid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","reportCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","claim":{"intentId":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","checkpointCid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","resolutionCid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","state":"claimed","generation":7,"claimant":"original-coordinator","leaseExpiresMs":2000,"mode":"resume"},"observedAt":"1970-01-01T00:00:01.000Z"},"reviewer":{"scheme":"ed25519-v1","checkpointCid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","installation":"local","workspaceId":"workspace-original","authorityScopeCid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","principalId":"original-person","reviewerId":"registered-signer","keyId":"original-key","publicKeyBase64":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","approvalAuthorityScopeCid":"sha256:5555555555555555555555555555555555555555555555555555555555555555","authorityContextCid":"sha256:6666666666666666666666666666666666666666666666666666666666666666","policyCid":"sha256:7777777777777777777777777777777777777777777777777777777777777777"}}
  )
}

///|
fn cloud_reviewer_test_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 128, max_depth: 5, }
}

///|
test "Cloud Reviewer private context keeps original principal distinct from signer and uses existing claim fence" {
  let snapshot = cloud_reviewer_reply(
    @utf8.encode(cloud_reviewer_test_reply()),
    cloud_resume_test_expected(),
    "fresh-query",
    cloud_reviewer_test_scope(),
    1001L,
    cloud_reviewer_test_limits(),
  ).unwrap()
  assert_eq(snapshot.registration.selection.principal_id, "original-person")
  assert_eq(snapshot.registration.reviewer_id, "registered-signer")
  assert_eq(snapshot.registration.key_id, "original-key")
  assert_eq(snapshot.observation.claim, cloud_resume_test_expected().claim)
  assert_eq(snapshot.observation.view.lease_expires_ms, 2000L)
  assert_eq(
    snapshot.registration.public_key_pem,
    "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n-----END PUBLIC KEY-----\n",
  )
}

///|
test "Cloud Reviewer private context refuses foreign Site workspace installation and expired or replayed claim" {
  let scope = cloud_reviewer_test_scope()
  for
    changed in [
      { ..scope, site_key: "foreign-site", },
      { ..scope, site_generation: 4L, },
      { ..scope, workspace_id: "foreign-workspace", },
      { ..scope, authority_scope_cid: "sha256:" + "f".repeat(64), },
      { ..scope, installation: "preview:other", },
    ] {
    assert_true(
      cloud_reviewer_reply(
        @utf8.encode(cloud_reviewer_test_reply()),
        cloud_resume_test_expected(),
        "fresh-query",
        changed,
        1001L,
        cloud_reviewer_test_limits(),
      )
      is None,
    )
  }
  for now in [-1L, 2000L, 9007199254740992L] {
    assert_true(
      cloud_reviewer_reply(
        @utf8.encode(cloud_reviewer_test_reply()),
        cloud_resume_test_expected(),
        "fresh-query",
        scope,
        now,
        cloud_reviewer_test_limits(),
      )
      is None,
    )
  }
  assert_true(
    cloud_reviewer_reply(
      @utf8.encode(cloud_reviewer_test_reply()),
      cloud_resume_test_expected(),
      "old-query",
      scope,
      1001L,
      cloud_reviewer_test_limits(),
    )
    is None,
  )
}

///|
test "Cloud Reviewer private context rejects missing duplicate or secret-bearing fields before any verification" {
  let body = cloud_reviewer_test_reply()
  for
    changed in [
      "{}",
      body.replace(old="\"scheme\":\"ed25519-v1\"", new="\"scheme\":\"none\""),
      body.replace(
        old="\"principalId\":\"original-person\"",
        new="\"principalId\":\"\"",
      ),
      body.replace(old="\"keyId\":", new="\"keyId\":\"duplicate\",\"keyId\":"),
      body.replace(
        old="\"reviewer\":",
        new="\"approvalToken\":true,\"reviewer\":",
      ),
      body.replace(
        old="\"policyCid\":",
        new="\"privateKey\":true,\"policyCid\":",
      ),
      body.replace(
        old="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        new="invalid-key",
      ),
    ] {
    assert_true(
      cloud_reviewer_reply(
        @utf8.encode(changed),
        cloud_resume_test_expected(),
        "fresh-query",
        cloud_reviewer_test_scope(),
        1001L,
        cloud_reviewer_test_limits(),
      )
      is None,
    )
  }
  assert_true(
    cloud_reviewer_reply(
      @utf8.encode(body),
      cloud_resume_test_expected(),
      "fresh-query",
      cloud_reviewer_test_scope(),
      1001L,
      { max_wire_bytes: 16, max_nodes: 128, max_depth: 5, },
    )
    is None,
  )
}
