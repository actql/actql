///|
test "only original Unsupported projects a pre-admission refusal" {
  assert_true(
    client_program_installed_managed_run_issue_is_unsupported(
      @client_local_host.Unsupported,
    ),
  )
  let others : Array[@client_local_host.ClientInstalledManagedRunIssue] = [
    @client_local_host.ForeignOriginal,
    @client_local_host.AlreadyBound,
    @client_local_host.Retired,
    @client_local_host.CleanupPending,
    @client_local_host.InsufficientCapacity,
  ]
  for issue in others {
    assert_false(
      client_program_installed_managed_run_issue_is_unsupported(issue),
    )
  }
}
