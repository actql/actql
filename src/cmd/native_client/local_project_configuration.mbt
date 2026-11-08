///|
// Project input metadata stays separate from authenticated installation
// originals. It cannot issue an Account decision, capture, grant or Run.
priv struct LocalProjectConfiguration {
  metadata : @run_host.ClientProjectConfiguration
  directory : String
  source_free_bindings : @run_host.ClientSourceFreeProjectBindings?
  mock_declarations : LocalProjectMockDeclarations?
  state_directory : String
  profile : String?
}

///|
fn local_project_absolute_path(
  directory : String,
  selected : String,
  ordinary_file? : Bool = false,
  ordinary_directory? : Bool = false,
) -> String raise ClientStop {
  if (directory != "/" && !local_product_path(directory)) ||
    (!ordinary_file && directory.contains("\\")) ||
    selected.is_empty() ||
    selected.length() > 4096 ||
    (!ordinary_file && selected.contains("\\")) ||
    selected.contains("\u{0000}") {
    stop("InvalidProjectConfigurationPath")
  }
  let combined = if selected.has_prefix("/") {
    selected
  } else {
    directory + "/" + selected
  }
  let parts : Array[String] = []
  for part in combined.split("/") {
    match part {
      "" | "." => ()
      ".." => {
        if parts.is_empty() {
          stop("InvalidProjectConfigurationPath")
        }
        ignore(parts.pop())
      }
      _ => parts.push(part.to_owned())
    }
  }
  let absolute = "/" + parts.join("/")
  if !(ordinary_file && ordinary_directory && absolute == "/") &&
    !local_product_path(absolute) {
    stop("InvalidProjectConfigurationPath")
  }
  absolute
}

///|
fn local_project_select_loaded(
  matches : @argparse.Matches,
  directory : String,
  wire : String,
) -> LocalProjectConfiguration raise ClientStop {
  let metadata = @run_host.admit_client_project_configuration(wire).unwrap_or_else(() => {
      stop("InvalidProjectConfiguration")
    },
  )
  let state_directory = match optional(matches, "state-dir") {
    Some(explicit) => {
      // Preserve the existing flag's explicit absolute installation contract.
      ignore(local_product_selected_location(Some(explicit), None))
      explicit
    }
    None => local_project_absolute_path(directory, metadata.state_directory())
  }
  ignore(local_product_selected_location(Some(state_directory), None))
  {
    metadata,
    directory,
    source_free_bindings: None,
    mock_declarations: None,
    state_directory,
    profile: match optional(matches, "profile") {
      Some(value) => Some(value)
      None => metadata.selected_profile()
    },
  }
}

///|
// This chooses a frontend route only. A project cannot create adoption,
// authority or a saved Run. Explicit Remote and legacy roots stay explicit.
fn local_project_default_local_candidate(
  matches : @argparse.Matches,
) -> Bool raise ClientStop {
  if !(matches.sources.get("mode") is Some(@argparse.Default)) ||
    required(matches, "mode") != "remote" ||
    matches.sources.get("config-file") is Some(@argparse.Argv) ||
    matches.sources.get("config-root") is Some(@argparse.Argv) {
    return false
  }
  for
    name in [
      "endpoint", "connection-root", "connection-file", "token-root", "token-file",
      "http-library", "ca", "cert", "key",
    ] {
    if optional(matches, name) is Some(_) {
      return false
    }
  }
  true
}

///|
// Saved public operands select only an existing Local installation. The
// original Run/Account/Store lookup remains authoritative; no ref file is
// inferred and this selection never authorizes initialization or a new Run.
fn local_project_saved_run_requested(
  matches : @argparse.Matches,
) -> Bool raise ClientStop {
  guard matches.subcommand is Some((operation, child)) &&
    optional(child, "ref-file") is None &&
    optional(child, "submission-ref-file") is None else {
    return false
  }
  if operation == "result" {
    optional(child, "run") is Some(_)
  } else if operation == "status" {
    optional(child, "run") is Some(_) || optional(child, "run-id") is Some(_)
  } else {
    false
  }
}

///|
fn local_project_discovery_selected(
  matches : @argparse.Matches,
) -> Bool raise ClientStop {
  optional(matches, "config") is None &&
  (
    required(matches, "mode") == "local" ||
    local_project_default_local_candidate(matches)
  ) &&
  !(matches.sources.get("config-file") is Some(@argparse.Argv)) &&
  !(matches.sources.get("config-root") is Some(@argparse.Argv))
}

///|
fn local_project_parent_directory(
  directory : String,
) -> String? raise ClientStop {
  if directory == "/" {
    None
  } else {
    Some(local_product_selected_location(Some(directory), None).parent_path)
  }
}

///|
fn local_project_requires_read(
  matches : @argparse.Matches,
) -> Bool raise ClientStop {
  let explicit = optional(matches, "config")
  let discover = local_project_discovery_selected(matches)
  if explicit is None && !discover && optional(matches, "profile") is None {
    return false
  }
  if required(matches, "mode") != "local" &&
    !local_project_default_local_candidate(matches) {
    stop("Local project configuration is unavailable in Remote mode")
  }
  if explicit is Some(_) &&
    (
      matches.sources.get("config-file") is Some(@argparse.Argv) ||
      matches.sources.get("config-root") is Some(@argparse.Argv)
    ) {
    stop("ConflictingLocalProjectSelection")
  }
  if explicit is None && !discover {
    stop("ProjectConfigurationRequired")
  }
  true
}

///|
fn local_project_read_from(
  matches : @argparse.Matches,
  starting_directory : String,
) -> Result[LocalProjectConfiguration?, @files.NativeBoundedTextFailure] raise ClientStop {
  if !local_project_requires_read(matches) {
    return Ok(None)
  }
  let explicit = optional(matches, "config")
  let discover = local_project_discovery_selected(matches)
  let selected = explicit.unwrap_or("actql.config.json")
  if selected.has_suffix("/") {
    stop("InvalidProjectConfigurationPath")
  }
  let absolute = local_project_absolute_path(starting_directory, selected)
  let initial = local_product_selected_location(Some(absolute), None)
  let mut directory = initial.parent_path
  while true {
    // One exact generation at a time. The existing Reader retains rejected
    // constructor/close custody; only acknowledged absence may advance to a
    // parent. Malformed, unreadable or changed nearer files never fall back.
    match command_project_original_text(directory, initial.directory_name) {
      Ok(wire) =>
        return Ok(Some(local_project_select_loaded(matches, directory, wire)))
      Err(original) => {
        if !discover || !(original.issue() is @files.Missing) {
          return Err(original)
        }
        if original.retry_cleanup() is Err(_) {
          return Err(original)
        }
        match local_project_parent_directory(directory) {
          Some(parent) => directory = parent
          None => {
            if optional(matches, "profile") is Some(_) {
              stop("ProjectConfigurationRequired")
            }
            return Ok(None)
          }
        }
      }
    }
  } nobreak {
    stop("ProjectConfigurationDirectoryUnavailable")
  }
}

///|
fn local_project_read(
  matches : @argparse.Matches,
) -> Result[LocalProjectConfiguration?, @files.NativeBoundedTextFailure] raise ClientStop {
  native_timing_begin(11)
  defer native_timing_end(11)
  // Explicit Remote/legacy choices never probe project files. A default-mode
  // candidate remains unchanged until a complete metadata read has succeeded.
  if !local_project_requires_read(matches) {
    return Ok(None)
  }
  let cwd = @env.current_dir().unwrap_or_else(() => {
    stop("ProjectConfigurationDirectoryUnavailable")
  })
  local_project_read_from(matches, cwd)
}

///|
fn local_project_execution_operation(operation : String) -> Bool {
  ["check", "explain", "run", "sql", "aql", "start", "new-submission"].contains(
    operation,
  )
}

///|
// Implementation availability, never an installed binding or permission.
// Keep discovery and project admission on the same Native owner predicate.
fn local_project_binding_implementation(
  profile : String?,
  mock_inputs : Bool,
) -> Bool {
  (profile is None && !mock_inputs) || (profile == Some("mock") && mock_inputs)
}

///|
fn local_project_init_support() -> String {
  "{\"version\":\"actql-project-init-support/0.1\",\"sourceFree\":" +
  local_project_binding_implementation(None, false).to_string() +
  ",\"mock\":" +
  local_project_binding_implementation(Some("mock"), true).to_string() +
  "}"
}

///|
fn local_project_require_supported_profile(
  selected : LocalProjectConfiguration,
  operation : String,
) -> Unit raise ClientStop {
  if !local_project_execution_operation(operation) {
    return
  }
  let metadata = selected.metadata
  if metadata.lock_file() is Some(_) {
    stop("LocalProjectBindingsUnavailable")
  }
  if selected.profile == Some("mock") {
    // Availability DATA is not a selected installation. Only the exact closed
    // declaration original may reach the existing Command's Mock assembler.
    guard selected.mock_declarations is Some(mock) &&
      !mock.closing &&
      !mock.retired &&
      @run_host.client_project_profile_matches(
        mock.profile,
        Some(metadata),
        selected.profile,
      ) else {
      stop("LocalProjectBindingsUnavailable")
    }
    return
  }
  if !local_project_binding_implementation(
      selected.profile,
      metadata.mock_catalog_file() is Some(_) ||
      metadata.mock_data_file() is Some(_) ||
      metadata.mock_answer_count() != 0,
    ) {
    stop("LocalProjectBindingsUnavailable")
  }
}

///|
fn local_project_require_execution_bindings(
  selected : LocalProjectConfiguration,
  operation : String,
) -> Unit raise ClientStop {
  // Connection and saved operations retain their original installation. No
  // current project file can repair/recompile a saved Run or refresh policy.
  local_project_require_supported_profile(selected, operation)
  if !local_project_execution_operation(operation) {
    return
  }
  let metadata = selected.metadata
  if selected.profile == Some("mock") {
    // prepare_project_input already retained these SAME declarations before
    // their fallible Source/Model construction. No standalone intake, equal
    // copy or availability reply may stand in for that live Command Read.
    guard selected.mock_declarations is Some(mock) &&
      mock.sources_started &&
      mock.model_started &&
      mock.model_failure is None &&
      mock.model_profile is Some(_) &&
      command_preparation_invocation.val is Some(original) &&
      !original.closing &&
      !original.closed &&
      original.primary is None &&
      original.project is Some(retained) &&
      retained.mock_declarations is Some(retained_mock) &&
      physical_equal(mock, retained_mock) &&
      physical_equal(metadata, retained.metadata) &&
      original.host is Some(host) &&
      original.read is Some(read) else {
      stop("LocalProjectBindingsUnavailable")
    }
    match local_project_input_read_current(host, read, original.pair) {
      Ok(_) => ()
      Err(issue) => {
        original.retain_primary(issue)
        stop("LocalProjectBindingsUnavailable")
      }
    }
    return
  }
  if metadata.connectors_file() is Some(_) ||
    metadata.model_tasks_file() is Some(_) {
    guard selected.source_free_bindings is Some(bindings) &&
      bindings.has_connectors_file() == (metadata.connectors_file() is Some(_)) &&
      bindings.has_model_tasks_file() ==
      (metadata.model_tasks_file() is Some(_)) else {
      stop("LocalProjectBindingsUnavailable")
    }
  }
}

///|
fn local_project_read_declaration(
  selected : LocalProjectConfiguration,
  name : String?,
) -> Result[String?, @files.NativeBoundedTextFailure] raise ClientStop {
  guard name is Some(name) else { return Ok(None) }
  if name.has_suffix("/") {
    stop("InvalidProjectConfigurationPath")
  }
  let absolute = local_project_absolute_path(selected.directory, name)
  let location = local_product_selected_location(Some(absolute), None)
  // The same bounded Reader owns constructor/next/close custody. Missing,
  // malformed or physically refused declarations never become empty defaults.
  command_project_original_text(location.parent_path, location.directory_name).map(wire => {
      Some(wire)
    },
  )
}

///|
fn local_project_read_execution_bindings(
  selected : LocalProjectConfiguration?,
  operation : String,
) -> Result[LocalProjectConfiguration?, @files.NativeBoundedTextFailure] raise ClientStop {
  guard selected is Some(project) &&
    (local_project_execution_operation(operation) || operation == "adopt") else {
    return Ok(selected)
  }
  // Intake the exact public Mock documents independently of installation.
  // The later execution gate requires the same retained Command and prepared
  // Source/Model originals; declaration DATA cannot select a live installation.
  let metadata = project.metadata
  if project.profile == Some("mock") &&
    metadata.lock_file() is None &&
    metadata.connectors_file() is Some(_) &&
    metadata.model_tasks_file() is Some(_) &&
    metadata.mock_catalog_file() is Some(_) &&
    metadata.mock_data_file() is Some(_) &&
    metadata.mock_answer_count() > 0 {
    return match
      local_project_read_mock_declarations(
        project,
        local_project_mock_task_limits(),
      ) {
      Ok(original) =>
        Ok(Some({ ..project, mock_declarations: Some(original), }))
      Err(original) => Err(original)
    }
  }
  // Ordinary adoption does not intake execution declarations. Only the
  // explicitly selected closed Mock branch above needs first-install subjects.
  if operation == "adopt" {
    if project.profile == Some("mock") {
      stop("LocalProjectBindingsUnavailable")
    }
    return Ok(selected)
  }
  // Other unsupported profiles still refuse before declaration IO.
  local_project_require_supported_profile(project, operation)
  let connectors = match
    local_project_read_declaration(project, project.metadata.connectors_file()) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  let model_tasks = match
    local_project_read_declaration(project, project.metadata.model_tasks_file()) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  let bindings = match
    @run_host.admit_client_source_free_project_bindings(connectors, model_tasks) {
    Ok(value) => value
    Err(@run_host.BindingsUnavailable) =>
      stop("LocalProjectBindingsUnavailable")
    Err(@run_host.InvalidBindings) => stop("InvalidProjectBindings")
  }
  // These facts only rule out uninstalled declarations. Actual check/run still
  // restores the selected Host's saved environment through its original Owner;
  // it never assembles replacement environment/policy from project metadata.
  Ok(Some({ ..project, source_free_bindings: Some(bindings), }))
}

///|
fn local_project_apply_selection(
  matches : @argparse.Matches,
  selected : LocalProjectConfiguration?,
) -> Unit raise ClientStop {
  if selected is Some(project) {
    let (operation, _) = matches.subcommand.unwrap_or_else(() => {
      stop("LocalOperationUnavailable")
    })
    local_project_require_execution_bindings(project, operation)
    if local_project_default_local_candidate(matches) {
      matches.values["mode"] = ["local"]
    }
    matches.values["state-dir"] = [project.state_directory]
  } else if local_project_default_local_candidate(matches) &&
    matches.subcommand is Some((operation, child)) &&
    (
      local_quick_query_requested(operation, child) ||
      local_project_saved_run_requested(matches)
    ) {
    // Literal queries may initialize only under their existing first-use rule.
    // Saved operands only restore that original Host. Explicit Remote and
    // connection choices never enter this branch.
    matches.values["mode"] = ["local"]
  }
}

///|
fn execute_native_project_selection(
  matches : @argparse.Matches,
) -> Result[String, @files.NativeBoundedTextFailure] raise ClientStop {
  normalize_native_query_arguments(matches)
  normalize_native_program_arguments(matches)
  normalize_native_status_arguments(matches)
  let selected = match local_project_read(matches) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  let (operation, _) = matches.subcommand.unwrap_or_else(() => {
    stop("LocalOperationUnavailable")
  })
  let selected = match
    local_project_read_execution_bindings(selected, operation) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  // Retain the original Project in the existing command BEFORE assembling
  // cyclic Model originals. Pending retirement remains on that same carrier.
  let retained = match command_preparation_invocation.val {
    Some(original) => {
      match original.prepare_project_input(selected) {
        Ok(_) => ()
        Err(issue) => {
          original.retain_primary(issue)
          stop("InvalidProjectBindings")
        }
      }
      true
    }
    None => false
  }
  // The standalone Reader component has no command carrier or Model users.
  defer (if !retained &&
    selected is Some(project) &&
    project.mock_declarations is Some(original) {
    original.retire()
  })
  local_project_apply_selection(matches, selected)
  Ok(execute(matches))
}

///|
// The same command retains this Project before any Model original is made.
// Its current physical Read is required; metadata/Bool/capacity DATA cannot
// substitute for that live scope. No Host, Request or Ledger is created here.
fn local_project_input_read_current(
  host : @initial_arena.InstalledArenaHost,
  read : @initial_arena.InstalledArenaOriginalRead,
  pair : @initial_arena.InstalledArenaLocalHostResources?,
) -> Result[Unit, LocalCommandPreparationIssue] {
  match pair {
    None =>
      host
      .require_domain_original_read_current(read)
      .map_err(issue => CommandRead(issue))
    Some(pair) =>
      // The actual Command has spent its available-read claim. Match this
      // SAME consuming pair/read and its entered physical allocation scope.
      // Standalone declaration readers keep the original available-read port.
      match host.observe_local_host_consuming_read_scope(pair, read) {
        Ok(ReadEntered) => Ok(())
        Ok(ReadUnentered) => Err(CommandUnavailable)
        Err(issue) => Err(CommandPair(issue))
      }
  }
}

///|
fn LocalCommandPreparationOriginal::prepare_project_input(
  self : LocalCommandPreparationOriginal,
  selected : LocalProjectConfiguration?,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard !self.closing &&
    !self.closed &&
    self.primary is None &&
    self.project is None &&
    self.host is Some(host) &&
    self.read is Some(read) else {
    return Err(CommandUnavailable)
  }
  match local_project_input_read_current(host, read, self.pair) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.project = selected
  if selected is Some(project) && project.mock_declarations is Some(mock) {
    match mock.prepare_source_declarations() {
      Ok(_) => ()
      Err(issue) => return Err(CommandProjectMock(issue))
    }
    match
      mock.prepare_models(
        local_project_mock_task_limits(),
        local_project_mock_answer_limits(),
        local_utc_now,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(CommandProjectMock(issue))
    }
  }
  Ok(())
}
