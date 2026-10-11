///|
/// Install the two distinct original-custody boundaries on the existing
/// Resource service: the original Site Journal claim before fresh use selection,
/// and the same Journal's nominal-use retention after Resource persistence.
/// The callbacks do not grant read/write/approval or prove Provider execution.
/// Local and Local-preparation operations never invoke either Remote callback.
///
/// The trusted Host supplies the actual original Journal/context and retains
/// failed or uncertain claims. It must not return success from missing records,
/// a replacement DB, candidate dispatch bytes or a reconstructed grant. Current
/// Host authorization and credential lifetime/revocation remain independent.
pub fn install_native_credential_resource_service_with_initial_use_claim(
  database : @sqlite.Database,
  client : @http.Client,
  operations : Array[NativeCredentialOperation],
  authorize : (NativeCredentialAuthorization) -> Bool,
  claim_initial_use : (@credential.RemoteCredentialGrant, String, NativeCredentialScope) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ],
  retain_use : (@credential.RemoteCredentialUse) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ],
) -> Result[NativeCredentialResourceService, NativeCredentialResourceIssue] {
  install_native_credential_resource_service_with_clock(
    database,
    client,
    operations,
    authorize,
    fn() { @env.now().reinterpret_as_int64() },
    claim_initial_remote_use=Some(claim_initial_use),
    retain_remote_use=Some(retain_use),
  )
}
