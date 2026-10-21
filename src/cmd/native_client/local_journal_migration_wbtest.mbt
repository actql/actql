///|
test "explicit Journal migration stays on ordinary Local adopt without signing consent" {
  let matches = command().parse(
    argv=["--mode", "local", "adopt", "--migrate-journal", "--json"],
    env=Map([]),
  )
  guard matches.subcommand is Some(("adopt", child)) else {
    fail("missing adopt")
  }
  assert_true(child.flags.get("migrate-journal").unwrap_or(false))
  assert_false(child.flags.get("initialize-signing").unwrap_or(false))
  assert_true(local_command_json_selected(matches))
  let ordinary = command().parse(argv=["--mode", "local", "adopt"], env=Map([]))
  assert_false(
    ordinary.subcommand.unwrap().1.flags.get("migrate-journal").unwrap_or(false),
  )
}

///|
test "Journal migration diagnostic retains Unknown without a Run container" {
  local_command_diagnostic_reset()
  command_preparation_diagnostic.val = JournalMaintenanceFailed
  let text = local_command_failure_text(
    local_journal_migration_issue(@local_host.TransactionUnknown),
    true,
  )
  assert_true(text.contains("ACTQL_E_COMMAND_FAILED"))
  assert_true(text.contains("LocalJournalMigrationUnknown"))
  assert_false(text.contains("run_id"))
  assert_eq(
    local_journal_migration_issue(@local_host.AuthorizationDenied),
    "LocalJournalMigrationAuthorizationDenied",
  )
  local_command_diagnostic_reset()
}
