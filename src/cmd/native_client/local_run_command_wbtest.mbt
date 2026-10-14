///|
fn run_command_fixture(json : Bool) -> @argparse.Matches raise {
  let argv = [
    "--mode", "local", "run", "--program-file", "literal.sql", "--format", "sql",
    "--submission-ref-file", "original-submission.json", "--operation-attempt-id",
    "original-attempt", "--request-id", "original-nonce",
  ]
  if json {
    argv.push("--json")
  }
  command().parse(argv=argv[:], env=Map([]))
}

///|
test "Native Local run retains the original reference nonce and explicit attempt" {
  let parsed = run_command_fixture(true)
  guard parsed.subcommand is Some(("run", child)) else {
    fail("missing run command")
  }
  assert_eq(required(child, "submission-ref-file"), "original-submission.json")
  assert_eq(required(child, "operation-attempt-id"), "original-attempt")
  assert_eq(optional(child, "request-id"), Some("original-nonce"))
  assert_eq(required(child, "format"), "sql")
  assert_eq(local_run_original_operation(), "aql")
  assert_true(local_product_operation("run"))
}

///|
test "Native Local run refuses omitted original operation identities" {
  for
    argv in [
      [
        "run", "--program-file", "literal.sql", "--format", "sql", "--operation-attempt-id",
        "original-attempt",
      ],
      [
        "run", "--program-file", "literal.sql", "--format", "sql", "--submission-ref-file",
        "original-submission.json",
      ],
    ] {
    assert_true(
      try {
        command().parse(argv=argv[:], env=Map([])) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "Native run refuses Remote before connection files or input are read" {
  let parsed = command().parse(
    argv=[
      "run", "--program-file", "absent.sql", "--format", "sql", "--submission-ref-file",
      "absent.json", "--operation-attempt-id", "original",
    ],
    env=Map([]),
  )
  let issue = try {
    ignore(execute(parsed))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "operation requires an explicit Local configuration")
}

///|
test "Native Local run uses the existing exact AQL submitted intent bytes" {
  let parsed = run_command_fixture(true)
  let (_, child) = parsed.subcommand.unwrap()
  let root = @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli"
  let input = local_intent_wire(root, local_run_original_operation(), child)
  let original = @run_host.prepare_client_submitted_intent(
    input, 65536, 8192, 64,
  ).unwrap()
  let wire = @run_host.client_submitted_intent_wire(original)
  // Independent canonical input: no new command field, nonce or attempt enters
  // the original submitted-content body. Reference validation remains with the
  // existing submission Owner, not this bounded input reader.
  assert_eq(
    wire,
    (
      #|{"input":{"format":"sql","text":"SELECT 1 AS id\n"},"kind":"aql","parameters":null}
    ),
  )
}

///|
test "Native Local run output preserves Unknown and the original JSON bytes" {
  let json = run_command_fixture(true).subcommand.unwrap().1
  let human = run_command_fixture(false).subcommand.unwrap().1
  let unknown = "SubmissionUnknown original-reference original-attempt"
  assert_eq(local_run_reply(json, unknown), unknown)
  assert_eq(
    local_run_reply(human, unknown),
    "Local run response (original Submission preserved):\n" + unknown,
  )
}
