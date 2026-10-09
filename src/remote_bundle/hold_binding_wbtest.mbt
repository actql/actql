///|
fn hold_fixture_catalog() -> String {
  "123e4567-e89b-42d3-a456-426614174000"
}

///|
fn hold_fixture_scope(
  distribution? : RemoteBundleDistribution = hold_fixture_distribution(),
  coordinator? : String = "coordinator-a",
  workspace? : String = "workspace-a",
  authority? : String = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  environment? : String = "production",
  revision? : String = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  runtime_bundle_cid? : String = hold_fixture_cid_a(),
  site? : String = "site-a",
  generation? : Int = 7,
  attempt? : String = "hold-a",
) -> RemoteBundleHoldScope {
  prepare_bundle_hold_scope(
    distribution, coordinator, workspace, authority, environment, revision, runtime_bundle_cid,
    site, generation, attempt,
  ).unwrap()
}

///|
fn hold_fixture_binding(
  initial_revision? : Int = 11,
) -> RemoteBundleHoldBinding {
  prepare_bundle_hold_binding_from_scope(
    hold_fixture_scope(),
    hold_fixture_catalog(),
    initial_revision,
  ).unwrap()
}

///|
test "bundle hold scope and binding match independent canonical vectors" {
  let distribution = hold_fixture_distribution()
  let scope = hold_fixture_scope()
  assert_eq(bundle_hold_scope_json(scope).unwrap(), hold_vector_scope_body())
  assert_eq(bundle_hold_scope_identity(scope), hold_vector_scope_cid())
  let admitted_scope = admit_bundle_hold_scope_json(
    distribution,
    hold_vector_scope_body(),
    hold_vector_scope_cid(),
  ).unwrap()
  assert_eq(
    bundle_hold_scope_projection(admitted_scope),
    bundle_hold_scope_projection(scope),
  )
  let binding = prepare_bundle_hold_binding_from_scope(
    admitted_scope,
    hold_fixture_catalog(),
    11,
  ).unwrap()
  assert_eq(
    bundle_hold_binding_json(binding).unwrap(),
    hold_vector_binding_body(),
  )
  assert_eq(bundle_hold_binding_identity(binding), hold_vector_binding_cid())
  let admitted = admit_bundle_hold_binding_json(
    distribution,
    hold_vector_binding_body(),
    hold_vector_binding_cid(),
  ).unwrap()
  assert_true(bundle_hold_binding_matches_scope(admitted, scope))
  assert_eq(
    bundle_hold_scope_identity(bundle_hold_binding_scope(admitted).unwrap()),
    hold_vector_scope_cid(),
  )
  assert_eq(bundle_hold_binding_projection(admitted), [
    hold_vector_binding_cid(),
    hold_fixture_catalog(),
    "coordinator-a",
    "workspace-a",
    "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    "production",
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    hold_vector_distribution_cid(),
    hold_fixture_cid_a(),
    "site-a",
    "7",
    "11",
    "hold-a",
  ])
}

///|
test "bundle hold values reject closed-body tampering and mismatched distribution membership" {
  let distribution = hold_fixture_distribution()
  for
    body in [
      " " + hold_vector_binding_body(),
      hold_vector_binding_body().replace(old="{", new="{\"unknown\":true,"),
      hold_vector_binding_body().replace(
        old="{",
        new="{\"attempt_id\":\"hold-a\",",
      ),
      hold_vector_binding_body().replace(
        old="\"initial_revision\":11",
        new="\"initial_revision\":-1",
      ),
      hold_vector_binding_body().replace(
        old="\"initial_revision\":11",
        new="\"initial_revision\":11.0",
      ),
      hold_vector_binding_body().replace(
        old="\"site_generation\":7",
        new="\"site_generation\":2147483648",
      ),
      hold_vector_binding_body().replace(old="hold-a", new="folder/hold-a"),
      hold_vector_binding_body().replace(old="/0.1", new="/0.2"),
      hold_vector_binding_body().replace(
        old=hold_fixture_cid_a(),
        new="sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      ),
    ] {
    assert_true(
      admit_bundle_hold_binding_json(
        distribution,
        body,
        hold_vector_binding_cid(),
      )
      is Err(InvalidBundle),
    )
  }
  assert_true(
    admit_bundle_hold_binding_json(
      distribution,
      hold_vector_binding_body(),
      hold_fixture_cid_a(),
    )
    is Err(BundleIdentityMismatch),
  )
  assert_true(
    admit_bundle_hold_binding_json(
      distribution,
      hold_vector_binding_body().replace(old="workspace-a", new="workspace-b"),
      hold_vector_binding_cid(),
    )
    is Err(BundleIdentityMismatch),
  )
  let another = prepare_bundle_distribution([hold_fixture_cid_a()]).unwrap()
  assert_true(
    admit_bundle_hold_binding_json(
      another,
      hold_vector_binding_body(),
      hold_vector_binding_cid(),
    )
    is Err(InvalidBundle),
  )
  assert_true(
    admit_bundle_hold_scope_json(
      another,
      hold_vector_scope_body(),
      hold_vector_scope_cid(),
    )
    is Err(InvalidBundle),
  )
  assert_true(
    prepare_bundle_hold_scope(
      another,
      "coordinator-a",
      "workspace-a",
      hold_fixture_cid_a(),
      "production",
      hold_fixture_cid_a(),
      hold_fixture_cid_b(),
      "site-a",
      7,
      "hold-a",
    )
    is Err(InvalidBundle),
  )
  for
    body in [
      " " + hold_vector_scope_body(),
      hold_vector_scope_body().replace(old="{", new="{\"unknown\":true,"),
      hold_vector_scope_body().replace(
        old="{",
        new="{\"attempt_id\":\"hold-a\",",
      ),
      hold_vector_scope_body().replace(
        old="\"site_generation\":7",
        new="\"site_generation\":7.5",
      ),
    ] {
    assert_true(
      admit_bundle_hold_scope_json(distribution, body, hold_vector_scope_cid())
      is Err(InvalidBundle),
    )
  }
}

///|
test "bundle hold identities bind every scope dimension using exact text" {
  let scope = hold_fixture_scope()
  let binding = hold_fixture_binding()
  for
    changed in [
      hold_fixture_scope(coordinator="coordinator-b"),
      hold_fixture_scope(workspace="workspace-b"),
      hold_fixture_scope(authority=hold_fixture_cid_a()),
      hold_fixture_scope(environment="staging"),
      hold_fixture_scope(revision=hold_fixture_cid_a()),
      hold_fixture_scope(
        distribution=prepare_bundle_distribution([hold_fixture_cid_a()]).unwrap(),
      ),
      hold_fixture_scope(runtime_bundle_cid=hold_fixture_cid_b()),
      hold_fixture_scope(site="site-b"),
      hold_fixture_scope(generation=8),
      hold_fixture_scope(attempt="hold-b"),
    ] {
    assert_false(bundle_hold_binding_matches_scope(binding, changed))
    assert_true(
      bundle_hold_scope_identity(scope) != bundle_hold_scope_identity(changed),
    )
    assert_true(
      bundle_hold_binding_identity(binding) !=
      bundle_hold_binding_identity(
        prepare_bundle_hold_binding_from_scope(
          changed,
          hold_fixture_catalog(),
          11,
        ).unwrap(),
      ),
    )
  }
  assert_true(
    bundle_hold_scope_identity(hold_fixture_scope(workspace="caf\u{00e9}")) !=
    bundle_hold_scope_identity(hold_fixture_scope(workspace="cafe\u{0301}")),
  )
  assert_true(
    bundle_hold_binding_identity(binding) !=
    bundle_hold_binding_identity(hold_fixture_binding(initial_revision=12)),
  )
  assert_true(
    bundle_hold_binding_identity(binding) !=
    bundle_hold_binding_identity(
      prepare_bundle_hold_binding_from_scope(
        scope, "123e4567-e89b-42d3-a456-426614174001", 11,
      ).unwrap(),
    ),
  )
}

///|
test "bundle hold catalog UUIDs nonces and opaque-value identities are validated" {
  assert_true(valid_bundle_catalog_incarnation(hold_fixture_catalog()))
  for
    catalog in [
      "", "123e4567e89b42d3a456426614174000", "123E4567-e89b-42d3-a456-426614174000",
      "123e4567-e89b-42d3-a456-42661417400g",
    ] {
    assert_false(valid_bundle_catalog_incarnation(catalog))
    assert_true(
      prepare_bundle_hold_binding_from_scope(hold_fixture_scope(), catalog, 11)
      is Err(InvalidBundle),
    )
  }
  for attempt in ["", "../hold", "with space", "caf\u{00e9}", "a.b", "x\\y"] {
    assert_true(
      prepare_bundle_hold_scope(
        hold_fixture_distribution(),
        "coordinator-a",
        "workspace-a",
        hold_fixture_cid_a(),
        "production",
        hold_fixture_cid_a(),
        hold_fixture_cid_a(),
        "site-a",
        0,
        attempt,
      )
      is Err(InvalidBundle),
    )
  }
  assert_true(
    prepare_bundle_hold_binding_from_scope(
      hold_fixture_scope(),
      hold_fixture_catalog(),
      -1,
    )
    is Err(InvalidBundle),
  )
  let scope = hold_fixture_scope()
  assert_true(
    bundle_hold_scope_json({ ..scope, environment: "another", })
    is Err(BundleIdentityMismatch),
  )
  let binding = hold_fixture_binding()
  assert_true(
    bundle_hold_binding_json({ ..binding, environment: "another", })
    is Err(BundleIdentityMismatch),
  )
  assert_true(
    bundle_hold_binding_scope({ ..binding, environment: "another", })
    is Err(InvalidBundle),
  )
  assert_true(
    bundle_hold_binding_json({
      ..binding,
      runtime_bundle_cid: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    })
    is Err(InvalidBundle),
  )
  let projected = bundle_hold_binding_projection(binding)
  projected[3] = "another"
  assert_eq(
    bundle_hold_binding_json(binding).unwrap(),
    hold_vector_binding_body(),
  )
}
