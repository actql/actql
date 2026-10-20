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
