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
  @host.admit_client_check_environment(
    original.environment,
    environment_body_cid(original.environment),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
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
