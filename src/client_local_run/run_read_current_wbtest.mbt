///|
fn run_read_account(
  read : @authorization.ConfiguredOutcome,
  principal? : String = "local-user",
  connection? : String = "python.local",
) -> @authorization.AdmittedAccountConfiguration {
  let original_wire =
    #|{"version":"actql-execution-account-config/0.1","account_id":"local-account","entries":[{"entry_id":"publication","outcome":"allow","principal":{"any_of":["local-user"]},"connection":{"any_of":["python.local"]},"resource":{"any_of":["run"]},"operation":{"any_of":["publish"]},"exclusions":[]},{"entry_id":"submission","outcome":"allow","principal":{"all":true},"connection":{"any_of":["python.local"]},"resource":{"any_of":["runs"]},"operation":{"any_of":["submit"]},"exclusions":[]}]}
  let config = @authorization.decode_account_configuration_json(original_wire).unwrap()
  let entries = config.entries
  entries.push({
    entry_id: "read",
    outcome: read,
    scope: {
      principal: AnyOf([principal]),
      connection: AnyOf([connection]),
      resource: AnyOf(["run"]),
      operation: AnyOf(["read"]),
    },
    exclusions: [],
  })
  @authorization.admit_account_configuration({ ..config, entries, }).unwrap()
}

///|
test "original Local Run observation requires independent current Account read" {
  let original = run_read_account(Allow)
  let (host, preflight) = account_publisher_preflight(original)
  validate_local_preflight_run_read_current(preflight, original).unwrap()
  for
    current in [
      publisher_account(Allow),
      run_read_account(Deny),
      run_read_account(Allow, principal="another-user"),
      run_read_account(Allow, connection="another-connection"),
    ] {
    assert_true(
      validate_local_preflight_run_read_current(preflight, current)
      is Err(AuthorizationMismatch),
    )
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
