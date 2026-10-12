///|
// This finite product profile uses the actual explicit selection; no directory
// discovery, default profile fabrication or replacement of adopted originals.
fn local_run_policy_binding(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
) -> @local_host.NativeLocalRunPolicyBinding? raise ClientStop {
  match settings.run_policy_profile_file {
    None =>
      match (settings.read_file, settings.run_file) {
        (Some(read), Some(run)) =>
          host
          .bind_upgraded_run_policy(
            crypto,
            settings.principal,
            settings.connection,
            read,
            run,
          )
          .unwrap_or_else(() => stop("LocalRunPolicyOriginalUnavailable"))
        _ => None
      }
    Some(profile) =>
      Some(
        host
        .bind_run_policy_profile_for_read(
          crypto,
          settings.principal,
          settings.connection,
          profile,
          settings.read_file.unwrap_or_else(() => {
            stop("LocalReadPolicyOriginalNotSelected")
          }),
          settings.run_file.unwrap_or_else(() => {
            stop("LocalRunOriginalNotSelected")
          }),
        )
        .unwrap_or_else(() => stop("LocalRunPolicyOriginalUnavailable")),
      )
  }
}
