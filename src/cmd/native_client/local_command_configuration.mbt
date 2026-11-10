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

///|
// First-adoption default DATA only, before configuration signing or Program
// checking. An absent selection is the explicit/retained pass-through. The
// original packaged asset bytes and independent runtime identity stay intact.
fn local_product_model_policy_originals(
  originals : Array[(String, Bytes)],
  policy : @local_values.ClientLocalResourcePolicy?,
) -> Array[(String, Bytes)] raise ClientStop {
  guard policy is Some(policy) else { return originals }
  guard @local_values.client_local_preparation_initial_limits(policy) is Some(_) else {
    stop("LocalResourcePolicyUnavailable")
  }
  // The same existing Model window as the Node Local selector. This is a
  // policy ceiling, not a physical allocation or permission to invoke Model.
  let bytes = @infer.standard_limits().model.max_request_bytes
  if bytes < 1L || bytes > 9007199254740991L {
    stop("LocalModelRequestPolicyUnavailable")
  }
  let original = fn(name : String) -> (Int, String) raise ClientStop {
    let mut found = None
    for index, (key, value) in originals {
      if key == name {
        if found is Some(_) || value.length() > 65536 {
          stop("LocalProductDefaultsNotAdmitted")
        }
        let text = @utf8.decode(value) catch {
          _ => stop("LocalProductDefaultsNotAdmitted")
        }
        found = Some((index, text))
      }
    }
    found.unwrap_or_else(() => stop("LocalProductDefaultsNotAdmitted"))
  }
  let (environment_index, environment) = original("environment.json")
  let (configuration_index, configuration) = original("config.json")
  let parse = fn(text : String) -> Json raise ClientStop {
    @json.parse(text) catch {
      _ => stop("LocalProductDefaultsNotAdmitted")
    }
  }
  guard parse(environment) is Object(body) &&
    body.get("host_policy_profile") is Some(Object(host)) &&
    host.get("capacity") is Some(Object(capacity)) &&
    parse(configuration) is Object(config) &&
    config.get("native") is Some(Object(native)) &&
    native.get("check_environment") is Some(Object(selection)) &&
    selection.get("file") == Some(Json::string("environment.json")) else {
    stop("LocalProductDefaultsNotAdmitted")
  }
  capacity["max_model_request_bytes_per_item"] = Json::number(bytes.to_double())
  ignore(body.remove("evidence_bundle_cid"))
  let encode = fn(value : Json) -> String raise ClientStop {
    local_project_mock_relation_wire(value).unwrap_or_else(() => {
      stop("LocalProductDefaultsNotAdmitted")
    })
  }
  let cid = "sha256:" + @sha.hex(@utf8.encode(encode(Json::object(body))))
  body["evidence_bundle_cid"] = Json::string(cid)
  selection["evidence_bundle_cid"] = Json::string(cid)
  let environment = encode(Json::object(body))
  // The ordinary selected configuration consumer performs its one Environment
  // admission. This constructor changes only a typed policy scalar and the
  // canonical references; it does not add a second checker here.
  // New first-adoption originals, never mutation of an issued configuration
  // or the raw packaged assets. The existing initialization Owner signs and
  // retains this exact complete tuple, including its new Environment CID.
  let selected = originals.copy()
  selected[environment_index] = ("environment.json", @utf8.encode(environment))
  selected[configuration_index] = (
    "config.json",
    @utf8.encode(encode(Json::object(config))),
  )
  selected
}
