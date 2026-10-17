///|
/// The existing transport-neutral signature envelope with an explicitly typed
/// installation-metadata grant. Key trust and signature verification remain
/// the original Site's physical duties; shape admission supplies neither.
struct InstallationPreparationCredentialSignatureEnvelope {
  grant : InstallationPreparationCredentialGrant
  key_id : String
  signature : String
}

///|
pub fn installation_preparation_credential_signature_preimage(
  grant : InstallationPreparationCredentialGrant,
) -> Result[Bytes, RemoteCredentialIssue] {
  grant.original_wire().map(body =>
    @utf8.encode(
      "actql-remote-credential-grant-signature/0.1\u{0000}" +
      grant.identity +
      "\u{0000}" +
      body,
    ),
  )
}

///|
pub fn prepare_installation_preparation_credential_signature_envelope(
  grant : InstallationPreparationCredentialGrant,
  key_id : String,
  signature : String,
) -> Result[InstallationPreparationCredentialSignatureEnvelope, RemoteCredentialIssue] {
  if !installation_preparation_text(key_id, 512) || !valid_signature(signature) {
    Err(InvalidCredentialSignature)
  } else {
    Ok({ grant, key_id, signature, })
  }
}

///|
pub fn admit_installation_preparation_credential_signature_envelope(
  subject : InstallationPreparationSubject,
  version : String,
  key_id : String,
  grant_cid : String,
  body : String,
  signature : String,
) -> Result[InstallationPreparationCredentialSignatureEnvelope, RemoteCredentialIssue] {
  if version != "actql-remote-credential-grant-signature/0.1" {
    return Err(InvalidCredentialSignature)
  }
  let grant = match
    admit_installation_preparation_credential_grant_json(subject, body, grant_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  prepare_installation_preparation_credential_signature_envelope(
    grant, key_id, signature,
  )
}

///|
pub fn InstallationPreparationCredentialSignatureEnvelope::projection(
  self : InstallationPreparationCredentialSignatureEnvelope,
) -> (String, String, String, String, String, String) {
  (
    "actql-remote-credential-grant-signature/0.1",
    self.key_id,
    self.grant.identity,
    self.grant.original_wire().unwrap(),
    self.signature,
    self.grant.issuer_authority,
  )
}

///|
pub fn InstallationPreparationCredentialSignatureEnvelope::grant(
  self : InstallationPreparationCredentialSignatureEnvelope,
) -> InstallationPreparationCredentialGrant {
  self.grant
}
