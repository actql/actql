///|
fn bundle_cid(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn bundle_manifest() -> RemoteBundleManifest {
  prepare_bundle_manifest(
    "bundle-authority-a",
    "local-runtime",
    "local-runtime/1",
    "aarch64-apple-darwin",
    bundle_cid("a"),
    12L,
    "local",
    "local/1",
    "strategy/1",
  ).unwrap()
}

///|
test "runtime bundle identity and lifecycle are portable and monotonic" {
  let manifest = bundle_manifest()
  let body = bundle_manifest_json(manifest).unwrap()
  assert_eq(
    bundle_manifest_identity(
      admit_bundle_manifest_json(body, bundle_manifest_identity(manifest)).unwrap(),
    ),
    bundle_manifest_identity(manifest),
  )
  let record = open_bundle_record(manifest)
  commit_bundle_transition(prepare_bundle_activate(record).unwrap(), true).unwrap()
  |> ignore
  commit_bundle_transition(prepare_bundle_retain(record, 2).unwrap(), true).unwrap()
  |> ignore
  commit_bundle_transition(prepare_bundle_drain(record).unwrap(), true).unwrap()
  |> ignore
  assert_true(prepare_bundle_retain(record, 2) is Err(InvalidBundleState))
  assert_true(prepare_bundle_reclaim(record) is Err(InvalidBundleState))
  commit_bundle_transition(prepare_bundle_release(record).unwrap(), true).unwrap()
  |> ignore
  commit_bundle_transition(prepare_bundle_reclaim(record).unwrap(), true).unwrap()
  |> ignore
  assert_eq(bundle_record_projection(record), ["5", "3", "0"])
  assert_true(prepare_bundle_activate(record) is Err(InvalidBundleState))
}

///|
test "runtime bundle record restores exact drain ownership" {
  let manifest = bundle_manifest()
  let restored = restore_bundle_record(manifest, 7, 2, 3).unwrap()
  assert_eq(bundle_record_projection(restored), ["7", "2", "3"])
  assert_true(
    restore_bundle_record(manifest, 7, 3, 1) is Err(InvalidBundleState),
  )
}
