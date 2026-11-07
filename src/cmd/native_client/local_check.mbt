///|
// One command's private reporting context. These are the original adopted
// Host and selected files, not a Run, authorization grant or public hash.
priv struct LocalCheckContext {
  host : @local_host.NativeLocalHostConnection
  capture : @local_host.NativeLocalJournalCapture?
  crypto : @local_crypto.Library
  key : Bytes
  configuration_name : String
  configuration_body : Bytes
  environment_name : String
  environment_body : Bytes
  environment : @checked.CheckEnvironment
  audience : String
  connection : String
}

///|
priv struct LocalCheckInput {
  document : String
  format : @frontend.Format
  declarations : String?
  parameters : String?
}

///|
fn local_check_hex(bytes : Bytes) -> String {
  let out = StringBuilder()
  for byte in bytes {
    let hex = byte.to_hex()
    if hex.length() == 1 {
      out.write_char('0')
    }
    out.write_string(hex)
  }
  out.to_string()
}

///|
fn local_check_original_text(body : Bytes) -> String raise ClientStop {
  @utf8.decode(body) catch {
    _ => stop("LocalCheckContextUnavailable")
  }
}

///|
// Read only an original selected by this physical Host. The reporting key is
// fresh for this command lifetime; no epoch/signing key is reused or persisted.
fn local_check_context(
  host : @local_host.NativeLocalHostConnection,
  crypto : @local_crypto.Library,
  configuration_name : String,
  capture? : @local_host.NativeLocalJournalCapture? = None,
  configuration? : LocalCommandConfiguration? = None,
) -> LocalCheckContext raise ClientStop {
  let selected = fn(name : String) {
    match capture {
      None => host.selected_configuration(name)
      Some(original) => original.selected_configuration_in_original_read(name)
    }
  }
  let (
    configuration_body,
    settings,
    environment_name,
    environment_body,
    environment,
  ) = match configuration {
    Some(original) => {
      guard capture is Some(_) &&
        original.configuration_name == configuration_name else {
        stop("LocalCheckContextUnavailable")
      }
      (
        original.configuration_body,
        original.settings,
        original.environment_name,
        original.environment_body,
        original.checked_environment(),
      )
    }
    None => {
      let body = local_host_result(selected(configuration_name))
      let text = local_check_original_text(body)
      let settings = local_host_settings(text)
      let (environment_name, evidence) = local_configuration(text)
      let environment_body = local_host_result(selected(environment_name))
      let environment = local_admitted_check_environment(
        local_check_original_text(environment_body),
        evidence,
      ).unwrap_or_else(() => stop("LocalCheckContextUnavailable"))
      (body, settings, environment_name, environment_body, environment)
    }
  }
  let account = local_host_result(
    match capture {
      None => host.configuration()
      Some(original) => original.configuration_in_original_read()
    },
  )
  if account.account_id() != settings.account_id {
    stop("LocalCheckContextUnavailable")
  }
  let key = crypto
    .random_bytes(32)
    .unwrap_or_else(() => stop("LocalCheckContextUnavailable"))
  let context : LocalCheckContext = {
    host,
    capture,
    crypto,
    key,
    configuration_name,
    configuration_body,
    environment_name,
    environment_body,
    environment: local_command_project_environment(environment),
    audience: settings.principal,
    connection: settings.connection,
  }
  if !context.current() {
    stop("LocalCheckContextUnavailable")
  }
  context
}

///|
fn LocalCheckContext::current(self : LocalCheckContext) -> Bool {
  match self.capture {
    None =>
      self.host.check_binding() is Ok(_) &&
      self.host.selected_configuration(self.configuration_name)
      is Ok(configuration) &&
      configuration == self.configuration_body &&
      self.host.selected_configuration(self.environment_name) is Ok(environment) &&
      environment == self.environment_body
    Some(original) =>
      original.check_current_in_original_read() is Ok(_) &&
      original.selected_configuration_in_original_read(self.configuration_name)
      is Ok(configuration) &&
      configuration == self.configuration_body &&
      original.selected_configuration_in_original_read(self.environment_name)
      is Ok(environment) &&
      environment == self.environment_body
  }
}

///|
fn LocalCheckContext::revision(
  self : LocalCheckContext,
  role : String,
  original : String,
) -> String raise ClientStop {
  let message = "actql-check-input/0.1\u{0000}" + role + "\u{0000}" + original
  let tag = self.crypto
    .hmac_sha256(self.key, @utf8.encode(message))
    .unwrap_or_else(() => stop("LocalCheckContextUnavailable"))
  "rev:" + local_check_hex(tag)
}

///|
fn local_check_received(original : String?) -> Json {
  match original {
    None => Json::null()
    Some(original) =>
      Json::object(
        Map([
          ("kind", Json::string("structured")),
          ("received", Json::string(original)),
        ]),
      )
  }
}

///|
// Private keyed preimage, not a CID domain or wire. The existing encoder
// preserves String scalars (including Unicode and CR/LF) without normalization.
// File-backed structured inputs bind their exact received spelling as well.
fn LocalCheckContext::reference(
  self : LocalCheckContext,
  input : LocalCheckInput,
) -> String raise ClientStop {
  let (reason, outcome) = @preparation.client_program_check_reporting_schema_cids()
  let compiler = @json.parse(
    @preparation.client_program_check_compiler_identity(),
  ) catch {
    _ => stop("LocalCheckContextUnavailable")
  }
  let checking_context = @json.parse(
    @preparation.client_program_check_context_identity(self.environment),
  ) catch {
    _ => stop("LocalCheckContextUnavailable")
  }
  let fields = Map([
    ("version", Json::string("actql-check-context/0.1")),
    ("audience", Json::string(self.audience)),
    ("connection", Json::string(self.connection)),
    ("disclosure_policy", Json::string("actql-check-disclosure/0.1")),
    ("projection", Json::string("actql-check-outcome/0.1")),
    ("scope", Json::string("bound_input")),
    ("compiler", compiler),
    ("reason_schema_cid", Json::string(reason)),
    ("outcome_schema_cid", Json::string(outcome)),
    ("checking_context", checking_context),
    // No Native Source publication supplier is installed here. An empty
    // visible set is not complete namespace custody or proof of absence.
    ("visible_aliases", Json::array([])),
    ("parameters", local_check_received(input.parameters)),
  ])
  match input.format {
    @frontend.Json =>
      fields["program"] = local_check_received(Some(input.document))
    @frontend.Yaml =>
      fields["program"] = Json::object(
        Map([
          ("kind", Json::string("structured")),
          ("format", Json::string("yaml")),
          ("received", Json::string(input.document)),
        ]),
      )
    _ => {
      fields["source"] = Json::object(
        Map([
          (
            "format",
            Json::string(if input.format == Sql { "sql" } else { "aql" }),
          ),
          ("text", Json::string(input.document)),
        ]),
      )
      fields["parameter_declarations"] = local_check_received(
        input.declarations,
      )
    }
  }
  // The existing physical HMAC API has a 1 MiB message intake. This is only
  // its bounded private message, never a workspace/funding allowance.
  let message = encode_request_json(Json::object(fields), 1048576)
  let tag = self.crypto
    .hmac_sha256(self.key, @utf8.encode(message))
    .unwrap_or_else(() => stop("LocalCheckContextUnavailable"))
  "ctx:" + local_check_hex(tag)
}

///|
fn LocalCheckContext::project(
  self : LocalCheckContext,
  input : LocalCheckInput,
) -> String raise ClientStop {
  let correlation = "corr:" +
    local_check_hex(
      self.crypto
      .random_bytes(16)
      .unwrap_or_else(() => stop("LocalCheckContextUnavailable")),
    )
  if !self.current() {
    return @preparation.client_program_check_unavailable(correlation)
  }
  let reference = self.reference(input)
  let publication = encode_request_json(
    Json::object(
      Map([
        (
          "environmentCid",
          Json::string(@checked.checking_environment_cid(self.environment)),
        ),
        ("aliases", Json::array([])),
      ]),
    ),
    4096,
  )
  let parameters_revision = input.parameters.map(body => {
    self.revision("parameters", body)
  })
  let report = match input.format {
    Json =>
      @preparation.client_program_check_program(
        input.document,
        self.environment,
        publication,
        input.parameters,
        reference,
        self.revision("program", input.document),
        parameters_revision,
        correlation,
        "bound_input",
        None,
      )
    Text | Sql =>
      @preparation.client_program_check_source(
        input.document,
        if input.format == Sql {
          "sql"
        } else {
          "aql"
        },
        self.environment,
        publication,
        input.declarations,
        input.parameters,
        reference,
        self.revision("source", input.document),
        input.declarations.map(body => {
          self.revision("parameter_declarations", body)
        }),
        parameters_revision,
        correlation,
        "bound_input",
        None,
      )
    Yaml =>
      @preparation.client_program_check_program_with_format(
        input.document,
        "yaml",
        self.environment,
        publication,
        input.parameters,
        reference,
        self.revision("program", input.document),
        parameters_revision,
        correlation,
        "bound_input",
        None,
      )
  }
  // Pure projection does not establish terminal current. Never return its
  // verdict if original Host/configuration custody changed during this call.
  if !self.current() {
    return @preparation.client_program_check_unavailable(correlation)
  }
  report
}

///|
fn local_check_for_host(
  host : @local_host.NativeLocalHostConnection,
  crypto : @local_crypto.Library,
  configuration_name : String,
  input_root : String,
  child : @argparse.Matches,
  capture? : @local_host.NativeLocalJournalCapture? = None,
  configuration? : LocalCommandConfiguration? = None,
) -> String raise ClientStop {
  native_timing_begin(2)
  defer native_timing_end(2)
  let context = local_check_context(
    host,
    crypto,
    configuration_name,
    capture~,
    configuration~,
  )
  let format = @frontend.select_format(required(child, "format")).unwrap_or_else(() => {
      stop("UnsupportedLocalSourceFormat")
    },
  )
  let declarations = optional(child, "parameter-declarations-file").map(name => {
    local_input_text_file(input_root, name, 65536L)
  })
  if declarations is Some(_) && format != Text && format != Sql {
    stop("external declarations require aql-text or sql")
  }
  let input : LocalCheckInput = {
    document: local_input_text_file(
      input_root,
      required(child, "program-file"),
      65536L,
    ),
    format,
    declarations,
    parameters: optional(child, "parameters-file").map(name => {
      local_input_text_file(input_root, name, 65536L)
    }),
  }
  let wire = context.project(input)
  command_check_invalid_exit.val = local_check_invalid_exit(wire)
  local_check_reply(
    wire,
    child.flags.get("json").unwrap_or(false),
    input.document,
  )
}
