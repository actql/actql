///|
// The launcher supplies installation metadata, never execution authority.
// Every file still passes the existing no-follow generation-pinned Owner.
priv struct LocalPackagedRuntime {
  manifest : @run_host.ClientNativeLocalRuntime
  sqlite : String
  crypto : String
  assets : @run_host.ClientLocalProductAssets
  installed_contracts : @local_values.ClientInstalledSequenceContracts
  physical : @local_host.NativeLocalPackagedRuntime
}

///|
// A location is operator-selected metadata, never configuration custody or
// authority. The existing installation Owner still creates/restores its exact
// original child and refuses an existing child without its original witness.
priv struct LocalProductLocation {
  parent_path : String
  directory_name : String
}

///|
fn local_product_selected_location(
  state_directory : String?,
  home : String?,
) -> LocalProductLocation raise ClientStop {
  match state_directory {
    None => {
      let home = home.unwrap_or_else(() => stop("LocalProductHomeUnavailable"))
      if !local_product_path(home) {
        stop("LocalProductHomeUnavailable")
      }
      { parent_path: home, directory_name: ".actql-local", }
    }
    Some(path) => {
      // The project loader resolves paths relative to the selected config.
      // Keep this physical boundary explicit rather than interpreting a path
      // relative to HOME or repairing an existing installation elsewhere.
      if !local_product_path(path) || path.contains("\\") {
        stop("InvalidLocalStateDirectory")
      }
      let parts = path.split("/").to_array()
      let directory_name = parts[parts.length() - 1].to_owned()
      if directory_name.length() > 128 {
        stop("InvalidLocalStateDirectory")
      }
      let mut parent_path = ""
      let parent_end = parts.length() - 1
      for index in 1..<parent_end {
        parent_path += "/" + parts[index].to_owned()
      }
      if parent_path.is_empty() {
        parent_path = "/"
      }
      { parent_path, directory_name, }
    }
  }
}

///|
// An explicit original state directory does not consult or copy HOME. The
// absent selection obtains exactly one bounded original before path validation.
fn local_product_location_with_home(
  state_directory : String?,
  read_home : () -> String? raise ClientStop,
) -> LocalProductLocation raise ClientStop {
  let home = match state_directory {
    Some(_) => None
    None => read_home()
  }
  local_product_selected_location(state_directory, home)
}

///|
fn local_product_original_location(
  state_directory : String?,
) -> LocalProductLocation raise ClientStop {
  local_product_location_with_home(state_directory, local_product_bounded_home)
}

///|
fn local_product_operation(operation : String) -> Bool {
  [
    "adopt", "connect", "upgrade-policy", "lookup-policy-upgrade", "check", "explain",
    "new-submission", "lookup-submission", "lookup-request", "checkpoint-state",
    "lookup-preparation-grant", "lookup-preparation-raw", "lookup-cancellation",
    "cancel", "delivery-attempt", "read", "result", "start", "aql", "sql", "run",
    "status", "approve", "reject",
  ].contains(operation)
}

///|
fn local_product_path(path : String) -> Bool {
  if !path.has_prefix("/") ||
    path.length() < 2 ||
    path.length() > 4096 ||
    path.has_suffix("/") ||
    path.contains("\u{0000}") {
    return false
  }
  let parts = path.split("/").to_array()
  for index in 1..<parts.length() {
    if parts[index].is_empty() || parts[index] == "." || parts[index] == ".." {
      return false
    }
  }
  true
}

///|
fn local_product_context(
  wire : String,
) -> (String, String, String, String) raise ClientStop {
  if @utf8.encode(wire).length() > 8192 {
    stop("PackagedLocalRuntimeInvalid")
  }
  let object = @decode.closed_object(local_input_cursor(wire), [
    "root", "sourceSha", "platform", "manifestSha256",
  ]).unwrap_or_else(() => stop("PackagedLocalRuntimeInvalid"))
  let get = fn(key : String) -> String raise ClientStop {
    @decode.lookup(object, key)
    .bind(value => @decode.text(value).to_option())
    .unwrap_or_else(() => stop("PackagedLocalRuntimeInvalid"))
  }
  let root = get("root")
  if !local_product_path(root) {
    stop("PackagedLocalRuntimeInvalid")
  }
  (root, get("sourceSha"), get("platform"), get("manifestSha256"))
}

///|
fn local_packaged_runtime(
  context_wire : String,
) -> LocalPackagedRuntime raise ClientStop {
  let (root, source, platform, digest) = local_product_context(context_wire)
  let physical = match
    @local_host.open_native_local_packaged_runtime(
      root, source, platform, digest,
    ) {
    Ok(value) => value
    Err(Pending(pending, _)) => {
      if pending.close() is Err(_) {
        stop("PackagedLocalRuntimeCleanupPending")
      }
      stop("PackagedLocalRuntimeUnavailable")
    }
    Err(_) => stop("PackagedLocalRuntimeUnavailable")
  }
  local_packaged_runtime_from_physical(physical)
}

///|
fn local_packaged_runtime_from_physical(
  physical : @local_host.NativeLocalPackagedRuntime,
) -> LocalPackagedRuntime raise ClientStop {
  errdefer (if physical.close() is Err(_) {
    stop("PackagedLocalRuntimeCleanupPending")
  })
  let manifest = physical
    .manifest()
    .unwrap_or_else(() => stop("PackagedLocalRuntimeChanged"))
  let (assets, installed_contracts) = physical
    .installed_assets()
    .unwrap_or_else(() => stop("PackagedLocalRuntimeChanged"))
  let (sqlite, crypto) = physical
    .library_paths()
    .unwrap_or_else(() => stop("PackagedLocalRuntimeChanged"))
  { manifest, sqlite, crypto, assets, installed_contracts, physical, }
}

///|
fn local_product_runtime_current(runtime : LocalPackagedRuntime) -> Bool {
  runtime.physical.check_current() is Ok(_)
}

///|
fn execute_native_local_product(
  matches : @argparse.Matches,
  operation : String,
) -> String raise ClientStop {
  if !(matches.sources.get("config-root") is Some(@argparse.Default)) {
    stop("ExplicitLocalRootRequiresConfiguration")
  }
  if command_preparation_invocation.val is Some(original) {
    return original.execute_product_command(matches, operation)
  }
  let context = match command_preargument_retained_context() {
    Ok(Some(original)) => original
    Ok(None) =>
      @env.get_env_var("ACTQL_NATIVE_LOCAL_RUNTIME").unwrap_or_else(() => {
        stop("PackagedLocalRuntimeUnavailable")
      })
    Err(_) => stop("PackagedLocalRuntimeUnavailable")
  }
  let runtime = local_packaged_runtime(context)
  let reply = {
    errdefer (if runtime.physical.close() is Err(_) {
      stop("PackagedLocalRuntimeCleanupPending")
    })
    execute_native_local_packaged_operation(matches, operation, runtime)
  }
  if runtime.physical.close() is Err(_) {
    stop("PackagedLocalRuntimeCleanupPending")
  }
  reply
}

///|
fn execute_native_local_packaged_operation(
  matches : @argparse.Matches,
  operation : String,
  runtime : LocalPackagedRuntime,
) -> String raise ClientStop {
  // An explicit configuration remains its own profile. Do not silently replace
  // a user's selected root or repair an absent original configuration there.
  if !(matches.sources.get("config-root") is Some(@argparse.Default)) {
    stop("ExplicitLocalRootRequiresConfiguration")
  }
  let location = local_product_original_location(optional(matches, "state-dir"))
  let parent = @local_filesystem.open_root(location.parent_path).unwrap_or_else(() => {
      stop("LocalProductHomeUnavailable")
    },
  )
  local_product_with_owned_parent(parent, () => {
    execute_native_local_packaged_with_parent(
      matches, operation, runtime, location, parent,
    )
  })
}

///|
// The current opaque package was admitted independently. Equal wire metadata
// preserves its original path; old or malformed state never selects freshness.
fn local_product_require_same_runtime_wire(
  original : String,
  current : String,
) -> Unit raise ClientStop {
  if original != current {
    stop("HistoricalLocalRuntimeUnavailable")
  }
}

///|
fn execute_native_local_packaged_with_parent(
  matches : @argparse.Matches,
  operation : String,
  runtime : LocalPackagedRuntime,
  location : LocalProductLocation,
  parent : @local_filesystem.Root,
) -> String raise ClientStop {
  ignore(
    parent
    .bootstrap_parent_ownership()
    .unwrap_or_else(() => stop("LocalProductHomeUntrusted")),
  )
  let intent = parent
    .inspect_generation("product-initialization.json")
    .unwrap_or_else(() => stop("LocalProductCustodyUnavailable"))
  if !local_product_runtime_current(runtime) {
    stop("PackagedLocalRuntimeChanged")
  }
  let initial_crypto = if operation == "adopt" {
    Some(local_begin_initial_crypto(runtime))
  } else {
    None
  }
  let crypto = match initial_crypto {
    Some(original) =>
      original
      .library(false)
      .unwrap_or_else(() => stop("InitialCryptoOuterLibraryUnavailable"))
    None =>
      @local_crypto.load_library(runtime.crypto).unwrap_or_else(() => {
        stop("NativeLocalSignatureUnavailable")
      })
  }
  if !local_product_runtime_current(runtime) {
    stop("PackagedLocalRuntimeChanged")
  }
  let configuration_root = if location.parent_path == "/" {
    "/" + location.directory_name
  } else {
    location.parent_path + "/" + location.directory_name
  }
  let session = if intent is Some(_) {
    // Even repeated adopt restores the original clock and selection. Missing
    // witness/body/intent never triggers factory regeneration or new custody.
    local_host_result(
      @local_host.restore_native_local_product_configuration(
        location.parent_path,
        location.directory_name,
        crypto,
      ),
    )
  } else {
    if operation != "adopt" {
      stop("ExplicitLocalAdoptionRequired")
    }
    // An existing child without its original intent is lost custody, not a
    // fresh initialization. Refuse before even assembling replacement bodies.
    if parent
      .inspect_directory(location.directory_name)
      .unwrap_or_else(() => stop("LocalProductCustodyUnavailable"))
      is Some(_) {
      stop("LocalProductCustodyLost")
    }
    let originals = @run_host.client_native_local_finite_product_originals(
      configuration_root,
      runtime.sqlite,
      runtime.crypto,
      local_utc_now(),
      runtime.assets,
      runtime.manifest,
    ).unwrap_or_else(() => stop("LocalProductDefaultsNotAdmitted"))
    let originals = local_product_model_policy_originals(
      originals,
      Some(@local_values.client_local_resource_policy()),
    )
    local_host_result(
      @local_host.begin_native_local_product_configuration(
        location.parent_path,
        location.directory_name,
        originals,
        crypto,
      ),
    )
  }
  let reply = {
    errdefer (if !session.close() { stop("LocalProductCleanupPending") })
    local_host_result(session.stage_configuration())
    let original_runtime_wire = text_file(
      configuration_root, "runtime.json", 65536L,
    )
    let unchanged = original_runtime_wire ==
      @run_host.client_native_local_runtime_original(runtime.manifest)
    local_product_require_same_runtime_wire(
      original_runtime_wire,
      @run_host.client_native_local_runtime_original(runtime.manifest),
    )
    let settings = local_host_settings(
      text_file(configuration_root, "config.json", 65536L),
    )
    if (
        unchanged &&
        (
          settings.sqlite_library != runtime.sqlite ||
          settings.signature_library != runtime.crypto
        )
      ) ||
      !settings.installation_files.contains("runtime.json") ||
      !local_product_runtime_current(runtime) {
      stop("PackagedLocalRuntimeChanged")
    }
    // Close the original-file observation race before selecting a library.
    local_host_result(session.stage_configuration())
    if optional(matches, "input-root") is None {
      let input = @env.current_dir().unwrap_or_else(() => {
        stop("LocalDocumentRootUnavailable")
      })
      matches.values["input-root"] = [input]
    }
    matches.values["config-root"] = [configuration_root]
    matches.values["config-file"] = ["config.json"]
    if operation == "explain" {
      let observation = execute_native_local(matches)
      // Static metadata discloses only the same selected originals. Recheck
      // their existing custody and current package before returning the copy.
      local_host_result(session.stage_configuration())
      if !local_product_runtime_current(runtime) {
        stop("PackagedLocalRuntimeChanged")
      }
      observation
    } else {
      let (_, child) = matches.subcommand.unwrap()
      execute_native_local_adoption(
        matches,
        operation,
        child,
        packaged_runtime=Some(runtime.physical),
        initial_crypto~,
      )
    }
  }
  if !session.close() {
    stop("LocalProductCleanupPending")
  }
  reply
}

///|
// The selected parent descriptor was opened by this operation independently of the
// adoption session's Roots. Its own ACK is required after the original work
// and session cleanup, including early refusal. This does not settle a read
// claim, a WorkspaceLoan, child descriptor or another same-path Root.
fn local_product_with_owned_parent(
  parent : @local_filesystem.Root,
  operation : () -> String raise ClientStop,
) -> String raise ClientStop {
  let reply = {
    errdefer (if parent.close() is Err(_) {
      stop("LocalProductCleanupPending")
    })
    operation()
  }
  if parent.close() is Err(_) {
    stop("LocalProductCleanupPending")
  }
  reply
}
