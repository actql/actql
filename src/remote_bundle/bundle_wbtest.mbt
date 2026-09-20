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

///|
test "bundle signature envelope owns exact preimage and authority binding" {
  let manifest = bundle_manifest()
  let signature = "A".repeat(86)
  let envelope = prepare_bundle_signature_envelope(manifest, "key-a", signature).unwrap()
  let projection = bundle_signature_envelope_projection(envelope)
  assert_eq(projection[0], "actql-remote-runtime-bundle-signature/0.1")
  assert_eq(projection[1], "key-a")
  assert_eq(projection[2], bundle_manifest_identity(manifest))
  assert_eq(projection[4], signature)
  assert_eq(projection[5], "bundle-authority-a")
  assert_eq(
    bundle_signature_preimage(manifest).unwrap(),
    @utf8.encode(
      "actql-remote-runtime-bundle-signature/0.1\u{0000}" +
      bundle_manifest_identity(manifest) +
      "\u{0000}" +
      bundle_manifest_json(manifest).unwrap(),
    ),
  )
  let admitted = admit_bundle_signature_envelope(
    projection[0],
    projection[1],
    projection[2],
    projection[3],
    projection[4],
  ).unwrap()
  assert_eq(
    bundle_manifest_identity(bundle_signature_envelope_manifest(admitted)),
    bundle_manifest_identity(manifest),
  )
  assert_true(
    admit_bundle_signature_envelope(
      projection[0],
      projection[1],
      projection[2],
      projection[3],
      "=".repeat(86),
    )
    is Err(InvalidBundleSignature),
  )
}
