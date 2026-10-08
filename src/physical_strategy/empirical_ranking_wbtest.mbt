///|
fn empirical_test_candidates(single? : Bool = false) -> PolicyCandidateSet {
  {
    cid: "snapshot",
    canonical_json: if single {
      "[\"actql-policy-candidates/0.1\",\"program\",0,1,true,[[0,1,0,1,1,[null,[\"offer\"]]]]]"
    } else {
      "[\"actql-policy-candidates/0.1\",\"program\",0,1,true,[[7,1,0,1,1,[null,[\"offer\"]]],[0,1,0,1,1,[null,[\"offer\"]]]]]"
    },
  }
}

///|
fn empirical_test_sidecar() -> OperationalEstimateSidecar {
  {
    request: operational_test_request(),
    conditions: operational_test_admit(operational_test_body(), 1100L).unwrap().conditions,
    profile_revision: "profile",
    oldest_ms: 1000L,
    newest_ms: 1000L,
    max_age_ms: 500L,
    capture_ms: Some(1.0),
    references: [7, 0].map(position => {
      position,
      task: 1,
      quantity: "task-processing",
      median_ms: Some(if position == 7 { 1.0 } else { 2.0 }),
      minimum_ms: Some(1.0),
      maximum_ms: Some(3.0),
      sample_count: 3,
      unknown_reason: None,
    }),
  }
}

///|
test "empirical ranking compares every presented assignment and preserves closed policy wire" {
  let sidecar = empirical_test_sidecar()
  let ranking = rank_operational_candidates(
    empirical_test_candidates(),
    sidecar,
    1,
    "policy",
    1100L,
  ).unwrap()
  assert_eq(ranking.selected_position, Some(7))
  assert_eq(ranking.positions, [7, 0])
  let response : PolicyResponse = {
    request: sidecar.request,
    position: 7,
    policy_id: "local",
    policy_revision: ranking.policy_revision,
    explanation: "first-task-processing only",
  }
  let wire = placement_policy_response_json(response).unwrap()
  assert_eq(
    admit_placement_policy_response_json(wire, sidecar.request, "local").unwrap(),
    response,
  )
  assert_true(!wire.contains("median_ms"))
  assert_true(
    admit_placement_policy_response_json(
      wire,
      { ..sidecar.request, revision: 2, },
      "local",
    )
    is Err(_),
  )
  let equal = {
    ..sidecar,
    references: sidecar.references.map(r => { ..r, median_ms: Some(1.0), }),
  }
  assert_eq(
    rank_operational_candidates(
      empirical_test_candidates(),
      equal,
      1,
      "policy",
      1100L,
    ).unwrap().selected_position,
    Some(0),
  )
}

///|
test "one or partly unknown candidate set cannot claim an empirical ranking" {
  let sidecar = empirical_test_sidecar()
  assert_eq(
    rank_operational_candidates(
      empirical_test_candidates(single=true),
      sidecar,
      1,
      "policy",
      1100L,
    ).unwrap().reason,
    "single-candidate",
  )
  for
    references in [
      [],
      [sidecar.references[0]],
      sidecar.references.map(r => {
        ..r,
        median_ms: if r.position == 0 {
          None
        } else {
          r.median_ms
        },
        unknown_reason: if r.position == 0 {
          Some("conditions-mismatch")
        } else {
          None
        },
      }),
      sidecar.references.map(r => {
        ..r,
        median_ms: None,
        unknown_reason: Some("samples-insufficient"),
      }),
    ] {
    let ranking = rank_operational_candidates(
      empirical_test_candidates(),
      { ..sidecar, references, },
      1,
      "policy",
      1100L,
    ).unwrap()
    assert_eq(ranking.selected_position, None)
    assert_eq(ranking.positions.length(), 2)
    assert_eq(ranking.reason, "incomplete-reference")
  }
  assert_eq(
    rank_operational_candidates(
      empirical_test_candidates(),
      sidecar,
      1,
      "policy",
      1600L,
    ).unwrap().reason,
    "freshness-insufficient",
  )
  assert_true(
    rank_operational_candidates(
      empirical_test_candidates(),
      sidecar,
      1,
      "policy",
      2001L,
    )
    is Err(_),
  )
  assert_true(
    rank_operational_candidates(
      { ..empirical_test_candidates(), cid: "other", },
      sidecar,
      1,
      "policy",
      1100L,
    )
    is Err(_),
  )
}

///|
test "whole caller elapsed references cannot silently borrow task processing" {
  let sidecar = empirical_test_sidecar()
  assert_eq(
    rank_operational_candidates(
      empirical_test_candidates(),
      sidecar,
      1,
      "whole-run",
      1100L,
      quantity="run-caller-elapsed",
    ).unwrap().selected_position,
    None,
  )
  let whole = {
    ..sidecar,
    references: sidecar.references.map(r => {
      ..r,
      quantity: "run-caller-elapsed",
    }),
  }
  let ranking = rank_operational_candidates(
    empirical_test_candidates(),
    whole,
    1,
    "whole-run",
    1100L,
    quantity="run-caller-elapsed",
  ).unwrap()
  assert_eq(ranking.selected_position, Some(7))
  assert_eq(ranking.reason, "run-caller-elapsed-median")
  assert_eq(
    rank_operational_candidates(
      empirical_test_candidates(),
      whole,
      1,
      "whole-run",
      1100L,
    ).unwrap().selected_position,
    None,
  )
}
