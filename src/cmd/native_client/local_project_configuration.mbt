///|
// Project input metadata stays separate from authenticated installation
// originals. It cannot issue an Account decision, capture, grant or Run.
priv struct LocalProjectConfiguration {
  metadata : @run_host.ClientProjectConfiguration
  directory : String
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
    directory,
    state_directory,
    profile: match optional(matches, "profile") {
      Some(value) => Some(value)
      None => metadata.selected_profile()
    },
  }
}

///|
fn local_project_read(
  matches : @argparse.Matches,
) -> Result[LocalProjectConfiguration?, @files.NativeBoundedTextFailure] raise ClientStop {
  let selected = optional(matches, "config")
  if selected is None && optional(matches, "profile") is None {
    return Ok(None)
  }
  if required(matches, "mode") != "local" {
    stop("Local project configuration is unavailable in Remote mode")
  }
  if matches.sources.get("config-file") is Some(@argparse.Argv) ||
    matches.sources.get("config-root") is Some(@argparse.Argv) {
    stop("ConflictingLocalProjectSelection")
  }
  let selected = selected.unwrap_or_else(() => {
    stop("ProjectConfigurationRequired")
  })
  let cwd = @env.current_dir().unwrap_or_else(() => {
    stop("ProjectConfigurationDirectoryUnavailable")
  })
  let absolute = local_project_absolute_path(cwd, selected)
  let location = local_product_selected_location(Some(absolute), None)
  // The existing Reader owns no-follow/generation/UTF-8 and close. Propagate
  // its original failure carrier, including rejected constructor custody.
  match
    @files.read_bounded_text_file_with_custody(
      location.parent_path,
      location.directory_name,
      65536L,
    ) {
    Ok(wire) =>
      Ok(Some(local_project_select_loaded(matches, location.parent_path, wire)))
    Err(original) => Err(original)
  }
}

///|
fn local_project_require_execution_bindings(
  selected : LocalProjectConfiguration,
  operation : String,
) -> Unit raise ClientStop {
  // Saved Run operations use their retained installation/materials, never
  // fresh project declarations to repair or recompile an original Run.
  if ![
      "adopt", "connect", "check", "explain", "run", "aql", "start", "new-submission",
    ].contains(operation) {
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
fn execute_native_project_selection(
  matches : @argparse.Matches,
) -> Result[String, @files.NativeBoundedTextFailure] raise ClientStop {
  let selected = match local_project_read(matches) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  if selected is Some(project) {
    let (operation, _) = matches.subcommand.unwrap_or_else(() => {
      stop("LocalOperationUnavailable")
    })
    local_project_require_execution_bindings(project, operation)
    matches.values["state-dir"] = [project.state_directory]
  }
  Ok(execute(matches))
}
