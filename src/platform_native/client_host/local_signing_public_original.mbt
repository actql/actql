///|
// Pure metadata encoding for the same private installation preimage. This
// function cannot authenticate the packet, capture a file or adopt a key.
fn local_signing_public_installation_body(
  adoption : String,
  scope : String,
  configuration : String,
  projection : Bytes,
  purpose : @credential.LocalSigningPurpose,
  public_key : @credential.LocalSigningPublicKey,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  local_adoption_record([
    ("adoption_cid", adoption),
    ("authority_scope_cid", scope),
    ("installation_configuration_cid", configuration),
    ("projection", @base64.encode(projection)),
    ("public_key_cid", public_key.cid()),
    ("public_key_original", public_key.json()),
    ("purpose", local_signing_installation_purpose(purpose)),
    ("version", "actql-native-local-installation-original/0.1"),
  ])
}

///|
// Private payload metadata only. The enclosing installation reader authenticates
// the same original HMAC before these fields can become key custody.
priv struct LocalSigningInstallationFields {
  adoption : String
  scope : String
  configuration : String
  projection : String
  purpose : String
  version : String
  public_key : @credential.LocalSigningPublicKey?
}

///|
fn local_signing_installation_fields(
  payload : Bytes,
) -> Result[LocalSigningInstallationFields, NativeLocalAdoptionIssue] {
  // Retain the exact historical six-field alternative. Missing public metadata
  // is represented, never synthesized from today's PEM, configuration or stat.
  match local_adoption_fields(payload, [
    "adoption_cid", "authority_scope_cid", "installation_configuration_cid", "projection",
    "purpose", "version",
  ]) {
    Ok(fields) =>
      Ok({
        adoption: fields[0],
        scope: fields[1],
        configuration: fields[2],
        projection: fields[3],
        purpose: fields[4],
        version: fields[5],
        public_key: None,
      })
    Err(_) => {
      let fields = match local_adoption_fields(payload, [
        "adoption_cid", "authority_scope_cid", "installation_configuration_cid", "projection",
        "public_key_cid", "public_key_original", "purpose", "version",
      ]) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let original = match @credential.admit_local_signing_public_key_json(
        fields[5], fields[4],
      ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      Ok({
        adoption: fields[0],
        scope: fields[1],
        configuration: fields[2],
        projection: fields[3],
        purpose: fields[6],
        version: fields[7],
        public_key: Some(original),
      })
    }
  }
}

///|
// Trusted first-install path only: the existing Host-selected physical Library
// projects the selected public PEM, and the Credential Owner issues its byte
// identity. This does not read a private key or prove public/private pairing.
fn NativeLocalSigningAccountBinding::prepare_public_key_original(
  self : NativeLocalSigningAccountBinding,
) -> Result[@credential.LocalSigningPublicKey, NativeClientRunJournalIssue] {
  if self.require_current_account() is Err(_) {
    return Err(AuthorizationDenied)
  }
  let (_, _, _, _, _, _, _, pem) = @credential_resource.native_local_signing_key_selection_projection(
    self.selection,
  )
  let raw = match self.host.epoch.crypto.ed25519_public_key_raw32(pem) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let original = match @credential.prepare_local_signing_public_key(raw) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  if self.require_current_account() is Err(_) {
    return Err(AuthorizationDenied)
  }
  Ok(original)
}
