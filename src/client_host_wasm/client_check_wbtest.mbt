///|
fn local_check_test_object(body : String) -> @decode.ObjectView {
  let source = @source.parse_json_bytes(@utf8.encode(body), {
    max_input_bytes: 1048576,
    max_nodes: 16384,
    max_depth: 64,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 16384,
    max_depth: 64,
    max_string_bytes: 1048576,
    max_total_string_bytes: 1048576,
  }).unwrap()
  @decode.open_object(cursor).unwrap()
}

///|
fn local_check_test_environment() -> @checked.CheckEnvironment {
  // Actual generated product configuration is DATA, not a physical supplier.
  let original = @host.client_local_product_bootstrap_originals(
    "/local-check-fixture", "2026-10-20T00:00:00.000Z",
  ).unwrap()
  @host.admit_local_relation_check_environment(
    original.environment,
    environment_body_cid(original.environment),
  ).unwrap()
}

///|
fn local_check_test_report(
  environment : @checked.CheckEnvironment,
  document : String,
  format : String,
) -> @decode.ObjectView raise {
  let writer = @encode.writer(4096, 16, 2)
  @encode.begin_object(writer)
  for
    (key, text) in [
      ("kind", "text"),
      ("scope", "bound_input"),
      ("document", document),
      ("format", format),
      ("context", "ctx:profile-local"),
      ("revision", "rev:" + "1".repeat(64)),
      ("correlation", "corr:profile-local"),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, text)
  }
  @encode.end_object(writer)
  let wire = client_check_report(
    environment,
    local_check_test_object(@encode.finish(writer)),
  ).unwrap()
  let outcome = local_check_test_object(wire)
  assert_eq(required_text(outcome, "outcome"), Some("completed"), msg=wire)
  @decode.open_object(@decode.required(outcome, "report").unwrap()).unwrap()
}

///|
test "Local public Check reports a real constant query without preparing a Run" {
  let report = client_check_report(
    local_check_test_environment(),
    local_check_test_object(
      (
        #|{"kind":"text","scope":"bound_input","document":"SELECT 1 AS id","format":"sql","context":"ctx:original-local","revision":"rev:1111111111111111111111111111111111111111111111111111111111111111","correlation":"corr:original"}
      ),
    ),
  ).unwrap()
  let outcome = local_check_test_object(report)
  assert_eq(required_text(outcome, "outcome"), Some("completed"))
  let result = @decode.open_object(@decode.required(outcome, "report").unwrap()).unwrap()
  assert_eq(required_text(result, "context_ref"), Some("ctx:original-local"))
  assert_eq(required_text(result, "verdict"), Some("verified"))
  assert_true(@decode.lookup(outcome, "correlation_ref") is None)
}

///|
test "Local public Check keeps authored syntax rejection in Common" {
  let report = client_check_report(
    local_check_test_environment(),
    local_check_test_object(
      (
        #|{"kind":"text","scope":"bound_input","document":"SELECT !","format":"sql","context":"ctx:invalid-local","revision":"rev:2222222222222222222222222222222222222222222222222222222222222222","correlation":"corr:invalid"}
      ),
    ),
  ).unwrap()
  let outcome = local_check_test_object(report)
  assert_eq(required_text(outcome, "outcome"), Some("completed"))
  let result = @decode.open_object(@decode.required(outcome, "report").unwrap()).unwrap()
  assert_eq(required_text(result, "verdict"), Some("invalid"))
  assert_eq(required_text(result, "context_ref"), Some("ctx:invalid-local"))
  assert_true(@decode.lookup(outcome, "correlation_ref") is None)
}

///|
test "Python Local Check admits the pinned numeric profile for PIVOT SUM and COUNT" {
  let environment = local_check_test_environment()
  let profiles = @checked.checking_environment_profile_selection(environment)
  assert_eq(
    profiles.numeric_profile_cid,
    Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  )
  let prefix =
    #|WITH r AS (
    #|  SELECT 'east' AS side, 1 AS v UNION ALL
    #|  SELECT 'west', 2 UNION ALL SELECT 'west', 3
    #|)
  for
    (document, format) in [
      (
        prefix + "\nFROM r |> PIVOT(SUM(v) FOR side IN ('east','west'))",
        "aql-text",
      ),
      (prefix + " SELECT SUM(v) AS n FROM r", "sql"),
      (prefix + " SELECT COUNT(v) AS n FROM r", "sql"),
    ] {
    let report = local_check_test_report(environment, document, format)
    assert_eq(required_text(report, "verdict"), Some("verified"), msg=document)
    assert_eq(
      @decode.array_length(@decode.required(report, "requirements").unwrap()),
      Some(0),
    )
  }
}

///|
test "Python Local Check selects text-time from the original installed policy" {
  let assets = @host.client_local_product_assets()
  let cid = environment_body_cid(assets.environment)
  let publication = "{\"environmentCid\":\"" + cid + "\",\"aliases\":[]}"
  let (published, _) = admit_python_local_published_input(
    assets.environment,
    publication,
  ).unwrap()
  for environment in [local_check_test_environment(), published] {
    assert_eq(@checked.checking_environment_cid(environment), cid)
    assert_true(
      @checked.checking_environment_profile_selection(environment).expressions.text_time,
    )
    let timestamp = local_check_test_report(
      environment, "SELECT PARSE_TIMESTAMP('yyyy-MM-dd', '2026-01-02') AS x", "sql",
    )
    assert_eq(required_text(timestamp, "verdict"), Some("verified"))
    let invalid = local_check_test_report(
      environment, "SELECT PARSE_TIMESTAMP('%Y', '2026') AS x", "sql",
    )
    assert_eq(required_text(invalid, "verdict"), Some("invalid"))
  }
}
