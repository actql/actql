///|
fn result_read_account(
  run_read : @authorization.ConfiguredOutcome,
  result_read : @authorization.ConfiguredOutcome,
  resource? : String = "result/answer",
  principal? : String = "local-user",
  connection? : String = "python.local",
) -> @authorization.AdmittedAccountConfiguration {
  let original_wire =
    #|{"version":"actql-execution-account-config/0.1","account_id":"local-account","entries":[{"entry_id":"publication","outcome":"allow","principal":{"any_of":["local-user"]},"connection":{"any_of":["python.local"]},"resource":{"any_of":["run"]},"operation":{"any_of":["publish"]},"exclusions":[]},{"entry_id":"submission","outcome":"allow","principal":{"all":true},"connection":{"any_of":["python.local"]},"resource":{"any_of":["runs"]},"operation":{"any_of":["submit"]},"exclusions":[]}]}
  let config = @authorization.decode_account_configuration_json(original_wire).unwrap()
  let entries = config.entries
  for
    (entry_id, outcome, selected) in [
      ("run-read", run_read, "run"),
      ("result-read", result_read, resource),
    ] {
    entries.push({
      entry_id,
      outcome,
      scope: {
        principal: AnyOf([principal]),
        connection: AnyOf([connection]),
        resource: AnyOf([selected]),
        operation: AnyOf(["read"]),
      },
      exclusions: [],
    })
  }
  @authorization.admit_account_configuration({ ..config, entries, }).unwrap()
}

///|
test "named Local Result read requires both original current Run and Result Account decisions" {
  let original = result_read_account(Allow, Allow)
  let (host, preflight) = account_publisher_preflight(original)
  validate_local_preflight_result_read_current(preflight, original, "answer").unwrap()
  for
    current in [
      run_read_account(Allow),
      result_read_account(Allow, Deny),
      result_read_account(Deny, Allow),
      result_read_account(Allow, Allow, resource="result/foreign"),
      result_read_account(Allow, Allow, principal="foreign-user"),
      result_read_account(Allow, Allow, connection="foreign-connection"),
    ] {
    assert_true(
      validate_local_preflight_result_read_current(preflight, current, "answer")
      is Err(AuthorizationMismatch),
    )
    // Bind to that same Account too: an original-configuration fence must
    // not hide the missing or denied independent Result-read decision.
    let (same_host, same_preflight) = account_publisher_preflight(current)
    assert_true(
      validate_local_preflight_result_read_current(
        same_preflight, current, "answer",
      )
      is Err(AuthorizationMismatch),
    )
    close_account_publisher_fixture(same_host)
  }
  assert_false(@strategy.captured_task_completed(local_compute_run(host), 0))
  assert_eq(
    @resources.ledger_usage(
      @strategy.captured_dag_ledger(local_compute_run(host)),
    ).attempts,
    0,
  )
  close_account_publisher_fixture(host)
}

///|
test "named Local Result read cannot use wildcard or missing name outside original checked inventory" {
  let original = result_read_account(Allow, Allow)
  let (host, preflight) = account_publisher_preflight(original)
  for name in ["missing", "*", "answer/foreign", ""] {
    assert_true(
      validate_local_preflight_result_read_current(preflight, original, name)
      is Err(MissingResult),
    )
  }
  close_account_publisher_fixture(host)
}
