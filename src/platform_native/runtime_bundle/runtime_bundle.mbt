///|
pub(all) struct NativeRuntimeBundleAuthority {
  issuer_authority : String
  key_id : String
  public_key_pem : String
}

///|
/// A verification key and its current bundle-admission authority.
///
/// Historical records may continue to use a key after normal rotation while
/// `admit_new_bundles` is false. Removing the trust entry entirely also makes
/// records signed by that key unverifiable when the Store is reopened.
pub(all) struct NativeRuntimeBundleTrust {
  authority : NativeRuntimeBundleAuthority
  admit_new_bundles : Bool
}

///|
pub(all) enum NativeRuntimeBundleIssue {
  InvalidConfiguration
  AuthorityCollision
  AuthorityRejected
  TargetRejected
  Bundle(@bundle.RemoteBundleIssue)
  Signature(@signature.NativeSignatureIssue)
} derive(Eq, Debug)

///|
/// Admit the portable signed envelope and verify it through the configured
/// native crypto adapter. Authority selection, target selection and the exact
/// preimage remain MoonBit decisions; the adapter reports only the physical
/// Ed25519 verification result.
pub fn admit_signed_bundle(
  library : @signature.Library,
  authorities : Array[NativeRuntimeBundleAuthority],
  version : String,
  key_id : String,
  runtime_bundle_cid : String,
  body : String,
  signature : String,
  target_triple : String,
) -> Result[@bundle.RemoteBundleManifest, NativeRuntimeBundleIssue] {
  if authorities.is_empty() ||
    authorities.length() > 1024 ||
    target_triple.is_empty() ||
    target_triple.length() > 512 {
    return Err(InvalidConfiguration)
  }
  let envelope = match
    @bundle.admit_bundle_signature_envelope(
      version, key_id, runtime_bundle_cid, body, signature,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Bundle(issue))
  }
  let projection = @bundle.bundle_signature_envelope_projection(envelope)
  if projection[5] == "" || projection[1] == "" {
    return Err(Bundle(@bundle.InvalidBundleSignature))
  }
  let mut selected : String? = None
  for authority in authorities {
    if authority.issuer_authority.is_empty() ||
      authority.issuer_authority.length() > 512 ||
      authority.key_id.is_empty() ||
      authority.key_id.length() > 512 ||
      authority.public_key_pem.is_empty() ||
      authority.public_key_pem.length() > 16384 {
      return Err(InvalidConfiguration)
    }
    if authority.issuer_authority == projection[5] &&
      authority.key_id == projection[1] {
      if selected is Some(_) {
        return Err(AuthorityCollision)
      }
      selected = Some(authority.public_key_pem)
    }
  }
  guard selected is Some(public_key) else { return Err(AuthorityRejected) }
  let manifest = @bundle.bundle_signature_envelope_manifest(envelope)
  let manifest_projection = @bundle.bundle_manifest_projection(manifest)
  if manifest_projection[4] != target_triple {
    return Err(TargetRejected)
  }
  let preimage = match @bundle.bundle_signature_preimage(manifest) {
    Ok(value) => value
    Err(issue) => return Err(Bundle(issue))
  }
  match library.verify_ed25519(public_key, preimage, projection[4]) {
    Ok(true) => Ok(manifest)
    Ok(false) => Err(AuthorityRejected)
    Err(issue) => Err(Signature(issue))
  }
}
