///|
fn operational_test_request() -> PolicyRequest {
  {
    version: "actql-placement-policy/0.1",
    request_id: "request",
    run_identity: "run",
    authority: "authority",
    candidate_set_cid: "snapshot",
    generation: 0,
    revision: 1,
    deadline_ms: 2000L,
  }
}

///|
fn operational_test_body() -> String {
  let binding = placement_policy_request_json(operational_test_request()).unwrap()
  "{\"version\":\"actql-operational-estimate/0.1\",\"binding\":" +
  binding +
  ",\"profile_revision\":\"profile\",\"candidate_snapshot_cid\":\"snapshot\",\"conditions\":{\"host\":\"native\",\"realization\":\"resident\",\"captureMode\":\"metadata-only\",\"runtimeRevision\":\"r\",\"binaryDigest\":\"b\",\"inputDigest\":\"i\",\"programDigest\":\"p\",\"inputRows\":1000,\"schemaLayout\":\"text-1024\",\"limitsDigest\":\"l\",\"instrumentationRevision\":\"o\",\"measurementScopeRevision\":\"m\",\"environmentDigest\":\"e\",\"controlDigest\":\"c\",\"concurrency\":1,\"processState\":\"new-process-and-environment\",\"osCache\":\"uncontrolled\",\"authorizedScope\":\"local\"},\"oldest_ms\":\"1000\",\"newest_ms\":\"1000\",\"max_age_ms\":\"500\",\"capture_ms\":1,\"overhead\":\"unknown-no-off-comparison\",\"entries\":[{\"position\":0,\"task\":1,\"quantity\":\"task-processing\",\"status\":\"reference\",\"reason\":\"\",\"median_ms\":2,\"minimum_ms\":1,\"maximum_ms\":3,\"sample_count\":3}]}"
}

///|
fn operational_test_admit(
  body : String,
  now : Int64,
) -> Result[OperationalEstimateSidecar, SearchIssue] {
  admit_operational_estimate_sidecar_json(
    body,
    operational_test_request(),
    {
      cid: "snapshot",
      canonical_json: "[\"actql-policy-candidates/0.1\",\"program\",0,1,true,[[0,1,0,1,1,[null,[\"offer\"]]]]]",
    },
    "configured-local-profile-producer",
    "profile",
    now,
  )
}

///|
test "operational reference is bounded and fresh without predicting whole Run latency" {
  let admitted = operational_test_admit(operational_test_body(), 1100L).unwrap()
  assert_eq(admitted.references[0].median_ms, Some(2.0))
  assert_eq(admitted.references[0].sample_count, 3)
  assert_eq(admitted.capture_ms, Some(1.0))
  assert_true(operational_test_admit(operational_test_body(), 2001L) is Err(_))
  assert_eq(
    operational_test_admit(operational_test_body(), 1600L).unwrap().references[0].unknown_reason,
    Some("freshness-insufficient"),
  )
  assert_eq(
    operational_test_admit(operational_test_body(), 999L).unwrap().references[0].median_ms,
    None,
  )
}

///|
test "operational sidecar rejects binding changes and closed schema violations" {
  let body = operational_test_body()
  for
    (old, new) in [
      ("\"request\"", "\"other\""),
      ("\"run\"", "\"other\""),
      ("\"authority\":\"authority\"", "\"authority\":\"other\""),
      ("\"generation\":0", "\"generation\":1"),
      ("\"revision\":1", "\"revision\":2"),
      ("\"2000\"", "\"2001\""),
      ("\"candidate_set_cid\":\"snapshot\"", "\"candidate_set_cid\":\"other\""),
      ("\"profile_revision\":\"profile\"", "\"profile_revision\":\"other\""),
      ("\"position\":0", "\"position\":1"),
      ("\"task\":1", "\"task\":0"),
      ("\"sample_count\":3", "\"sample_count\":2"),
      ("\"median_ms\":2", "\"median_ms\":4"),
      ("\"capture_ms\":1", "\"capture_ms\":1,\"issuer\":\"trusted\""),
    ] {
    assert_true(
      operational_test_admit(body.replace(old~, new~), 1100L) is Err(_),
    )
  }
  assert_true(operational_test_admit(body.repeat(100), 1100L) is Err(_))
}

///|
test "operational missing phase and unsupported diagnostics stay explicit" {
  let off = operational_test_body().replace(old="metadata-only", new="off")
  assert_eq(
    operational_test_admit(off, 1100L).unwrap().references[0].unknown_reason,
    Some("physical-phase-observer-off"),
  )
  let unknown = operational_test_body()
    .replace(old="\"reference\"", new="\"unknown\"")
    .replace(old="\"reason\":\"\"", new="\"reason\":\"quantity-unobserved\"")
    .replace(old="\"median_ms\":2", new="\"median_ms\":null")
    .replace(old="\"minimum_ms\":1", new="\"minimum_ms\":null")
    .replace(old="\"maximum_ms\":3", new="\"maximum_ms\":null")
  assert_eq(
    operational_test_admit(unknown, 1100L).unwrap().references[0].unknown_reason,
    Some("quantity-unobserved"),
  )
  assert_true(
    operational_test_admit(
      unknown.replace(old="quantity-unobserved", new="arbitrary-message"),
      1100L,
    )
    is Err(_),
  )
}

///|
test "operational whole caller reference retains its quantity without granting prediction" {
  let whole = operational_test_body().replace(
    old="task-processing",
    new="run-caller-elapsed",
  )
  let reference = operational_test_admit(whole, 1100L).unwrap().references[0]
  assert_eq(reference.quantity, "run-caller-elapsed")
  assert_eq(reference.median_ms, Some(2.0))
  assert_eq(reference.sample_count, 3)
  assert_true(
    operational_test_admit(
      whole.replace(old="run-caller-elapsed", new="predicted-eta"),
      1100L,
    )
    is Err(_),
  )
  assert_eq(
    operational_test_admit(whole, 1600L).unwrap().references[0].unknown_reason,
    Some("freshness-insufficient"),
  )
}
