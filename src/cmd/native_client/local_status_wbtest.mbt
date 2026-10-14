///|
test "Native Local status ID selects without input files or another operation identity" {
  let parsed = command().parse(
    argv=["--mode", "local", "status", "--run-id", "original-run", "--json"],
    env=Map([]),
  )
  guard parsed.subcommand is Some(("status", child)) else {
    fail("missing original status command")
  }
  assert_eq(optional(child, "run-id"), Some("original-run"))
  assert_eq(optional(child, "ref-file"), None)
  assert_eq(optional(child, "submission-ref-file"), None)
  assert_true(child.flags.get("json").unwrap_or(false))
  assert_true(local_product_operation("status"))
}

///|
test "Native Remote status rejects Local original ID before transport or file access" {
  let parsed = command().parse(
    argv=["status", "--run-id", "original-run"],
    env=Map([]),
  )
  let issue = try {
    ignore(execute(parsed))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(
    issue, "Original Local status selection is unavailable in Remote mode",
  )
}

///|
test "Native status retains authenticated reference grammar and typed Unknown" {
  let parsed = command().parse(
    argv=[
      "--mode", "local", "status", "--ref-file", "original-run.json", "--submission-ref-file",
      "original-submission.json",
    ],
    env=Map([]),
  )
  let (_, child) = parsed.subcommand.unwrap()
  assert_eq(optional(child, "run-id"), None)
  assert_eq(optional(child, "ref-file"), Some("original-run.json"))
  assert_eq(
    optional(child, "submission-ref-file"),
    Some("original-submission.json"),
  )
  assert_eq(
    local_saved_state_issue(
      @local_host.NativeClientSavedRunStateIssue::Unavailable,
    ),
    "LocalOriginalRunStateUnavailable",
  )
  assert_eq(
    local_saved_state_issue(
      @local_host.NativeClientSavedRunStateIssue::Journal(
        @local_host.TransactionUnknown,
      ),
    ),
    "LocalRunStateLookupUnknown",
  )
}
