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
