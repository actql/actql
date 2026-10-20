///|
fn check_cli_fixture(name : String) -> (LocalCheckContext, String) raise {
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let sqlite_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let crypto_path = @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap()
  let root = base + "/" + name
  let parent = effect_finite_cli_ok(
    @local_filesystem.open_private_root(base),
    "check.parent",
  )
  effect_finite_cli_ok(parent.create_directory(name), "check.directory")
  |> ignore
  effect_finite_cli_ok(parent.close(), "check.parent.close")
  let originals = effect_finite_cli_ok(
    @run_host.client_local_product_finite_originals(
      root,
      sqlite_path,
      crypto_path,
      "2026-10-10T00:00:00.000Z",
      @run_host.client_local_product_assets(),
    ),
    "check.originals",
  )
  let files = effect_finite_cli_ok(
    @local_filesystem.open_private_root(root),
    "check.files",
  )
  for (name, body) in originals {
    let writer = effect_finite_cli_ok(
      files.create_writer(name + ".stage", body.length().to_int64()),
      "check.writer",
    )
    effect_finite_cli_ok(writer.append(body), "check.append")
    effect_finite_cli_ok(writer.seal(name), "check.seal") |> ignore
  }
  effect_finite_cli_ok(files.close(), "check.files.close")
  let crypto = effect_finite_cli_ok(
    @local_crypto.load_library(crypto_path),
    "check.crypto",
  )
  let sqlite = effect_finite_cli_ok(
    @local_sqlite.load_library(sqlite_path),
    "check.sqlite",
  )
  let configuration = @utf8.decode(
    originals.iter().find_first(pair => pair.0 == "config.json").unwrap().1,
  ) catch {
    _ => fail("check.configuration.utf8")
  }
  let settings = local_host_settings(configuration)
  let host = effect_finite_cli_ok(
    effect_finite_cli_ok(
      @local_host.begin_native_local_host_adoption(
        settings.state_parent,
        settings.state_name,
        root,
        settings.account_file,
        settings.account_id,
        crypto,
        configuration_files=[
          "config.json",
          "environment.json",
          ..settings.installation_files,
        ],
        managed_root_path=Some(root),
      ),
      "check.adoption",
    ).open_journal(
      sqlite,
      crypto,
      settings.ttl_ms,
      settings.record_limit,
      settings.snapshot_bytes,
    ),
    "check.journal",
  )
  (local_check_context(host, crypto, "config.json"), root)
}

///|
fn check_cli_input(document : String) -> LocalCheckInput {
  { document, format: Sql, declarations: None, parameters: None, }
}

///|
fn check_cli_report(wire : String) -> Json raise {
  let value = @json.parse(wire) catch { _ => fail("check.report.json") }
  match value {
    Object(fields) => fields.get("report").unwrap()
    _ => fail("check.report.object")
  }
}

///|
test "Native check uses the actual portable verdict and runnable without a prepared response" {
  let (context, _) = check_cli_fixture("native-check-verdict")
  let valid = context.project(
    check_cli_input("SELECT 1 AS id |> RESULT answer;"),
  )
  let invalid = context.project(check_cli_input("SELECT 1 / 'text' AS id"))
  assert_false(local_check_invalid_exit(valid))
  assert_true(local_check_invalid_exit(invalid))
  let valid_report = check_cli_report(valid)
  assert_eq(
    local_explain_field(valid_report, "verdict"),
    Json::string("verified"),
  )
  assert_eq(
    local_explain_field(
      local_explain_field(valid_report, "runnable"),
      "verdict",
    ),
    Json::string("yes"),
  )
  let invalid_report = check_cli_report(invalid)
  assert_eq(
    local_explain_field(invalid_report, "verdict"),
    Json::string("invalid"),
  )
  assert_eq(
    local_explain_field(
      local_explain_field(invalid_report, "runnable"),
      "verdict",
    ),
    Json::string("no"),
  )
  assert_false(valid.contains("\"prepared\""))
  effect_finite_cli_ok(context.host.close(), "check.host.close")
}

///|
test "Native check context keys exact original inputs audience and disclosure without a private Environment CID" {
  let (context, _) = check_cli_fixture("native-check-reference")
  let original = check_cli_input("SELECT 'é\r\n' AS id")
  let reference = context.reference(original)
  assert_eq(reference, context.reference(original))
  for
    input in [
      check_cli_input("SELECT 'e\u0301\r\n' AS id"),
      check_cli_input("SELECT 'é\n' AS id"),
      { ..original, format: Text, },
      { ..original, declarations: Some("[]"), },
      { ..original, parameters: Some("{\"id\":1}"), },
    ] {
    assert_false(reference == context.reference(input))
  }
  let other_audience : LocalCheckContext = {
    ..context,
    audience: "another-client",
  }
  let other_connection : LocalCheckContext = {
    ..context,
    connection: "another-connection",
  }
  let other_key : LocalCheckContext = { ..context, key: Bytes::make(32, 1), }
  assert_false(reference == other_audience.reference(original))
  assert_false(reference == other_connection.reference(original))
  assert_false(reference == other_key.reference(original))
  // Independent Python stdlib HMAC-SHA256 vectors over key 01 repeated 32
  // and the exact domain, role, UTF-8 bytes; not derived from this implementation.
  assert_eq(
    other_key.revision("source", original.document),
    "rev:ac093ea103a4d5d28f0a9f728cb0c5991f01e0366a42588f95bfb32f22a76d89",
  )
  assert_eq(
    other_key.revision("parameters", original.document),
    "rev:450cddef673fdcc17c50bf0062a3a4dd161e54a72cda0660e462177e9d1f5f20",
  )
  assert_false(
    context.revision("source", original.document) ==
    context.revision("parameters", original.document),
  )
  assert_false(
    context.revision("source", original.document) ==
    context.revision("source", "SELECT 'é\n' AS id"),
  )
  // The same Owner supplies pins; neither a copied literal nor unavailable
  // output is used to discover reporting identities.
  let (reason, outcome) = @preparation.client_program_check_reporting_schema_cids()
  let wire = context.project(check_cli_input("SELECT 1 AS id"))
  assert_true(wire.contains(reason))
  assert_true(wire.contains(outcome))
  assert_false(
    wire.contains(@checked.checking_environment_cid(context.environment)),
  )
  effect_finite_cli_ok(context.host.close(), "check.host.close")
}

///|
test "Native check hidden namespace stays unresolved while independent invalid input remains visible" {
  let (context, _) = check_cli_fixture("native-check-protected")
  let report = context.project(check_cli_input("SELECT * FROM inaccessible"))
  assert_true(report.contains("unresolved_protected"), msg=report)
  assert_false(report.contains("query_alias_absent"), msg=report)
  let invalid = context.project({
    document: "SELECT @count AS id",
    format: Sql,
    declarations: Some("{\"count\":{\"type\":\"number\",\"nullable\":false}}"),
    parameters: Some("{\"count\":\"private-input-value\"}"),
  })
  assert_eq(
    local_explain_field(check_cli_report(invalid), "verdict"),
    Json::string("invalid"),
  )
  assert_false(invalid.contains("private-input-value"))
  effect_finite_cli_ok(context.host.close(), "check.host.close")
}

///|
test "Native check missing parameters use the same Owner requirements and runnable reasons" {
  let (context, _) = check_cli_fixture("native-check-missing")
  let report = context.project({
    document: "SELECT @count AS id",
    format: Sql,
    declarations: Some("{\"count\":{\"type\":\"number\",\"nullable\":false}}"),
    parameters: None,
  })
  assert_true(report.contains("parameter_value_required"), msg=report)
  assert_eq(
    local_explain_field(
      local_explain_field(check_cli_report(report), "runnable"),
      "verdict",
    ),
    Json::string("no"),
  )
  effect_finite_cli_ok(context.host.close(), "check.host.close")
}

///|
test "Native check refuses a retired original Host instead of returning a prior verdict" {
  let (context, _) = check_cli_fixture("native-check-retired")
  let input = check_cli_input("SELECT 1 AS id")
  assert_true(context.project(input).contains("\"outcome\":\"completed\""))
  effect_finite_cli_ok(context.host.close(), "check.host.close")
  let unavailable = context.project(input)
  assert_true(unavailable.contains("\"outcome\":\"unavailable\""))
  assert_false(unavailable.contains("\"report\""))
  assert_false(unavailable.contains("\"context_ref\""))
}

///|
test "Native check reads original file-backed Program and parameters through the public command consumer" {
  let (context, root) = check_cli_fixture("native-check-command")
  let files = effect_finite_cli_ok(
    @local_filesystem.open_private_root(root),
    "check.inputs",
  )
  result_fresh_host_write(files, "program.json", public_run_result_program)
  effect_finite_cli_ok(files.close(), "check.inputs.close")
  let parsed = command().parse(
    argv=[
      "--mode", "local", "check", "--program-file", "program.json", "--format", "json",
      "--json",
    ],
    env=Map([]),
  )
  let report = local_check_for_host(
    context.host,
    context.crypto,
    "config.json",
    root,
    parsed.subcommand.unwrap().1,
  )
  assert_true(report.contains("\"outcome\":\"completed\""), msg=report)
  assert_eq(
    local_explain_field(
      local_explain_field(check_cli_report(report), "runnable"),
      "verdict",
    ),
    Json::string("yes"),
  )
  assert_true(report.contains("\"document_id\":\"program\""))
  assert_false(report.contains("\"document_id\":\"source\""))
  effect_finite_cli_ok(context.host.close(), "check.host.close")
}

///|
let check_cli_yaml_program : String =
  #|version: actql/0.1
  #|id: native.yaml.original
  #|params:
  #|  x: {type: number, nullable: false}
  #|stages:
  #|  - id: main
  #|    inputs: {}
  #|    steps:
  #|      - values:
  #|          schema:
  #|            n: {type: number, nullable: false}
  #|          rows: [{n: 1}]
  #|        as: rows
  #|      - derive: {value: 'n + $x'}
  #|        as: derived
  #|    results:
  #|      r: {from: derived, fields: [value]}
  #|results:
  #|  answer: {from: {stage: main, result: r}}

///|
test "Native check reads original YAML Program and separately JSON Parameters through the command consumer" {
  let (context, root) = check_cli_fixture("native-check-yaml-command")
  let original = ("# é 😀\n" + check_cli_yaml_program).replace_all(
    old="\n",
    new="\r\n",
  )
  let files = effect_finite_cli_ok(
    @local_filesystem.open_private_root(root),
    "check.yaml.inputs",
  )
  result_fresh_host_write(files, "program.yaml", original)
  result_fresh_host_write(files, "parameters.json", "{\"x\":2}")
  effect_finite_cli_ok(files.close(), "check.yaml.inputs.close")
  let parsed = command().parse(
    argv=[
      "--mode", "local", "check", "--program-file", "program.yaml", "--format", "yaml",
      "--parameters-file", "parameters.json", "--json",
    ],
    env=Map([]),
  )
  let wire = local_check_for_host(
    context.host,
    context.crypto,
    "config.json",
    root,
    parsed.subcommand.unwrap().1,
  )
  let report = check_cli_report(wire)
  assert_eq(local_explain_field(report, "verdict"), Json::string("verified"))
  assert_eq(
    local_explain_field(local_explain_field(report, "runnable"), "verdict"),
    Json::string("yes"),
  )
  assert_true(wire.contains("\"document_id\":\"program\""))
  // Independent UTF-8 count includes the original Unicode comment and CR/LF.
  assert_true(wire.contains("\"byte_length\":449"))
  // The command creates its own fresh key. Check exact revision binding only
  // within one original context, never by borrowing another context's key.
  let keyed = context.project({
    document: original,
    format: Yaml,
    declarations: None,
    parameters: Some("{\"x\":2}"),
  })
  assert_true(keyed.contains(context.revision("program", original)))
  assert_true(keyed.contains(context.revision("parameters", "{\"x\":2}")))
  assert_false(wire.contains("\"document_id\":\"source\""))
  effect_finite_cli_ok(context.host.close(), "check.yaml.host.close")
}

///|
test "Native YAML check preserves format and exact original context binding without changing JSON" {
  let (context, _) = check_cli_fixture("native-check-yaml-reference")
  // JSON spelling is also a valid YAML input, but its parser selection is distinct.
  let json : LocalCheckInput = {
    document: public_run_result_program,
    format: Json,
    declarations: None,
    parameters: None,
  }
  let yaml : LocalCheckInput = { ..json, format: Yaml, }
  let reference = context.reference(yaml)
  assert_eq(reference, context.reference(yaml))
  assert_false(reference == context.reference(json))
  assert_eq(
    context.revision("program", yaml.document),
    context.revision("program", json.document),
  )
  assert_false(
    context.reference({ ..yaml, document: "# é\r\n" + yaml.document, }) ==
    context.reference({ ..yaml, document: "# é\n" + yaml.document, }),
  )
  let before = context.project(json)
  assert_true(before.contains("\"verdict\":\"verified\""))
  let yaml_wire = context.project(yaml)
  assert_true(yaml_wire.contains("\"verdict\":\"verified\""))
  assert_true(yaml_wire.contains(reference))
  let after = context.project(json)
  assert_eq(check_cli_report(before), check_cli_report(after))
  effect_finite_cli_ok(context.host.close(), "check.yaml.reference.close")
}

///|
test "Native YAML check retains malformed original and JSON parameter refusals and terminal current" {
  let (context, _) = check_cli_fixture("native-check-yaml-refusal")
  let input : LocalCheckInput = {
    document: check_cli_yaml_program,
    format: Yaml,
    declarations: None,
    parameters: None,
  }
  let missing = context.project(input)
  assert_true(missing.contains("parameter_value_required"))
  for parameters in ["{\"x\":null}", "{\"x\":\"private-yaml-value\"}", "x: 2"] {
    let wire = context.project({ ..input, parameters: Some(parameters), })
    assert_eq(
      local_explain_field(check_cli_report(wire), "verdict"),
      Json::string("invalid"),
    )
    assert_false(wire.contains("private-yaml-value"))
  }
  let malformed = context.project({
    ..input,
    document: "version: [unterminated",
  })
  assert_eq(
    local_explain_field(check_cli_report(malformed), "verdict"),
    Json::string("invalid"),
  )
  effect_finite_cli_ok(context.host.close(), "check.yaml.refusal.close")
  let unavailable = context.project({ ..input, parameters: Some("{\"x\":2}"), })
  assert_true(unavailable.contains("\"outcome\":\"unavailable\""))
  assert_false(unavailable.contains("\"report\""))
  assert_false(unavailable.contains("\"context_ref\""))
}
