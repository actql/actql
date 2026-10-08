///|
fn hold_lifecycle_fixture(
  revision : Int,
  phase : Int,
  owners : Int,
) -> (RemoteBundleRecord, RemoteBundleHoldBinding) {
  let manifest = prepare_bundle_manifest(
    "issuer-a",
    "bundle-a",
    "revision-a",
    "target-a",
    hold_fixture_cid_a(),
    1L,
    "connector-a",
    "connector/0.1",
    "strategy/0.1",
  ).unwrap()
  let member = bundle_manifest_identity(manifest)
  let scope = hold_fixture_scope(
    distribution=prepare_bundle_distribution([member]).unwrap(),
    member~,
  )
  let binding = prepare_bundle_hold_binding_from_scope(
    scope,
    hold_fixture_catalog(),
    11,
  ).unwrap()
  (restore_bundle_record(manifest, revision, phase, owners).unwrap(), binding)
}

///|
test "bundle hold observations distinguish exact retained fenced unresolved and unavailable" {
  let (record, binding) = hold_lifecycle_fixture(11, 1, 0)
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(record), binding, false),
    BundleHoldUnresolved,
  )
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(record), binding, true),
    BundleHoldUnavailable,
  )
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), None, binding, false),
    BundleHoldUnavailable,
  )
  assert_eq(
    observe_bundle_hold(
      "123e4567-e89b-42d3-a456-426614174001",
      Some(record),
      binding,
      false,
    ),
    BundleHoldUnavailable,
  )
  let (regressed, _) = hold_lifecycle_fixture(10, 1, 0)
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(regressed), binding, false),
    BundleHoldUnavailable,
  )
  let (advanced, _) = hold_lifecycle_fixture(12, 1, 1)
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(advanced), binding, false),
    BundleHoldFenced,
  )
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(advanced), binding, true),
    BundleHoldRetained,
  )
  let (draining, _) = hold_lifecycle_fixture(13, 2, 1)
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(draining), binding, true),
    BundleHoldRetained,
  )
  let (empty, _) = hold_lifecycle_fixture(12, 1, 0)
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(empty), binding, true),
    BundleHoldUnavailable,
  )
  let (installed, _) = hold_lifecycle_fixture(12, 0, 1)
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(installed), binding, true),
    BundleHoldUnavailable,
  )
  let (reclaimed, _) = hold_lifecycle_fixture(15, 3, 0)
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(reclaimed), binding, false),
    BundleHoldFenced,
  )
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(reclaimed), binding, true),
    BundleHoldUnavailable,
  )
  assert_eq(
    observe_bundle_hold(
      hold_fixture_catalog(),
      Some(record),
      hold_fixture_binding(),
      false,
    ),
    BundleHoldUnavailable,
  )
  assert_eq(bundle_hold_observation_projection(BundleHoldRetained), "retained")
  assert_eq(bundle_hold_observation_projection(BundleHoldFenced), "fenced")
  assert_eq(
    bundle_hold_observation_projection(BundleHoldUnresolved),
    "unresolved",
  )
  assert_eq(
    bundle_hold_observation_projection(BundleHoldUnavailable),
    "unavailable",
  )
}

///|
test "release before retain fences only the existing revision without changing owners or phase" {
  for phase in [0, 1, 2, 3] {
    let owners = if phase == 3 { 0 } else { 2 }
    let (record, binding) = hold_lifecycle_fixture(11, phase, owners)
    let fence = prepare_bundle_hold_fence(
      hold_fixture_catalog(),
      record,
      binding,
      false,
    ).unwrap()
    let (before, after) = bundle_transition_projection(fence)
    assert_eq(before, ["11", phase.to_string(), owners.to_string()])
    assert_eq(after, ["12", phase.to_string(), owners.to_string()])
    assert_true(
      commit_bundle_transition(fence, false) is Err(BundleTransitionNotDurable),
    )
    assert_eq(
      observe_bundle_hold(hold_fixture_catalog(), Some(record), binding, false),
      BundleHoldUnresolved,
    )
    let committed = commit_bundle_transition(fence, true).unwrap()
    assert_eq(
      observe_bundle_hold(
        hold_fixture_catalog(),
        Some(committed),
        binding,
        false,
      ),
      BundleHoldFenced,
    )
    assert_true(
      prepare_bundle_hold_fence(hold_fixture_catalog(), record, binding, false)
      is Err(InvalidBundleState),
    )
    assert_true(
      prepare_bundle_hold_retain(
        hold_fixture_catalog(),
        Some(binding.runtime_bundle_cid),
        record,
        binding,
        10,
      )
      is Err(InvalidBundleState),
    )
    assert_eq(
      bundle_record_projection(commit_bundle_transition(fence, true).unwrap()),
      after,
    )
  }
}

///|
test "bundle holds use active admission and exact revision while retained retries remain idempotent" {
  let (record, binding) = hold_lifecycle_fixture(11, 1, 0)
  assert_true(
    prepare_bundle_hold_retain(hold_fixture_catalog(), None, record, binding, 1)
    is Err(InvalidBundleState),
  )
  assert_true(
    prepare_bundle_hold_retain(
      hold_fixture_catalog(),
      Some(binding.runtime_bundle_cid),
      record,
      binding,
      0,
    )
    is Err(BundleOwnerLimit),
  )
  let retain = prepare_bundle_hold_retain(
    hold_fixture_catalog(),
    Some(binding.runtime_bundle_cid),
    record,
    binding,
    1,
  ).unwrap()
  let record = commit_bundle_transition(retain, true).unwrap()
  assert_eq(bundle_record_projection(record), ["12", "1", "1"])
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(record), binding, true),
    BundleHoldRetained,
  )
  assert_true(
    prepare_bundle_hold_fence(hold_fixture_catalog(), record, binding, true)
    is Err(InvalidBundleState),
  )
  assert_true(
    prepare_bundle_hold_retain(
      hold_fixture_catalog(),
      Some(binding.runtime_bundle_cid),
      record,
      binding,
      2,
    )
    is Err(InvalidBundleState),
  )
  let drain = prepare_bundle_drain(record).unwrap()
  let record = commit_bundle_transition(drain, true).unwrap()
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(record), binding, true),
    BundleHoldRetained,
  )
  let release = prepare_bundle_release(record).unwrap()
  let record = commit_bundle_transition(release, true).unwrap()
  assert_eq(
    observe_bundle_hold(hold_fixture_catalog(), Some(record), binding, false),
    BundleHoldFenced,
  )
  for phase in [0, 2, 3] {
    let (inactive, binding) = hold_lifecycle_fixture(11, phase, 0)
    assert_true(
      prepare_bundle_hold_retain(
        hold_fixture_catalog(),
        Some(binding.runtime_bundle_cid),
        inactive,
        binding,
        1,
      )
      is Err(InvalidBundleState),
    )
  }
}

///|
test "bundle hold fences and ordinary lifecycle transitions reject revision overflow" {
  let (record, original_binding) = hold_lifecycle_fixture(2147483647, 1, 1)
  let binding = prepare_bundle_hold_binding(
    original_binding.distribution,
    hold_fixture_catalog(),
    "coordinator-a",
    "workspace-a",
    original_binding.authority_scope_cid,
    "production",
    original_binding.set_revision_cid,
    original_binding.runtime_bundle_cid,
    "site-a",
    7,
    2147483647,
    "overflow-attempt",
  ).unwrap()
  assert_true(
    prepare_bundle_hold_fence(hold_fixture_catalog(), record, binding, false)
    is Err(InvalidBundleState),
  )
  assert_true(
    prepare_bundle_hold_retain(
      hold_fixture_catalog(),
      Some(binding.runtime_bundle_cid),
      record,
      binding,
      2,
    )
    is Err(InvalidBundleState),
  )
  assert_true(prepare_bundle_drain(record) is Err(InvalidBundleState))
  assert_true(prepare_bundle_release(record) is Err(InvalidBundleState))
  assert_eq(bundle_record_projection(record), ["2147483647", "1", "1"])
  let (last, original_binding) = hold_lifecycle_fixture(2147483646, 1, 0)
  let binding = prepare_bundle_hold_binding(
    original_binding.distribution,
    hold_fixture_catalog(),
    "coordinator-a",
    "workspace-a",
    original_binding.authority_scope_cid,
    "production",
    original_binding.set_revision_cid,
    original_binding.runtime_bundle_cid,
    "site-a",
    7,
    2147483646,
    "last-attempt",
  ).unwrap()
  let fence = prepare_bundle_hold_fence(
    hold_fixture_catalog(),
    last,
    binding,
    false,
  ).unwrap()
  assert_eq(
    bundle_record_projection(commit_bundle_transition(fence, true).unwrap()),
    ["2147483647", "1", "0"],
  )
}

///|
test "competing prepared bundle retain and release fences cannot both commit" {
  let (record, binding) = hold_lifecycle_fixture(11, 1, 0)
  let retain = prepare_bundle_hold_retain(
    hold_fixture_catalog(),
    Some(binding.runtime_bundle_cid),
    record,
    binding,
    1,
  ).unwrap()
  let fence = prepare_bundle_hold_fence(
    hold_fixture_catalog(),
    record,
    binding,
    false,
  ).unwrap()
  commit_bundle_transition(fence, true).unwrap() |> ignore
  assert_true(commit_bundle_transition(retain, true) is Err(InvalidBundleState))
  assert_eq(bundle_record_projection(record), ["12", "1", "0"])
  let (record, binding) = hold_lifecycle_fixture(11, 1, 0)
  let retain = prepare_bundle_hold_retain(
    hold_fixture_catalog(),
    Some(binding.runtime_bundle_cid),
    record,
    binding,
    1,
  ).unwrap()
  let fence = prepare_bundle_hold_fence(
    hold_fixture_catalog(),
    record,
    binding,
    false,
  ).unwrap()
  commit_bundle_transition(retain, true).unwrap() |> ignore
  assert_true(commit_bundle_transition(fence, true) is Err(InvalidBundleState))
  assert_eq(bundle_record_projection(record), ["12", "1", "1"])
}
