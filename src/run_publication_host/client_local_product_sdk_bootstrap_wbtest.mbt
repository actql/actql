///|
test "explicit SDK bootstrap retains the original seven bodies and adds two bounded originals" {
  let root = "/private/local"
  let at = "2026-10-12T00:00:00.000Z"
  let old = client_local_product_bootstrap_originals(root, at).unwrap()
  let fresh = client_local_product_sdk_bootstrap_originals(root, at).unwrap()
  assert_eq(fresh.original.common.account, old.common.account)
  assert_eq(
    fresh.original.common.retention_dependencies,
    old.common.retention_dependencies,
  )
  assert_eq(fresh.original.common.retention_policy, old.common.retention_policy)
  assert_eq(fresh.original.common.store, old.common.store)
  assert_eq(fresh.original.common.result_policy, old.common.result_policy)
  assert_eq(fresh.original.environment, old.environment)
  assert_eq(fresh.original.compute, old.compute)
  assert_eq(
    client_local_run_policy_profile_cid(fresh.profile),
    "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
  )
  assert_eq(
    @publication.local_sdk_result_read_selection_cid(fresh.read),
    "sha256:13906dcd43b46a467520bf3ea87a8889fd9d04701106b814e85142703e751f27",
  )
  assert_true(
    @utf8.encode(client_local_run_policy_profile_wire(fresh.profile)).length() <=
    8192,
  )
  assert_true(
    @utf8.encode(@publication.local_sdk_result_read_selection_wire(fresh.read)).length() <=
    8192,
  )
}

///|
test "explicit SDK metadata does not contain an adoption-time read expiry" {
  let first = client_local_product_sdk_bootstrap_originals(
    "/private/local", "2026-10-12T00:00:00.000Z",
  ).unwrap()
  let later = client_local_product_sdk_bootstrap_originals(
    "/private/local", "2026-10-13T00:00:00.001Z",
  ).unwrap()
  assert_eq(
    client_local_run_policy_profile_wire(first.profile),
    client_local_run_policy_profile_wire(later.profile),
  )
  assert_eq(
    @publication.local_sdk_result_read_selection_wire(first.read),
    @publication.local_sdk_result_read_selection_wire(later.read),
  )
  assert_false(
    @publication.local_sdk_result_read_selection_wire(first.read).contains(
      "expires_at",
    ),
  )
}
