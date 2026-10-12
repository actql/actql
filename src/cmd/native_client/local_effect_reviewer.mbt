///|
// Selecting public registration syntax does not authenticate a Reviewer or
// authorize review disclosure. The original file joins ordinary Host adoption.
fn local_selected_effect_reviewer_original(
  root : String,
  settings : LocalHostSettings,
) -> (String, Bytes)? raise ClientStop {
  guard settings.reviewer_file is Some(file) else { return None }
  if !settings.installation_files.contains(file) {
    stop("LocalReviewerOriginalNotSelected")
  }
  let body = text_file(root, file, 8192L)
  if @local_host.admit_native_local_effect_reviewer_selection(body) is Err(_) {
    stop("InvalidLocalReviewerInstallation")
  }
  Some((file, @utf8.encode(body)))
}

///|
// The actual original custody Owner supplies the opaque approval scope. The
// CLI does not manufacture it from a Resolution, request CID or current file.
// Original Client read and the registered Reviewer's independent resolve are
// checked by the adopted Host; this caller owns no permission or send permit.
fn local_bind_effect_reviewer(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  reference : @local_host.NativeClientSubmissionReference,
  request : @run_host.ClientRequestIdentity,
  approval_scope : @source_owner.ResidentOriginalEffectApprovalScope,
) -> Result[
  @local_host.NativeLocalEffectReviewerBinding,
  @local_host.NativeLocalEffectReviewerBindingIssue,
] {
  host.bind_effect_reviewer(
    crypto,
    settings.principal,
    settings.connection,
    reference,
    request,
    approval_scope,
    () => @env.now().to_double(),
    configuration_file=settings.reviewer_file,
  )
}
