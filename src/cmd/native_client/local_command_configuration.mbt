///|
// Immutable preparation DATA for one command. The original Session and capture
// still join the selected bytes; this record supplies no current or Account
// decision, physical capacity, signing key or replacement installation.
priv struct LocalCommandConfiguration {
  configuration_name : String
  configuration_body : Bytes
  settings : LocalHostSettings
  environment_name : String
  environment_body : Bytes
  environment : @checked.CheckEnvironment?
}

///|
fn local_admitted_check_environment(
  environment : String,
  evidence : String,
) -> @checked.CheckEnvironment? {
  // Count actual Environment admissions, not uses of the typed result.
  native_timing_count(21)
  @run_host.admit_client_check_environment(
    environment,
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
// Saved operations restore their checked Run/Checkpoint originals. They do
// not prepare a Program using the installation's current Environment. This
// does not skip selection, custody or either independent read permission.
fn local_command_check_environment(
  operation : String,
  child : @argparse.Matches,
  environment : String,
  evidence : String,
) -> @checked.CheckEnvironment? raise ClientStop {
  if operation == "result" ||
    operation == "status" ||
    operation == "approve" ||
    operation == "reject" ||
    (operation == "explain" && optional(child, "run") is Some(_)) {
    return None
  }
  Some(
    local_admitted_check_environment(environment, evidence).unwrap_or_else(() => {
      stop("InvalidLocalCheckEnvironment")
    }),
  )
}

///|
fn LocalCommandConfiguration::checked_environment(
  self : LocalCommandConfiguration,
) -> @checked.CheckEnvironment raise ClientStop {
  self.environment.unwrap_or_else(() => {
    stop("LocalBusinessEnvironmentUnavailable")
  })
}
