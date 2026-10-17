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
    declarations: Some(
      "[{\"name\":\"count\",\"type\":{\"type\":\"number\",\"nullable\":false}}]",
    ),
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
    declarations: Some(
      "[{\"name\":\"count\",\"type\":{\"type\":\"number\",\"nullable\":false}}]",
    ),
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
