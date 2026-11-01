///|
/// Historical verification keys and current new-admission keys remain distinct.
/// These arrays are DATA for the existing constructor, not a Store, holding,
/// authority, currentness or cleanup acknowledgment.
fn runtime_bundle_trust_sets(
  trust : Array[NativeRuntimeBundleTrust],
) -> Result[
  (Array[NativeRuntimeBundleAuthority], Array[NativeRuntimeBundleAuthority]),
  NativeRuntimeBundleStoreIssue,
] {
  if trust.is_empty() || trust.length() > 1024 {
    return Err(InvalidConfiguration)
  }
  let authorities : Array[NativeRuntimeBundleAuthority] = []
  let admission_authorities : Array[NativeRuntimeBundleAuthority] = []
  for entry in trust {
    for prior in authorities {
      if prior.issuer_authority == entry.authority.issuer_authority &&
        prior.key_id == entry.authority.key_id {
        return Err(InvalidConfiguration)
      }
    }
    authorities.push(entry.authority)
    if entry.admit_new_bundles {
      admission_authorities.push(entry.authority)
    }
  }
  Ok((authorities, admission_authorities))
}
