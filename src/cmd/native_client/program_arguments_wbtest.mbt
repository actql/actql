///|
fn public_program_arguments(
  operation : String,
  extra : ArrayView[String],
) -> @argparse.Matches raise {
  let argv = ["--mode", "local", operation]
  for value in extra {
    argv.push(value)
  }
  if operation == "run" {
    argv.push("--submission-ref-file")
    argv.push("original-submission.json")
    argv.push("--operation-attempt-id")
    argv.push("original-attempt")
  }
  command().parse(argv=argv[:], env=Map([]))
}

///|
test "public Program positions select the same Native input for check explain and run" {
  for operation in ["check", "explain", "run"] {
    let matches = public_program_arguments(operation, ["program.aql", "--json"])
    normalize_native_program_arguments(matches)
    normalize_native_program_arguments(matches)
    let (_, child) = matches.subcommand.unwrap()
    assert_eq(optional(child, "program"), None)
    assert_eq(required(child, "program-file"), "program.aql")
    assert_eq(required(child, "format"), "aql-text")
    assert_true(child.flags.get("json").unwrap_or(false))
  }
}

///|
test "public params aliases preserve the original separate values file" {
  for operation in ["check", "explain", "run"] {
    let matches = public_program_arguments(operation, [
      "program.aql", "--params", "parameters.json",
    ])
    normalize_native_program_arguments(matches)
    let (_, child) = matches.subcommand.unwrap()
    assert_eq(optional(child, "parameters-file"), Some("parameters.json"))
    assert_eq(optional(child, "parameter-declarations-file"), None)
  }
}

///|
test "public Program arguments never infer source representation from a suffix" {
  for name in ["program.sql", "program.json", "program.yaml", "program"] {
    let matches = public_program_arguments("check", [name])
    normalize_native_program_arguments(matches)
    let (_, child) = matches.subcommand.unwrap()
    assert_eq(required(child, "format"), "aql-text")
  }
  let matches = public_program_arguments("check", [
    "program.json", "--format", "aql-json",
  ])
  normalize_native_program_arguments(matches)
  assert_eq(required(matches.subcommand.unwrap().1, "format"), "aql-json")
}

///|
test "named original inputs retain the exact format parameters and invocation identity" {
  let matches = public_program_arguments("run", [
    "--program-file", "original.sql", "--format", "sql", "--parameters-file", "original-parameters.json",
    "--request-id", "original-nonce",
  ])
  normalize_native_program_arguments(matches)
  let (_, child) = matches.subcommand.unwrap()
  assert_eq(required(child, "program-file"), "original.sql")
  assert_eq(required(child, "format"), "sql")
  assert_eq(
    optional(child, "parameters-file"),
    Some("original-parameters.json"),
  )
  assert_eq(required(child, "submission-ref-file"), "original-submission.json")
  assert_eq(required(child, "operation-attempt-id"), "original-attempt")
  assert_eq(optional(child, "request-id"), Some("original-nonce"))
}

///|
test "ambiguous Program or params inputs are rejected by the actual argument parser" {
  for
    args in [
      ["program.aql", "--program-file", "other.aql"],
      ["program.aql", "--params", "a.json", "--parameters-file", "b.json"],
      ["first.aql", "second.aql"],
    ] {
    assert_true(
      try {
        ignore(public_program_arguments("check", args[:]))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "missing Program or legacy format is rejected before project or input file IO" {
  for
    (args, expected) in [
      (
        ["--mode", "local", "--config", "never-open.json", "check"],
        "ProgramFileRequired",
      ),
      (
        [
          "--mode", "local", "--config", "never-open.json", "check", "--program-file",
          "never-open.json",
        ],
        "ProgramSourceFormatRequired",
      ),
    ] {
    let matches = command().parse(argv=args[:], env=Map([]))
    let issue = try {
      ignore(execute_native_project_selection(matches))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(issue, expected)
  }
}

///|
test "dash-prefixed Program paths use the existing separator without becoming options" {
  let matches = public_program_arguments("check", ["--", "--program.aql"])
  normalize_native_program_arguments(matches)
  assert_eq(
    required(matches.subcommand.unwrap().1, "program-file"),
    "--program.aql",
  )
}

///|
test "other operations keep their original shape and are not Program aliases" {
  let matches = command().parse(
    argv=["--mode", "local", "connect"],
    env=Map([]),
  )
  normalize_native_program_arguments(matches)
  assert_true(optional(matches.subcommand.unwrap().1, "program-file") is None)
}

///|
test "public Program syntax produces the exact original submitted intent bytes" {
  let public = public_program_arguments("run", [
    "literal.sql", "--format", "sql",
  ])
  normalize_native_program_arguments(public)
  let root = @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli"
  let wire = local_intent_wire(
    root,
    local_run_original_operation(),
    public.subcommand.unwrap().1,
  )
  assert_eq(
    @run_host.client_submitted_intent_wire(
      @run_host.prepare_client_submitted_intent(wire, 65536, 8192, 64).unwrap(),
    ),
    (
      #|{"input":{"format":"sql","text":"SELECT 1 AS id\n"},"kind":"aql","parameters":null}
    ),
  )
}
