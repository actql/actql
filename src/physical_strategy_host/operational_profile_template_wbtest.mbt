///|
fn template_test_body() -> String {
  let binding = placement_policy_request_json(operational_test_request()).unwrap()
  operational_test_body().replace(old="\"binding\":" + binding + ",", new="")
}

///|
test "immutable profile template retains actual condition fields and binds only a current request" {
  let template = template_test_body()
  let header = operational_profile_template_header(template).unwrap()
  assert_eq(header.conditions.input_digest, "i")
  assert_eq(header.conditions.input_rows, 1000)
  assert_eq(header.conditions.capture_mode, "metadata-only")
  assert_eq(header.conditions.program_digest, "p")
  let body = bind_operational_profile_template(
    template,
    operational_test_request(),
  ).unwrap()
  assert_eq(
    operational_test_admit(body, 1100L).unwrap().conditions,
    header.conditions,
  )
  assert_eq(
    operational_estimate_conditions_json(header.conditions)
    .unwrap()
    .contains("\"inputDigest\":\"i\""),
    true,
  )
  assert_eq(template, template_test_body())
  let changed = { ..operational_test_request(), generation: 9, }
  let changed_body = bind_operational_profile_template(template, changed).unwrap()
  assert_true(operational_test_admit(changed_body, 1100L) is Err(_))
}

///|
test "template rejects unknown fields duplicate entries and malformed references" {
  for
    (old, new) in [
      ("\"capture_ms\":1", "\"capture_ms\":1,\"issuer\":\"self\""),
      ("\"sample_count\":3", "\"sample_count\":2"),
      ("\"inputRows\":1000", "\"inputRows\":0"),
      ("\"oldest_ms\":\"1000\"", "\"oldest_ms\":\"1001\""),
      ("\"max_age_ms\":\"500\"", "\"max_age_ms\":\"86400001\""),
      ("\"concurrency\":1", "\"concurrency\":2"),
    ] {
    assert_true(
      operational_profile_template_header(
        template_test_body().replace(old~, new~),
      )
      is Err(_),
    )
  }
  assert_true(
    operational_profile_template_header(template_test_body().repeat(100))
    is Err(_),
  )
}

///|
fn trajectory_test_candidates(
  first : Int,
  second : Int,
  other? : Bool = false,
) -> PolicyCandidateSet {
  let first_offer = "[1,\"a\",0,0,0,0,0,0,0,null]"
  let second_offer = if other {
    "[2,\"other\",0,0,0,0,0,0,0,null]"
  } else {
    "[2,\"b\",0,0,0,0,0,0,0,{}]"
  }
  {
    cid: "trajectory",
    canonical_json: "[\"actql-policy-candidates/0.1\",\"program\",0,1,true,[[" +
    first.to_string() +
    ",1,0,1,1,[null," +
    first_offer +
    "," +
    second_offer +
    "]],[" +
    second.to_string() +
    ",1,0,1,1,[null," +
    first_offer +
    "," +
    second_offer +
    "]]]]",
  }
}

///|
test "assignment correspondence uses current residual positions not remembered position numbers" {
  let original = trajectory_test_candidates(7, 9)
  let trajectory = operational_candidate_trajectory(original, 7).unwrap()
  assert_eq(
    operational_residual_position(
      trajectory_test_candidates(42, 11),
      trajectory,
      2,
    ).unwrap(),
    Some(11),
  )
  assert_eq(
    operational_residual_position(
      trajectory_test_candidates(42, 11, other=true),
      trajectory,
      2,
    ).unwrap(),
    None,
  )
  assert_true(operational_candidate_trajectory(original, 0) is Err(_))
  assert_true(operational_residual_position(original, trajectory, 0) is Err(_))
  assert_true(operational_residual_position(original, trajectory, 3) is Err(_))
}
