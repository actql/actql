///|
test "Trust custody preserves historical verification separately from new admission" {
  let historical : NativeRuntimeBundleAuthority = {
    issuer_authority: "original-issuer",
    key_id: "old-key",
    public_key_pem: "original-public-key-data",
  }
  let current : NativeRuntimeBundleAuthority = {
    issuer_authority: "original-issuer",
    key_id: "current-key",
    public_key_pem: "current-public-key-data",
  }
  let (verification, admission) = runtime_bundle_trust_sets([
    { authority: historical, admit_new_bundles: false, },
    { authority: current, admit_new_bundles: true, },
  ]).unwrap()
  assert_eq(verification.length(), 2)
  assert_eq(verification[0].key_id, "old-key")
  assert_eq(verification[0].public_key_pem, "original-public-key-data")
  assert_eq(verification[1].key_id, "current-key")
  assert_eq(admission.length(), 1)
  assert_eq(admission[0].key_id, "current-key")
  let (all_historical, none_new) = runtime_bundle_trust_sets([
    { authority: historical, admit_new_bundles: false, },
    { authority: current, admit_new_bundles: false, },
  ]).unwrap()
  assert_eq(all_historical.length(), 2)
  assert_eq(none_new.length(), 0)
}

///|
test "Trust custody rejects duplicate identities and invalid counts before any Store" {
  let authority : NativeRuntimeBundleAuthority = {
    issuer_authority: "original-issuer",
    key_id: "same-key",
    public_key_pem: "original-public-key-data",
  }
  assert_true(runtime_bundle_trust_sets([]) is Err(InvalidConfiguration))
  assert_true(
    runtime_bundle_trust_sets([
      { authority, admit_new_bundles: false, },
      { authority, admit_new_bundles: true, },
    ])
    is Err(InvalidConfiguration),
  )
  let oversized : Array[NativeRuntimeBundleTrust] = []
  for _index = 0; _index < 1025; _index = _index + 1 {
    oversized.push({ authority, admit_new_bundles: false, })
  }
  assert_true(runtime_bundle_trust_sets(oversized) is Err(InvalidConfiguration))
}
