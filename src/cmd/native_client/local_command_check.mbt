///|
// This caller reference retains the same original across parser/command errors.
// It is not a supplier or an initialization/admission receipt.
let command_preparation_invocation : Ref[LocalCommandPreparationOriginal?] = Ref(
  None,
)

///|
fn command_preparation_result[T](
  result : Result[T, LocalCommandPreparationIssue],
) -> T raise ClientStop {
  match result {
    Ok(value) => value
    Err(_) => stop("LocalCommandPreparationUnavailable")
  }
}

///|
// The selected package and all of its original asset observations use the
// Runtime's own full scopes. Only then enter the same consuming Read for the
// retained Product/Host selection; do not nest Runtime acquisition inside it.
fn LocalCommandPreparationOriginal::execute_product_check(
  self : LocalCommandPreparationOriginal,
  matches : @argparse.Matches,
  operation : String,
) -> String raise ClientStop {
  if operation != "check" {
    stop("LocalCommandPreparationOperationUnavailable")
  }
  if !(matches.sources.get("config-root") is Some(@argparse.Default)) {
    stop("ExplicitLocalRootRequiresConfiguration")
  }
  guard self.runtime is Some(physical) else {
    stop("LocalCommandPreparationUnavailable")
  }
  let runtime = local_packaged_runtime_from_physical(physical)
  let location = local_product_selected_location(
    optional(matches, "state-dir"),
    @env.get_env_var("HOME"),
  )
  command_preparation_result(self.enter())
  command_preparation_result(
    self.stage_product(location.parent_path, location.directory_name, None),
  )
  let configuration_root = if location.parent_path == "/" {
    "/" + location.directory_name
  } else {
    location.parent_path + "/" + location.directory_name
  }
  let original_runtime = text_file(configuration_root, "runtime.json", 65536L)
  local_product_require_same_runtime_wire(
    original_runtime,
    @run_host.client_native_local_runtime_original(runtime.manifest),
  )
  let settings = local_host_settings(
    text_file(configuration_root, "config.json", 65536L),
  )
  if settings.sqlite_library != runtime.sqlite ||
    settings.signature_library != runtime.crypto ||
    !settings.installation_files.contains("runtime.json") {
    stop("PackagedLocalRuntimeChanged")
  }
  command_preparation_result(
    self.stage_product(location.parent_path, location.directory_name, None),
  )
  if optional(matches, "input-root") is None {
    matches.values["input-root"] = [
      @env.current_dir().unwrap_or_else(() => {
        stop("LocalDocumentRootUnavailable")
      }),
    ]
  }
  matches.values["config-root"] = [configuration_root]
  matches.values["config-file"] = ["config.json"]
  let (_, child) = matches.subcommand.unwrap()
  execute_native_local_adoption(
    matches,
    operation,
    child,
    packaged_runtime=Some(physical),
    preparation=Some(self),
  )
}

///|
// Continue the existing selected configuration comparisons. The same actual
// adoption capture owns every partial Root/Lock and the original child Journal;
// this path never loads a second SQLite Library or a stock Crypto fallback.
fn LocalCommandPreparationOriginal::execute_adopted_check(
  self : LocalCommandPreparationOriginal,
  settings : LocalHostSettings,
  root : String,
  name : String,
  configuration : String,
  environment_name : String,
  environment : String,
  selected_files : Array[String],
  selected_additional : Array[(String, Bytes)],
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let session = command_preparation_result(
    self.prepare_adoption(
      {
        parent_path: settings.state_parent,
        state_name: settings.state_name,
        source_path: root,
        source_name: settings.account_file,
        account_id: settings.account_id,
        configuration_files: selected_files,
        managed_root_path: Some(settings.managed_root),
      },
      false,
    ),
  )
  let expected = [
    (name, @utf8.encode(configuration)),
    (environment_name, @utf8.encode(environment)),
  ]
  for item in selected_additional {
    expected.push(item)
  }
  for (file, body) in expected {
    guard session.selected_configuration(file) is Ok(selected) &&
      selected == body else {
      stop("LocalConfigurationChanged")
    }
  }
  // Host fields still come from the same admitted original configuration.
  // No Run, initialization/key generation or replacement issue is selected.
  command_preparation_result(
    self.open_adopted_journal(false, {
      initialize_signing: false,
      ttl_ms: settings.ttl_ms,
      max_records: settings.record_limit,
      max_snapshot_bytes: settings.snapshot_bytes,
    }),
  )
  |> ignore
  let crypto = self.inner_library.unwrap()
  command_preparation_result(
    self.read_command(fn(host, capture) {
      Ok(
        local_check_for_host(
          host,
          crypto,
          name,
          input_root,
          child,
          capture=Some(capture),
        ),
      ) catch {
        ClientStop(message) => Err(message)
      }
    }),
  )
}
