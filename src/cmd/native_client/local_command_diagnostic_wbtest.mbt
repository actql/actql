///|
fn command_diagnostic_fixture(
  supplied : String?,
) -> Result[
  @local_host.NativeClientPreparation,
  @local_host.NativeClientPreparationIssue,
] raise ClientStop {
  let environment = explain_fixture_environment()
  let declarations = @parameters.read_declarations(
    Some(
      local_input_cursor("{\"id\":{\"type\":\"number\",\"nullable\":false}}"),
    ),
    { max_parameters: 16, max_nodes: 256, max_depth: 16, max_text_bytes: 4096, },
  ).unwrap()
  let context = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    parameter_declarations=Some(declarations),
  ).unwrap()
  let supplied = match supplied {
    Some(text) => Some(local_input_cursor(text))
    None => None
  }
  @local_host.prepare_native_client_program(
    "SELECT @id AS id",
    @frontend.Sql,
    environment,
    supplied,
    Some(context),
    [],
    @run_host.client_standard_effect_computation_limits(),
  )
}

///|
test "runtime requirements diagnostics preserve actual phase and proven dimension" {
  let cases : Array[
    (@local_values.ClientLocalRequirementsIssue, String, String),
  ] = [
    (
      SequencePreparation(Sequence(SequenceLimit)),
      "ACTQL_E_PREPARATION_LIMIT",
      "step bound",
    ),
    (
      SequencePreparation(Sequence(InvalidSequenceLimits)),
      "ACTQL_E_CONFIGURATION_INVALID",
      "selected limits",
    ),
    (
      SequencePreparation(Unsupported),
      "ACTQL_E_PREPARATION_FAILED",
      "Runtime sequence",
    ),
    (MissingDataEdge, "ACTQL_E_PREPARATION_FAILED", "input-port inventory"),
    (
      ModelOccurrencesUnavailable,
      "ACTQL_E_PREPARATION_FAILED",
      "input-port inventory",
    ),
    (InputPortCountLimit, "ACTQL_E_PREPARATION_LIMIT", "input-port count"),
    (
      CapacityQuoteUnavailable,
      "ACTQL_E_PREPARATION_FAILED",
      "no budget dimension",
    ),
  ]
  for (issue, expected_code, expected_dimension) in cases {
    local_command_diagnostic_reset()
    let stopped = try {
      local_stop_runtime_requirements(issue)
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(stopped, "LocalPreparationNotReady")
    let (code, message) = local_command_primary_diagnostic(stopped)
    assert_eq(code, expected_code)
    assert_true(message.contains(expected_dimension))
    let wire = local_command_diagnostic_text(code, message, true)
    guard @json.parse(wire) is Object(fields) else {
      fail("closed diagnostic required")
    }
    assert_eq(fields.length(), 2)
    assert_false(wire.contains("SequencePreparation"))
    assert_false(wire.contains("run_id"))
  }
  local_command_diagnostic_reset()
}

///|
test "Pre-Run diagnostic preserves original wrong-type parameter classification without its value" {
  local_command_diagnostic_reset()
  let original = match
    command_diagnostic_fixture(Some("{\"id\":\"private-value\"}")) {
    Ok(_) => fail("a string must not be admitted by the declared number type")
    Err(issue) => issue
  }
  let reason = try {
    local_stop_native_preparation(original)
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(reason, "LocalPreparationNotReady")
  let (code, message) = local_command_primary_diagnostic(reason)
  assert_eq(code, "ACTQL_E_PARAMETER_INVALID")
  assert_false(message.contains("private-value"))
  let wire = local_command_diagnostic_text(code, message, true)
  guard @json.parse(wire) is Object(fields) else {
    fail("the original rejection must have one diagnostic object")
  }
  assert_eq(fields.length(), 2)
  assert_eq(fields.get("code"), Some(Json::string(code)))
  assert_eq(fields.get("message"), Some(Json::string(message)))
  assert_false(wire.contains("run_id"))
  local_command_diagnostic_reset()
}

///|
test "Pre-Run missing parameters use original input requests and valid binding stays valid" {
  for supplied in [None, Some("{}")] {
    local_command_diagnostic_reset()
    let original = match command_diagnostic_fixture(supplied) {
      Ok(_) => fail("a required original parameter is missing")
      Err(issue) => issue
    }
    let reason = try {
      local_stop_native_preparation(original)
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(reason, "LocalPreparationNotReady")
    assert_eq(
      local_command_primary_diagnostic(reason).0,
      "ACTQL_E_PARAMETER_MISSING",
    )
  }
  local_command_diagnostic_reset()
  assert_true(command_diagnostic_fixture(Some("{\"id\":7}")) is Ok(_))
  assert_eq(
    local_command_primary_diagnostic("original unrelated failure"),
    ("ACTQL_E_COMMAND_FAILED", "original unrelated failure"),
  )
}

///|
test "Diagnostic mode follows accepted Matches without reinterpreting option values" {
  for
    arguments in [
      ["run", "query.aql", "--json"],
      ["run", "--json", "query.aql"],
    ] {
    let parsed = command().parse(argv=arguments[:], env=Map([]))
    assert_true(local_command_json_selected(parsed))
  }
  let parsed = command().parse(argv=["run", "--", "--json"], env=Map([]))
  assert_false(local_command_json_selected(parsed))
  let rejected = try {
    ignore(
      parse_native_initial_arguments(
        ["original", "run", "--json", "--unknown"],
        false,
      ),
    )
    false
  } catch {
    NativeCommandArgumentStop(_) => true
    _ => fail("the original parser error must retain the argument boundary")
  }
  assert_true(rejected)
  assert_true(command_diagnostic_json.val)
  assert_false(
    local_command_argument_diagnostic_json(["original", "run", "--", "--json"]),
  )
  assert_false(
    local_command_argument_diagnostic_json([
      "original", "run", "--params=--json",
    ]),
  )
  assert_true(command_preparation_invocation.val is None)
  local_command_diagnostic_reset()
}

///|
test "A pending return cannot erase the typed primary and cleanup is a separate bounded diagnostic" {
  local_command_diagnostic_reset()
  let original = match command_diagnostic_fixture(Some("{\"id\":\"wrong\"}")) {
    Ok(_) => fail("the original typed rejection is required")
    Err(issue) => issue
  }
  local_stop_native_preparation(original) catch {
    ClientStop(_) => ()
  }
  // The physical carrier may report a distinct failed return. This is a
  // presentation counter only; it does not pretend to acquire or close it.
  let primary = local_command_primary_diagnostic(
    "LocalCommandPreparationUnavailable:original-return",
  )
  assert_eq(primary.0, "ACTQL_E_PARAMETER_INVALID")
  let cleanup = local_command_diagnostic_text(
    "ACTQL_E_CLEANUP_PENDING", "original return remains pending", true,
  )
  assert_true(cleanup.contains("ACTQL_E_CLEANUP_PENDING"))
  assert_eq(local_command_primary_diagnostic("return pending"), primary)
  let message = StringBuilder()
  for _ in 0..<2000 {
    message.write_string("\u{001b}\n\"日本語")
  }
  let bounded = local_command_diagnostic_text(
    "ACTQL_E_COMMAND_FAILED",
    message.to_string(),
    true,
  )
  assert_true(@utf8.encode(bounded).length() < 4096)
  assert_true(@json.parse(bounded) is Object(_))
  let human = local_command_diagnostic_text(primary.0, "\u{001b}\n", false)
  assert_true(human.contains(primary.0))
  assert_false(human.contains("\u{001b}"))
  assert_false(human.contains("\n"))
  local_command_diagnostic_reset()
}

///|
test "Pre-Run presentation never reinterprets or truncates a legacy recovery carrier" {
  local_command_diagnostic_reset()
  let original = StringBuilder()
  original.write_string("original Unknown metadata: ")
  for _ in 0..<1000 {
    original.write_string("run-ref/ACTQL_E_PARAMETER_INVALID/\"preserve\"\n")
  }
  let original = original.to_string()
  for json in [false, true] {
    assert_eq(
      local_command_failure_text(original, json),
      "actql-native-client: " + original,
    )
  }
}

///|
test "Query syntax diagnostics keep the code and omit private parser text" {
  local_command_diagnostic_reset()
  let private_text = "synthetic-token=DO_NOT_DISCLOSE\u{001b}"
  let issue : @frontend.Issue = QuerySyntax({
    issue: Syntax(private_text),
    span: None,
  })
  let original : @local_host.NativeClientPreparationIssue = Frontend(issue)
  local_stop_native_preparation(original) catch {
    ClientStop(_) => ()
  }
  let (code, message) = local_command_primary_diagnostic(
    "LocalPreparationNotReady",
  )
  assert_eq(code, "ACTQL_E_PROGRAM_INVALID")
  assert_true(message.contains("query syntax"))
  assert_true(message.contains("actql check"))
  for json in [false, true] {
    let rendered = local_command_failure_text("LocalPreparationNotReady", json)
    assert_true(rendered.contains(code))
    assert_true(rendered.contains("query syntax"))
    assert_false(rendered.contains("DO_NOT_DISCLOSE"))
    assert_false(rendered.contains("\u{001b}"))
  }
  command_preparation_diagnostic.val = local_frontend_diagnostic_kind(
    @frontend.QuerySyntax({ issue: Lexical(UnterminatedComment), span: None, }),
  )
  assert_eq(local_command_primary_diagnostic("ignored").0, code)
  assert_true(
    local_command_primary_diagnostic("ignored").1.contains("query syntax"),
  )
  // The parser also reports budget/configuration failures in this carrier.
  // They must not acquire syntax-specific advice merely by sharing its type.
  for
    issue in [
      @frontend.QuerySyntax({ issue: InvalidLimits, span: None, }),
      @frontend.QuerySyntax({ issue: Source(InvalidRange), span: None, }),
      @frontend.InvalidFormat,
      @frontend.WrongQueryForm,
    ] {
    command_preparation_diagnostic.val = local_frontend_diagnostic_kind(issue)
    assert_eq(local_command_primary_diagnostic("ignored").0, code)
    assert_false(
      local_command_primary_diagnostic("ignored").1.contains("query syntax"),
    )
  }
  local_command_diagnostic_reset()
}

///|
test "Query parser resource refusals are not classified as invalid syntax" {
  for
    text in [
      "SELECT " + Array::make(4200, "1").join(","),
      "SELECT " + " ".repeat(65536) + "1 AS value",
    ] {
    guard @frontend.parse_query(text, @frontend.Text) is Err(issue) else {
      fail("the query must exceed the fixed parser resource budget")
    }
    guard issue is QuerySyntax({ issue: Limit(_) | Source(InputLimit), .. }) else {
      fail("the original parser must retain its typed resource cause")
    }
    local_command_diagnostic_reset()
    let original : @local_host.NativeClientPreparationIssue = Frontend(issue)
    local_stop_native_preparation(original) catch {
      ClientStop(_) => ()
    }
    let (code, message) = local_command_primary_diagnostic("private source")
    assert_eq(code, "ACTQL_E_PREPARATION_LIMIT")
    assert_true(message.contains("limit"))
    assert_false(message.contains("invalid"))
    for json in [false, true] {
      let rendered = local_command_failure_text("private source", json)
      assert_true(rendered.contains(code))
      assert_false(rendered.contains("private source"))
    }
  }
  assert_true(
    @frontend.parse_query("SELECT 1 AS value", @frontend.Text) is Ok(_),
  )
  local_command_diagnostic_reset()
}

///|
test "Primary file diagnostics disclose closed causes without replacing custody or cleanup families" {
  let prefix = "LocalCommandPreparationUnavailable:configuration-read:filesystem"
  let cases : Array[(@files.NativeBoundedTextIssue, String?)] = [
    (Missing, Some("input file is missing")),
    (CapacityExceeded, Some("configured read limit")),
    (InvalidUtf8, Some("not valid UTF-8")),
    (InvalidLimit, None),
    (Filesystem(Read("SYNTHETIC_OS_SECRET")), None),
    (
      Cleanup(Read("SYNTHETIC_OS_SECRET"), Cleanup("SYNTHETIC_CLEANUP_SECRET")),
      None,
    ),
  ]
  for (issue, hint) in cases {
    local_command_diagnostic_reset()
    let failure : Result[Unit, LocalCommandPreparationIssue] = Err(
      CommandFilesystem(issue),
    )
    let message = try {
      command_preparation_result(failure, stage=Some("configuration-read"))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_true(message.has_prefix(prefix))
    match hint {
      Some(hint) => assert_true(message.contains(hint))
      None => assert_eq(message, prefix)
    }
    assert_false(message.contains("SYNTHETIC_OS_SECRET"))
    assert_false(message.contains("SYNTHETIC_CLEANUP_SECRET"))
    assert_eq(
      command_preparation_cleanup_kind(CommandFilesystem(issue)),
      "filesystem",
    )
  }
  local_command_diagnostic_reset()
}

///|
// Keep the original read-only terminal on its actual Native Request. Only the
// closed diagnostic tag escapes the payload frame, as in the command caller.
fn command_request_query_diagnostic_fixture(
  facility : NativeMockReadmeRequestFacility,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  text : String,
) -> Unit raise {
  let wire : Json = {
    "kind": "aql",
    "input": { "text": Json::string(text), "format": "sql" },
    "parameters": null,
  }
  let wire = local_project_mock_relation_wire(wire).unwrap()
  let intent = @run_host.prepare_client_submitted_intent(wire, 65536, 8192, 64).unwrap()
  guard @local_host.prepare_native_client_submitted_request_input(
      facility.parent,
      facility.input,
      intent,
      environment,
      publication,
    )
    is Err(issue) else {
    fail("the original Request must refuse this authored Query")
  }
  assert_true(
    issue
    is Request(
      QuerySyntax(Frontend(QuerySyntax({ issue: Syntax(_) | Lexical(_), .. })))
    ),
  )
  local_stop_submitted_preparation(issue) catch {
    ClientStop(_) => ()
  }
}

///|
test "Native original Request parser failure retains invalid input after payload cleanup" {
  let environment = explain_fixture_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  for text in ["SELECT )", "/* SYNTHETIC_UNTERMINATED_QUERY"] {
    local_command_diagnostic_reset()
    let facility = native_mock_readme_request_facility()
    facility.arena.enter_domain_retained_execution(facility.physical).unwrap()
    command_request_query_diagnostic_fixture(
      facility, environment, publication, text,
    )
    ignore(
      @local_values.abort_request_preparation_after_cleanup(facility.parent),
    )
    facility.arena.leave_domain_retained_execution(facility.physical).unwrap()
    facility.arena.close_domain_retained_execution(facility.physical).unwrap()
    @local_values.abort_request_preparation_after_cleanup(facility.parent).unwrap()
    facility.arena.close_domain_after_owner_ack(facility.domain).unwrap()
    facility.arena.try_close().unwrap()
    let (code, _) = local_command_primary_diagnostic("ignored")
    assert_eq(code, "ACTQL_E_PROGRAM_INVALID")
    for json in [false, true] {
      let rendered = local_command_failure_text(text, json)
      assert_true(rendered.contains(code))
      assert_false(rendered.contains(text))
    }
  }
  local_command_diagnostic_reset()
}
