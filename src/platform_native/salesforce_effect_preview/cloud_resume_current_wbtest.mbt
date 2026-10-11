///|
fn cloud_resume_test_expected() -> CloudResumeExpected {
  {
    dispatch_cid: "sha256:" + "a".repeat(64),
    report_cid: "sha256:" + "b".repeat(64),
    checkpoint_cid: "sha256:" + "c".repeat(64),
    resolution_cid: "sha256:" + "d".repeat(64),
    intent_id: "sha256:" + "e".repeat(64),
    claim: { claimant: "original-coordinator", generation: 7L, },
  }
}

///|
fn cloud_resume_test_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 64, max_depth: 4, }
}

///|
/// Authored private codec fixture only: this does not establish original
/// Review/ACK/Host authentication, an HTTP read or execution permission.
fn cloud_resume_test_reply() -> String {
  (
    #|{"version":"actql-cloud-effect-resume-current/0.1","queryId":"fresh-query","dispatchCid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","reportCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","claim":{"intentId":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","checkpointCid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","resolutionCid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","state":"claimed","generation":7,"claimant":"original-coordinator","leaseExpiresMs":2000,"mode":"resume"},"observedAt":"1970-01-01T00:00:01.000Z"}
  )
}

///|
test "Cloud Resume private reply uses the independently returned view and caller clock" {
  let expected = cloud_resume_test_expected()
  let observed = cloud_resume_reply(
    @utf8.encode(cloud_resume_test_reply()),
    expected,
    "fresh-query",
    1001L,
    cloud_resume_test_limits(),
  ).unwrap()
  assert_eq(observed.claim, expected.claim)
  assert_eq(observed.view.lease_expires_ms, 2000L)
  assert_eq(observed.now_ms, 1001L)
  assert_eq(
    @checkpoint.decide_resume_fence(
      observed.view,
      observed.claim,
      observed.now_ms,
    ),
    @checkpoint.FenceCurrent,
  )
  assert_true(!observed.settlement_only)
}

///|
test "Cloud Resume private reply refuses each foreign original identity and old challenge" {
  let expected = cloud_resume_test_expected()
  let c = "sha256:" + "f".repeat(64)
  for
    changed in [
      { ..expected, dispatch_cid: c, },
      { ..expected, report_cid: c, },
      { ..expected, checkpoint_cid: c, },
      { ..expected, resolution_cid: c, },
      { ..expected, intent_id: c, },
      {
        ..expected,
        claim: { claimant: "another-coordinator", generation: 7L, },
      },
      {
        ..expected,
        claim: { claimant: "original-coordinator", generation: 8L, },
      },
    ] {
    assert_true(
      cloud_resume_reply(
        @utf8.encode(cloud_resume_test_reply()),
        changed,
        "fresh-query",
        1000L,
        cloud_resume_test_limits(),
      )
      is None,
    )
  }
  assert_true(
    cloud_resume_reply(
      @utf8.encode(cloud_resume_test_reply()),
      expected,
      "next-query",
      1000L,
      cloud_resume_test_limits(),
    )
    is None,
  )
}

///|
test "Cloud Resume private reply refuses expired lease and invalid local time" {
  for now in [-1L, 2000L, 2001L, 9007199254740992L] {
    assert_true(
      cloud_resume_reply(
        @utf8.encode(cloud_resume_test_reply()),
        cloud_resume_test_expected(),
        "fresh-query",
        now,
        cloud_resume_test_limits(),
      )
      is None,
    )
  }
}

///|
test "Cloud Resume private reply rejects incomplete duplicate and excess fields under original bounds" {
  let body = cloud_resume_test_reply()
  for
    changed in [
      "{}",
      body.replace(
        old="\"mode\":\"resume\"",
        new="\"mode\":\"settlement_only\"",
      ),
      body.replace(old="\"state\":\"claimed\"", new="\"state\":\"completed\""),
      body.replace(old="\"generation\":7", new="\"generation\":7.5"),
      body.replace(
        old="\"generation\":7",
        new="\"generation\":7,\"generation\":7",
      ),
      body.replace(old="\"claim\":", new="\"authority\":true,\"claim\":"),
      body.replace(
        old="\"mode\":\"resume\"",
        new="\"extra\":true,\"mode\":\"resume\"",
      ),
    ] {
    assert_true(
      cloud_resume_reply(
        @utf8.encode(changed),
        cloud_resume_test_expected(),
        "fresh-query",
        1000L,
        cloud_resume_test_limits(),
      )
      is None,
    )
  }
  let invalid_limits : Array[@checkpoint.WireLimits] = [
    { max_wire_bytes: 16, max_nodes: 64, max_depth: 4, },
    { max_wire_bytes: 65536, max_nodes: 2, max_depth: 4, },
    { max_wire_bytes: 65536, max_nodes: 64, max_depth: 1, },
  ]
  for limits in invalid_limits {
    assert_true(
      cloud_resume_reply(
        @utf8.encode(body),
        cloud_resume_test_expected(),
        "fresh-query",
        1000L,
        limits,
      )
      is None,
    )
  }
}

///|
test "Cloud Resume query preserves opaque labels and numeric original generation without authority" {
  let expected = cloud_resume_test_expected()
  let query = cloud_resume_query_body(
    expected,
    "e\u{301}\r\n",
    cloud_resume_test_limits(),
  )
  assert_eq(query, None)
  let body = cloud_resume_query_body(
    expected,
    "e\u{301}",
    cloud_resume_test_limits(),
  ).unwrap()
  let node = @source.parse_json_bytes_preserving(body, {
    max_input_bytes: 65536,
    max_nodes: 64,
    max_depth: 4,
  }).unwrap()
  let root = @decode.admit(node, {
    max_nodes: 64,
    max_depth: 4,
    max_string_bytes: 65536,
    max_total_string_bytes: 65536,
  }).unwrap()
  let fields = @decode.closed_object(root, [
    "version", "queryId", "dispatchCid", "reportCid", "checkpointCid", "resolutionCid",
    "intentId", "claimant", "generation",
  ]).unwrap()
  assert_eq(
    @decode.text(@decode.required(fields, "queryId").unwrap()).unwrap(),
    "e\u{301}",
  )
  assert_eq(
    @decode.safe_integer(@decode.required(fields, "generation").unwrap()).unwrap(),
    7L,
  )
  assert_true(@decode.lookup(fields, "authority") is None)
  assert_true(@decode.lookup(fields, "resolutionWire") is None)
  for label in ["", "x".repeat(257), "x\u{7f}"] {
    assert_eq(
      cloud_resume_query_body(expected, label, cloud_resume_test_limits()),
      None,
    )
  }
  assert_eq(
    cloud_resume_query_body(
      {
        ..expected,
        claim: {
          claimant: "original-coordinator",
          generation: 9007199254740992L,
        },
      },
      "fresh-query",
      cloud_resume_test_limits(),
    ),
    None,
  )
}
