///|
priv struct LocalOperatorHostLocation {
  base_path : String
  directories : Array[String]
  name : String
  create_default : Bool
}

///|
// Explicit operator selection never consults HOME or the Project. Resolve its
// relative path against the original command cwd, not the submitted document.
fn local_operator_host_location(
  selected : String?,
  cwd : String,
  read_home : () -> String? raise ClientStop,
  initialize? : Bool = false,
) -> LocalOperatorHostLocation raise ClientStop {
  match selected {
    Some(path) => {
      let absolute = local_project_absolute_path(cwd, path, ordinary_file=true)
      let location = local_product_selected_location(Some(absolute), None)
      {
        base_path: location.parent_path,
        directories: [],
        name: location.directory_name,
        create_default: false,
      }
    }
    None => {
      let home = read_home().unwrap_or_else(() => {
        stop("LocalHostHomeUnavailable")
      })
      if !local_product_path(home) {
        stop("LocalHostHomeUnavailable")
      }
      {
        base_path: home,
        directories: [".config", "actql"],
        name: "host.json",
        create_default: initialize,
      }
    }
  }
}

///|
// The current Native default installer implements the absent-policy Host.
// Never silently ignore a configured Account/policy/signer and use its local
// default key instead. Those explicit configurations need their own consumer.
fn local_operator_host_require_initial_default(
  wire : String,
) -> Unit raise ClientStop {
  let fields = @decode.closed_object(local_input_cursor(wire), ["version"]).unwrap_or_else(() => {
      stop("LocalConfiguredHostInstallationUnavailable")
    },
  )
  let version = @decode.required(fields, "version")
    .bind(value => @decode.text(value))
    .unwrap_or_else(() => stop("InvalidLocalHostConfiguration"))
  if version != "actql-host/0.1" {
    stop("InvalidLocalHostConfiguration")
  }
}

///|
fn LocalCommandPreparationOriginal::select_operator_host(
  self : LocalCommandPreparationOriginal,
  matches : @argparse.Matches,
  initialize : Bool,
) -> String raise ClientStop {
  if !self.phase_open || self.closing || self.closed || self.primary is Some(_) {
    stop("LocalCommandPreparationUnavailable")
  }
  if self.operator_host is None {
    let cwd = @env.current_dir().unwrap_or_else(() => {
      stop("LocalHostPathUnavailable")
    })
    let location = local_operator_host_location(
      optional(matches, "host-config"),
      cwd,
      local_product_bounded_home,
      initialize~,
    )
    let capture = command_preparation_result(
      @local_host.prepare_native_local_operator_host_capture_in_current_read_context(
        location.base_path,
        location.directories,
        location.name,
        location.create_default,
        self.profile.diagnostic_ceiling,
      ).map_err(issue => CommandAdoption(issue)),
      stage=Some("operator-host-prepare"),
    )
    self.operator_host = Some(capture)
  }
  let capture = self.operator_host.unwrap()
  let original = match capture.open() {
    Ok(original) => original
    Err(issue) => {
      self.retain_primary(CommandAdoption(issue))
      command_preparation_result(
        Err(CommandAdoption(issue)),
        stage=Some("operator-host-open"),
      )
    }
  }
  if self.operator_host_wire is Some(wire) {
    // Keep the once-decoded immutable selection. Only its physical current
    // observation is repeated at a later boundary, not the policy admission.
    command_preparation_result(
      original.check_current().map_err(issue => CommandAdoption(issue)),
      stage=Some("operator-host-current"),
    )
    return wire
  }
  let wire = command_preparation_result(
    original.original_wire().map_err(issue => CommandAdoption(issue)),
    stage=Some("operator-host-original"),
  )
  local_operator_host_require_initial_default(wire)
  self.operator_host_wire = Some(wire)
  wire
}
