///|
// Only authenticated initial Host originals may use the distinct Host-purpose
// storage entry. Existing Reviewer callers/records keep their original law.
fn local_initial_signing_original_history_locked(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
) -> Result[
  @credential_resource.NativeLocalSigningHistoryCandidate,
  @credential_resource.NativeCredentialResourceIssue,
] {
  guard original.grant is SigningGrant(grant) else {
    return Err(@credential_resource.InvalidConfiguration)
  }
  if @credential.local_signing_credential_grant_scope(grant).purpose ==
    @credential.HostAttestation {
    if original.initial_issue is None {
      return Err(@credential_resource.InvalidConfiguration)
    }
    @credential_resource.prepare_native_local_initial_host_signing_history_candidate(
      host.database,
      grant,
    )
  } else {
    @credential_resource.prepare_native_local_original_signing_history_candidate(
      host.database,
      grant,
    )
  }
}
