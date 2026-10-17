///|
// Existing Credential DATA projection only. The Host retains its actual
// publication/current/issuer/material duties independently of these values.
fn[T] installation_credential_result(
  result : Result[T, @credential.RemoteCredentialIssue],
) -> T raise NodeHostFailure {
  match result {
    Ok(value) => value
    Err(issue) => raise RemoteCredential(issue)
  }
}

///|
#export_name("clientInstallationPreparationSubjectAdmit")
pub fn client_installation_preparation_subject_admit(
  wire : String,
  cid : String,
) -> @credential.InstallationPreparationSubject raise NodeHostFailure {
  installation_credential_result(
    @credential.admit_installation_preparation_subject_json(wire, cid),
  )
}

///|
#export_name("clientInstallationPreparationSubjectWire")
pub fn client_installation_preparation_subject_wire(
  value : @credential.InstallationPreparationSubject,
) -> String {
  value.original_wire()
}

///|
#export_name("clientInstallationPreparationSubjectCid")
pub fn client_installation_preparation_subject_cid(
  value : @credential.InstallationPreparationSubject,
) -> String {
  value.cid()
}

///|
#export_name("clientInstallationPreparationScopeMatchesSubject")
pub fn client_installation_preparation_scope_matches_subject(
  value : @credential.InstallationPreparationCredentialScope,
  subject : @credential.InstallationPreparationSubject,
) -> Bool {
  physical_equal(value.subject, subject)
}

///|
#export_name("clientInstallationPreparationGrantPrepare")
pub fn client_installation_preparation_grant_prepare(
  issuer : String,
  scope : @credential.InstallationPreparationCredentialScope,
  expires : Int64,
  maximum : Int,
) -> @credential.InstallationPreparationCredentialGrant raise NodeHostFailure {
  installation_credential_result(
    @credential.prepare_installation_preparation_credential_grant(
      issuer, scope, expires, maximum,
    ),
  )
}

///|
#export_name("clientInstallationPreparationGrantAdmit")
pub fn client_installation_preparation_grant_admit(
  subject : @credential.InstallationPreparationSubject,
  wire : String,
  cid : String,
) -> @credential.InstallationPreparationCredentialGrant raise NodeHostFailure {
  installation_credential_result(
    @credential.admit_installation_preparation_credential_grant_json(
      subject, wire, cid,
    ),
  )
}

///|
#export_name("clientInstallationPreparationGrantWire")
pub fn client_installation_preparation_grant_wire(
  value : @credential.InstallationPreparationCredentialGrant,
) -> String raise NodeHostFailure {
  installation_credential_result(value.original_wire())
}

///|
#export_name("clientInstallationPreparationGrantCid")
pub fn client_installation_preparation_grant_cid(
  value : @credential.InstallationPreparationCredentialGrant,
) -> String {
  value.cid()
}

///|
#export_name("clientInstallationPreparationGrantScope")
pub fn client_installation_preparation_grant_scope(
  value : @credential.InstallationPreparationCredentialGrant,
) -> @credential.InstallationPreparationCredentialScope {
  value.scope()
}

///|
#export_name("clientInstallationPreparationGrantIssuer")
pub fn client_installation_preparation_grant_issuer(
  value : @credential.InstallationPreparationCredentialGrant,
) -> String {
  value.issuer_authority()
}

///|
#export_name("clientInstallationPreparationGrantExpires")
pub fn client_installation_preparation_grant_expires(
  value : @credential.InstallationPreparationCredentialGrant,
) -> Int64 {
  value.expires_unix_ms()
}

///|
#export_name("clientInstallationPreparationGrantMaxUses")
pub fn client_installation_preparation_grant_max_uses(
  value : @credential.InstallationPreparationCredentialGrant,
) -> Int {
  value.max_uses()
}

///|
#export_name("clientInstallationPreparationUsePrepare")
pub fn client_installation_preparation_use_prepare(
  grant : @credential.InstallationPreparationCredentialGrant,
  id : String,
  now : Int64,
  used : Int,
  revoked : Bool,
  actual : @credential.InstallationPreparationCredentialScope,
) -> @credential.InstallationPreparationCredentialUse raise NodeHostFailure {
  installation_credential_result(
    @credential.prepare_installation_preparation_credential_use(
      grant, id, now, used, revoked, actual,
    ),
  )
}

///|
#export_name("clientInstallationPreparationUseAdmit")
pub fn client_installation_preparation_use_admit(
  grant : @credential.InstallationPreparationCredentialGrant,
  wire : String,
  cid : String,
) -> @credential.InstallationPreparationCredentialUse raise NodeHostFailure {
  installation_credential_result(
    @credential.admit_installation_preparation_credential_use_json(
      grant, wire, cid,
    ),
  )
}

///|
#export_name("clientInstallationPreparationUseWire")
pub fn client_installation_preparation_use_wire(
  value : @credential.InstallationPreparationCredentialUse,
) -> String raise NodeHostFailure {
  installation_credential_result(value.original_wire())
}

///|
#export_name("clientInstallationPreparationUseCid")
pub fn client_installation_preparation_use_cid(
  value : @credential.InstallationPreparationCredentialUse,
) -> String {
  value.cid()
}

///|
#export_name("clientInstallationPreparationUseProjection")
pub fn client_installation_preparation_use_projection(
  value : @credential.InstallationPreparationCredentialUse,
) -> Array[String] {
  let (cid, grant, id, ordinal) = value.projection()
  [cid, grant, id, ordinal.to_string()]
}

///|
#export_name("clientInstallationPreparationUseCheck")
pub fn client_installation_preparation_use_check(
  value : @credential.InstallationPreparationCredentialUse,
  now : Int64,
  revoked : Bool,
  actual : @credential.InstallationPreparationCredentialScope,
) -> Unit raise NodeHostFailure {
  installation_credential_result(
    @credential.authorize_installation_preparation_credential_use(
      value, now, revoked, actual,
    ),
  )
}

///|
#export_name("clientInstallationPreparationSignaturePreimage")
pub fn client_installation_preparation_signature_preimage(
  value : @credential.InstallationPreparationCredentialGrant,
) -> Bytes raise NodeHostFailure {
  installation_credential_result(
    @credential.installation_preparation_credential_signature_preimage(value),
  )
}

///|
#export_name("clientInstallationPreparationSignaturePrepare")
pub fn client_installation_preparation_signature_prepare(
  grant : @credential.InstallationPreparationCredentialGrant,
  key : String,
  signature : String,
) -> @credential.InstallationPreparationCredentialSignatureEnvelope raise NodeHostFailure {
  installation_credential_result(
    @credential.prepare_installation_preparation_credential_signature_envelope(
      grant, key, signature,
    ),
  )
}

///|
#export_name("clientInstallationPreparationSignatureAdmit")
pub fn client_installation_preparation_signature_admit(
  subject : @credential.InstallationPreparationSubject,
  version : String,
  key : String,
  grant : String,
  body : String,
  signature : String,
) -> @credential.InstallationPreparationCredentialSignatureEnvelope raise NodeHostFailure {
  installation_credential_result(
    @credential.admit_installation_preparation_credential_signature_envelope(
      subject, version, key, grant, body, signature,
    ),
  )
}

///|
#export_name("clientInstallationPreparationSignatureProjection")
pub fn client_installation_preparation_signature_projection(
  value : @credential.InstallationPreparationCredentialSignatureEnvelope,
) -> Array[String] {
  let (version, key, grant, body, signature, issuer) = value.projection()
  [version, key, grant, body, signature, issuer]
}

///|
#export_name("clientInstallationPreparationSignatureGrant")
pub fn client_installation_preparation_signature_grant(
  value : @credential.InstallationPreparationCredentialSignatureEnvelope,
) -> @credential.InstallationPreparationCredentialGrant {
  value.grant()
}
