///|
/// Explicit Python worker first-adoption selection, staged by the existing
/// durable configuration Owner. Existing installation witnesses must match
/// exactly; this entry never supplements a restored Account. Restoration uses
/// restore_native_local_product_configuration and its retained original files.
/// The returned session must stage_configuration and close before Host adoption.
pub fn begin_native_local_python_worker_configuration(
  parent_path : String,
  directory_name : String,
  observed_at : String,
  crypto : @crypto.Library,
) -> Result[NativeLocalProductConfigurationSession, NativeLocalAdoptionIssue] {
  if !local_adoption_name(directory_name) {
    return Err(InvalidInput)
  }
  let selected = match
    @host.client_local_product_python_worker_bootstrap_originals(
      parent_path + "/" + directory_name,
      observed_at,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidInput)
  }
  let common = selected.original.common
  // Account plus eight originals: the existing selection and per-file limits.
  begin_native_local_product_configuration(
    parent_path,
    directory_name,
    [
      ("account.json", common.account),
      ("environment.json", @utf8.encode(selected.original.environment)),
      ("compute.json", @utf8.encode(selected.original.compute)),
      ("retention.json", common.retention_dependencies),
      ("retention-policy.json", common.retention_policy),
      ("store.json", common.store),
      ("result-policy.json", common.result_policy),
      (
        "profile.json",
        @utf8.encode(
          @host.client_local_run_policy_profile_wire(selected.profile),
        ),
      ),
      (
        "read.json",
        @utf8.encode(
          @publication.local_sdk_result_read_selection_wire(selected.read),
        ),
      ),
    ],
    crypto,
  )
}
