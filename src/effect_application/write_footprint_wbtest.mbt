///|
fn footprint_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn footprint(
  effect_id : String,
  kind : EffectFootprintKind,
  boundary : String,
  scheme : String,
  targets : Array[String],
) -> EffectMemberFootprint {
  {
    effect_id,
    kind,
    provider_namespace: "salesforce-org",
    provider_boundary_cid: boundary,
    resource_identity_scheme_cid: scheme,
    resource_kind: "Record",
    provider_object_identity_cids: targets,
  }
}

///|
test "Effect Set admits disjoint exact targets in one provider boundary" {
  let members = [
    footprint(
      "first",
      ExactTargets,
      footprint_test_cid("a"),
      footprint_test_cid("b"),
      [footprint_test_cid("1")],
    ),
    footprint(
      "second",
      ExactTargets,
      footprint_test_cid("a"),
      footprint_test_cid("b"),
      [footprint_test_cid("2")],
    ),
  ]
  assert_true(check_effect_set_footprint_conflicts(members, 2, 2, 16) is Ok(_))
}

///|
test "Effect Set rejects overlap before any member can dispatch" {
  let members = [
    footprint(
      "first",
      ExactTargets,
      footprint_test_cid("a"),
      footprint_test_cid("b"),
      [footprint_test_cid("1")],
    ),
    footprint(
      "second",
      ExactTargets,
      footprint_test_cid("a"),
      footprint_test_cid("b"),
      [footprint_test_cid("1")],
    ),
  ]
  assert_true(
    check_effect_set_footprint_conflicts(members, 2, 2, 16)
    is Err(OverlappingTarget),
  )
  members[1] = footprint(
    "second",
    ExactTargets,
    footprint_test_cid("a"),
    footprint_test_cid("c"),
    [footprint_test_cid("2")],
  )
  assert_true(
    check_effect_set_footprint_conflicts(members, 2, 2, 16)
    is Err(UnprovenIndependence),
  )
}

///|
test "unproved collection or opaque independence cannot dispatch" {
  let members = [
    footprint(
      "create",
      Collection,
      footprint_test_cid("a"),
      footprint_test_cid("b"),
      [],
    ),
    footprint(
      "update",
      ExactTargets,
      footprint_test_cid("a"),
      footprint_test_cid("b"),
      [footprint_test_cid("1")],
    ),
  ]
  assert_true(
    check_effect_set_footprint_conflicts(members, 2, 1, 16)
    is Err(UnprovenIndependence),
  )
  members[0] = footprint(
    "command",
    Opaque,
    footprint_test_cid("a"),
    footprint_test_cid("b"),
    [],
  )
  assert_true(
    check_effect_set_footprint_conflicts(members, 2, 1, 16)
    is Err(UnprovenIndependence),
  )
  members[1] = footprint(
    "update",
    ExactTargets,
    footprint_test_cid("c"),
    footprint_test_cid("b"),
    [footprint_test_cid("1")],
  )
  assert_true(check_effect_set_footprint_conflicts(members, 2, 1, 16) is Ok(_))
}

///|
test "Effect Set footprint scan is bounded and validates every target" {
  let members = [
    footprint(
      "first",
      ExactTargets,
      footprint_test_cid("a"),
      footprint_test_cid("b"),
      [footprint_test_cid("1"), footprint_test_cid("1")],
    ),
  ]
  assert_true(
    check_effect_set_footprint_conflicts(members, 1, 2, 16)
    is Err(OverlappingTarget),
  )
  members[0] = footprint(
    "first",
    ExactTargets,
    footprint_test_cid("a"),
    footprint_test_cid("b"),
    [footprint_test_cid("1")],
  )
  assert_true(
    check_effect_set_footprint_conflicts(members, 1, 1, 1)
    is Err(CapacityExceeded),
  )
  assert_true(
    check_effect_set_footprint_conflicts(members, 1, 0, 16)
    is Err(CapacityExceeded),
  )
}
