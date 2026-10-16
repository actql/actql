///|
// Project input metadata stays separate from authenticated installation
// originals. It cannot issue an Account decision, capture, grant or Run.
priv struct LocalProjectConfiguration {
  metadata : @run_host.ClientProjectConfiguration
  state_directory : String
  profile : String?
}

///|
fn local_project_absolute_path(
  directory : String,
  selected : String,
) -> String raise ClientStop {
  if (directory != "/" && !local_product_path(directory)) ||
    directory.contains("\\") ||
    selected.is_empty() ||
    selected.length() > 4096 ||
    selected.contains("\\") ||
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
  if !local_product_path(absolute) {
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
    match
      @files.read_bounded_text_file_with_custody(
        directory,
        initial.directory_name,
        65536L,
      ) {
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
fn local_project_require_execution_bindings(
  selected : LocalProjectConfiguration,
  operation : String,
) -> Unit raise ClientStop {
  // Adoption/connection select installation metadata only; project declarations
  // cannot issue Host authority or execute mocks. Saved Run operations use their
  // retained installation/materials, never
  // fresh project declarations to repair or recompile an original Run.
  if !["check", "explain", "run", "aql", "start", "new-submission"].contains(
      operation,
    ) {
    return
  }
  let metadata = selected.metadata
  if metadata.connectors_file() is Some(_) ||
    metadata.model_tasks_file() is Some(_) ||
    metadata.lock_file() is Some(_) ||
    selected.profile is Some(_) ||
    metadata.mock_data_file() is Some(_) ||
    metadata.mock_answer_count() != 0 {
    // The Native connector/model/mock assembler is not installed yet. Never
    // interpret the project profile as permission or silently run live IO.
    stop("LocalProjectBindingsUnavailable")
  }
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
  }
}

///|
fn execute_native_project_selection(
  matches : @argparse.Matches,
) -> Result[String, @files.NativeBoundedTextFailure] raise ClientStop {
  normalize_native_program_arguments(matches)
  let selected = match local_project_read(matches) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  local_project_apply_selection(matches, selected)
  Ok(execute(matches))
}
