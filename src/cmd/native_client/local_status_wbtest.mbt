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

///|
test "public status Run position is the same original ID selection and is idempotent" {
  let parsed = command().parse(
    argv=["--mode", "local", "status", "original-run", "--json"],
    env=Map([]),
  )
  normalize_native_status_arguments(parsed)
  normalize_native_status_arguments(parsed)
  let (operation, child) = parsed.subcommand.unwrap()
  assert_eq(operation, "status")
  assert_eq(optional(child, "run"), None)
  assert_eq(optional(child, "run-id"), Some("original-run"))
  assert_eq(optional(child, "ref-file"), None)
  assert_eq(optional(child, "submission-ref-file"), None)
  assert_eq(optional(child, "operation-attempt-id"), None)
  assert_eq(optional(child, "request-id"), None)
  assert_true(child.flags.get("json").unwrap_or(false))
}

///|
test "public status position preserves the Remote refusal before endpoint and file access" {
  let parsed = command().parse(argv=["status", "original-run"], env=Map([]))
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
test "public status refuses positional ID mixed with another original selector" {
  for
    selectors in [
      ["--run-id", "other-run"],
      ["--ref-file", "never-open-run.json"],
      ["--submission-ref-file", "never-open-submission.json"],
    ] {
    let argv = ["--mode", "local", "status", "original-run"]
    for arg in selectors {
      argv.push(arg)
    }
    assert_true(
      try {
        ignore(command().parse(argv=argv[:], env=Map([])))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "public status requires one nonempty ID and never consumes multiple Run positions" {
  assert_true(
    try {
      ignore(
        command().parse(argv=["status", "first-run", "second-run"], env=Map([])),
      )
      false
    } catch {
      _ => true
    },
  )
  let parsed = command().parse(
    argv=["--mode", "local", "--config", "never-open-config.json", "status", ""],
    env=Map([]),
  )
  let issue = try {
    ignore(execute_native_project_selection(parsed))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "invalid or repeated option --run")
}

///|
test "status normalization leaves original reference and other command shapes unchanged" {
  let named = command().parse(
    argv=["status", "--ref-file", "original-run.json"],
    env=Map([]),
  )
  normalize_native_status_arguments(named)
  assert_eq(optional(named.subcommand.unwrap().1, "run-id"), None)
  assert_eq(
    optional(named.subcommand.unwrap().1, "ref-file"),
    Some("original-run.json"),
  )
  let connect = command().parse(
    argv=["--mode", "local", "connect"],
    env=Map([]),
  )
  normalize_native_status_arguments(connect)
  assert_eq(optional(connect.subcommand.unwrap().1, "run-id"), None)
}

///|
test "public status does not interpret a dash-prefixed original ID as an input file" {
  let parsed = command().parse(
    argv=["--mode", "local", "status", "--", "--original-run"],
    env=Map([]),
  )
  normalize_native_status_arguments(parsed)
  let child = parsed.subcommand.unwrap().1
  assert_eq(optional(child, "run-id"), Some("--original-run"))
  assert_eq(optional(child, "ref-file"), None)
  assert_eq(optional(child, "submission-ref-file"), None)
}
