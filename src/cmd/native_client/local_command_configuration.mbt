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
  run_original : LocalCommandRunInstallationOriginal?
}

///|
// Parsed configuration DATA for this command's selected bytes. This holds no
// Store, Root, permission or current decision independently of its capture.
priv struct LocalCommandRunInstallationOriginal {
  name : String
  body : Bytes
  installation : LocalRunInstallation
}

///|
fn local_command_run_installation_original(
  name : String,
  text : String,
) -> LocalCommandRunInstallationOriginal raise ClientStop {
  let installation = local_run_installation(text)
  { name, body: @utf8.encode(text), installation, }
}

///|
fn LocalCommandRunInstallationOriginal::select(
  self : LocalCommandRunInstallationOriginal,
  name : String,
  body : Bytes,
) -> LocalRunInstallation? {
  if self.name == name && self.body == body {
    Some(self.installation)
  } else {
    None
  }
}

///|
fn LocalCommandConfiguration::run_installation(
  self : LocalCommandConfiguration,
  name : String,
  body : Bytes,
) -> LocalRunInstallation raise ClientStop {
  guard self.settings.run_file == Some(name) &&
    self.run_original is Some(original) &&
    original.name == name else {
    stop("LocalRunOriginalNotSelected")
  }
  // Each closed caller obtains these bytes through its actual current Read.
  // This DATA projection cannot supply a Read, permission or replacement.
  original
  .select(name, body)
  .unwrap_or_else(() => stop("LocalConfigurationChanged"))
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
