///|
let authority = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

///|
let request = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

///|
fn customer(workspace : String, destination : String) -> ObservationScope {
  admit_observation_scope(
    workspace,
    authority,
    destination,
    "metadata-only.1",
    CustomerTelemetry,
  ).unwrap()
}

///|
test "pre-Run request custody needs no invented Program or Run CID" {
  let scope = customer("ws_a", "collector.1")
  let original_request = "request-4ff44bd7-5e81-4069-94f6-2346c9b7649d"
  let budget = open_observation_budget(
    scope,
    original_request,
    1,
    4,
    true,
    None,
  ).unwrap()
  assert_eq(
    charge_observation(
      budget,
      scope,
      original_request,
      Some("check;rejected"),
      4,
    ),
    Ok(ObservationCharged),
  )
  assert_eq(observation_budget_snapshot(budget).request_key, original_request)
}

///|
test "scope binds Workspace authority destination disclosure and purpose" {
  let scope = customer("ws_a", "collector.1")
  assert_eq(
    observation_scope_key(scope),
    "ws_a|" + authority + "|collector.1|metadata-only.1|customer_telemetry",
  )
  assert_false(scope == customer("ws_b", "collector.1"))
  assert_false(scope == customer("ws_a", "collector.2"))
  assert_false(
    scope ==
    admit_observation_scope(
      "ws_a",
      authority,
      "collector.1",
      "metadata-only.2",
      CustomerTelemetry,
    ).unwrap(),
  )
  assert_false(
    scope ==
    admit_observation_scope(
      "ws_a",
      authority,
      "collector.1",
      "metadata-only.1",
      ServiceOperations,
    ).unwrap(),
  )
  assert_true(
    admit_observation_scope(
      "ws_a|ws_b",
      authority,
      "collector.1",
      "metadata-only.1",
      CustomerTelemetry,
    ) ==
    None,
  )
}

///|
test "exact count and bytes are cumulative across restored observation" {
  let scope = customer("ws_a", "collector.1")
  let budget = open_observation_budget(scope, request, 2, 8, true, None).unwrap()
  assert_eq(
    charge_observation(budget, scope, request, Some("task:0;1"), 3),
    Ok(ObservationCharged),
  )
  let saved = observation_budget_snapshot(budget)
  assert_eq(saved.records, 1)
  assert_eq(saved.bytes, 3)
  let restored = open_observation_budget(
    scope,
    request,
    2,
    8,
    false,
    Some(saved),
  ).unwrap()
  assert_eq(
    charge_observation(restored, scope, request, Some("task:1;1"), 5),
    Ok(ObservationCharged),
  )
  assert_eq(observation_budget_snapshot(restored).records, 2)
  assert_eq(observation_budget_snapshot(restored).bytes, 8)
  assert_eq(
    charge_observation(restored, scope, request, Some("task:1;2"), 1),
    Err(ObservationRunLimit),
  )
  assert_eq(observation_budget_snapshot(restored).bytes, 8)
}

///|
test "one-short bytes rejects before modifying consumption" {
  let scope = customer("ws_a", "collector.1")
  let budget = open_observation_budget(scope, request, 2, 7, true, None).unwrap()
  assert_eq(
    charge_observation(budget, scope, request, None, 3),
    Ok(ObservationCharged),
  )
  assert_eq(
    charge_observation(budget, scope, request, None, 5),
    Err(ObservationRunLimit),
  )
  assert_eq(observation_budget_snapshot(budget).records, 1)
  assert_eq(observation_budget_snapshot(budget).bytes, 3)
}

///|
test "missing damaged and foreign custody never replenishes a Run" {
  let scope = customer("ws_a", "collector.1")
  assert_true(
    open_observation_budget(scope, request, 2, 8, false, None)
    is Err(ObservationBudgetUnavailable),
  )
  let budget = open_observation_budget(scope, request, 2, 8, true, None).unwrap()
  let saved = observation_budget_snapshot(budget)
  assert_true(
    open_observation_budget(
      customer("ws_b", "collector.1"),
      request,
      2,
      8,
      false,
      Some(saved),
    )
    is Err(ForeignObservationCustody),
  )
  assert_true(
    open_observation_budget(
      customer("ws_a", "collector.2"),
      request,
      2,
      8,
      false,
      Some(saved),
    )
    is Err(ForeignObservationCustody),
  )
  assert_true(
    open_observation_budget(scope, authority, 2, 8, false, Some(saved))
    is Err(ForeignObservationCustody),
  )
  assert_true(
    open_observation_budget(scope, request, 2, 8, true, Some(saved))
    is Err(ForeignObservationCustody),
  )
  assert_true(
    open_observation_budget(scope, request, 2, 9, false, Some(saved))
    is Err(ForeignObservationCustody),
  )
  let damaged = { ..saved, bytes: 1, }
  assert_true(
    open_observation_budget(scope, request, 2, 8, false, Some(damaged))
    is Err(ObservationBudgetUnavailable),
  )
}

///|
test "repeated verified fact remains suppressed after restart and exhaustion" {
  let scope = customer("ws_a", "collector.1")
  let budget = open_observation_budget(scope, request, 1, 4, true, None).unwrap()
  assert_eq(
    charge_observation(budget, scope, request, Some("run;9;1;0"), 4),
    Ok(ObservationCharged),
  )
  let saved = observation_budget_snapshot(budget)
  let restored = open_observation_budget(
    scope,
    request,
    1,
    4,
    false,
    Some(saved),
  ).unwrap()
  assert_eq(
    charge_observation(restored, scope, request, Some("run;9;1;0"), 4),
    Ok(ObservationRepeated),
  )
  assert_eq(observation_budget_snapshot(restored), saved)
  assert_eq(
    charge_observation(restored, scope, request, Some("run;9;0;1"), 4),
    Err(ObservationRunLimit),
  )
}

///|
test "foreign charge and oversized record preserve the original budget" {
  let scope = customer("ws_a", "collector.1")
  let budget = open_observation_budget(scope, request, 2, 8, true, None).unwrap()
  assert_eq(
    charge_observation(
      budget,
      customer("ws_b", "collector.1"),
      request,
      None,
      1,
    ),
    Err(ForeignObservationCustody),
  )
  assert_eq(
    charge_observation(budget, scope, authority, None, 1),
    Err(ForeignObservationCustody),
  )
  assert_eq(
    charge_observation(budget, scope, request, None, 4097),
    Err(ObservationRecordLimit),
  )
  assert_eq(observation_budget_snapshot(budget).records, 0)
}
