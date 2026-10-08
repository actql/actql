///|
test "profile configuration does not read and bounds trusted configuration" {
  let profile = prepare_native_local_performance_profile(
    "/does-not-exist",
    "profile.json",
    "0".repeat(64),
    "revision",
    creation_ms=1.0,
  ).unwrap()
  assert_eq(profile.attempted, false)
  assert_true(profile.template is None)
  assert_true(
    prepare_native_local_performance_profile(
      "",
      "profile.json",
      "0".repeat(64),
      "r",
    )
    is Err(_),
  )
  assert_true(
    prepare_native_local_performance_profile(
      "/tmp", "profile.json", "invalid", "r",
    )
    is Err(_),
  )
  assert_true(
    prepare_native_local_performance_profile(
      "/tmp",
      "profile.json",
      "0".repeat(64),
      "r",
      creation_ms=-1.0,
    )
    is Err(_),
  )
}

///|
test "optional diagnostic serialization failure has no side effects" {
  let reference : NativePerformanceDecision = {
    task: 1,
    positions: [7],
    evaluated_ms: 1000L,
    max_age_ms: None,
    mode: DiagnosticReference,
    objective: "descriptive-run-caller-elapsed",
    request: {
      version: "actql-placement-policy/0.1",
      request_id: "r",
      run_identity: "run",
      authority: "a",
      candidate_set_cid: "snapshot",
      generation: 0,
      revision: 1,
      deadline_ms: 2000L,
    },
    profile_revision: None,
    reason: "profile-not-configured",
    selected_position: None,
    offline_position: Some(7),
    conditions: None,
    references: [],
    profile_creation_ms: None,
    profile_read_microseconds: 0.0,
    consultation_microseconds: 1.0,
    reused_profile: false,
    oldest_ms: None,
    newest_ms: None,
    load_applicability: "unknown-uncontrolled",
    stable_improvement: "unknown",
    net_benefit: "unknown",
  }
  assert_true(
    native_performance_decision_json(reference, max_bytes=1) is Err(_),
  )
  let wire = native_performance_decision_json(reference).unwrap()
  assert_true(wire.contains("\"plan_changed\":false"))
  assert_true(wire.contains("\"calibrated_eta_ms\":null"))
  assert_true(wire.contains("\"net_benefit\":\"unknown\""))
  assert_eq(reference.selected_position, None)
}
