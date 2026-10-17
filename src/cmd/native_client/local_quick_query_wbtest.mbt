///|
fn quick_query_arguments(argv : ArrayView[String]) -> @argparse.Matches raise {
  let selected = command().parse(argv~, env=Map([]))
  normalize_native_query_arguments(selected)
  selected
}

///|
test "public quick queries select literal SQL and Pipe inputs without reading a Program file" {
  for (operation, format) in [("sql", "sql"), ("aql", "aql-text")] {
    let text = "SELECT 'é\r\n😀' AS value"
    let selected = quick_query_arguments([
      "--mode", "local", operation, text, "--format", "jsonl",
    ])
    let (_, child) = selected.subcommand.unwrap()
    assert_true(local_quick_query_requested(operation, child))
    assert_eq(optional(child, "program-file"), None)
    let wire = local_intent_wire("/never-open-this-root", operation, child)
    let original = @run_host.prepare_client_submitted_intent(
      wire, 65536, 8192, 64,
    ).unwrap()
    assert_true(@run_host.client_submitted_intent_requests_read_only(original))
    assert_false(
      @run_host.client_submitted_intent_requests_commit_stop(original),
    )
    let intent = @decode.open_object(local_input_cursor(wire)).unwrap()
    let input = @decode.open_object(@decode.required(intent, "input").unwrap()).unwrap()
    assert_eq(run_text(input, "text"), text)
    assert_eq(run_text(input, "format"), format)
    assert_eq(run_text(intent, "kind"), "aql")
    assert_true(
      @decode.is_null(@decode.required(intent, "parameters").unwrap()),
    )
  }
}

///|
test "quick query params aliases keep the original separate parameter input" {
  for operation in ["sql", "aql"] {
    let selected = quick_query_arguments([
      operation, "SELECT @value AS value", "--params", "parameters.json",
    ])
    normalize_native_query_arguments(selected)
    let (_, child) = selected.subcommand.unwrap()
    assert_eq(optional(child, "parameters-file"), Some("parameters.json"))
    assert_eq(optional(child, "params"), None)
    assert_eq(optional(child, "parameter-declarations-file"), None)
  }
}

///|
test "quick query result encoding never chooses the source parser" {
  for operation in ["sql", "aql"] {
    for format in ["json", "jsonl", "csv", "table"] {
      let selected = quick_query_arguments([
        operation, "SELECT 1 AS id", "--format", format,
      ])
      let (_, child) = selected.subcommand.unwrap()
      assert_eq(local_quick_query_format(child), format)
      let wire = local_intent_wire("/never-open-this-root", operation, child)
      let input = @decode.open_object(
        @decode.required(
          @decode.open_object(local_input_cursor(wire)).unwrap(),
          "input",
        ).unwrap(),
      ).unwrap()
      assert_eq(
        run_text(input, "format"),
        if operation == "sql" {
          "sql"
        } else {
          "aql-text"
        },
      )
    }
  }
  let selected = quick_query_arguments(["sql", "SELECT 1 AS id"])
  assert_eq(local_quick_query_format(selected.subcommand.unwrap().1), "table")
}

///|
test "quick query grammar refuses ambiguous original and output selections" {
  for
    args in [
      ["sql", "SELECT 1", "SELECT 2"],
      ["aql", "SELECT 1", "--program-file", "other.sql"],
      ["sql", "SELECT 1", "--params", "a.json", "--parameters-file", "b.json"],
      ["aql", "SELECT 1", "--stop-before", "commit"],
      ["aql", "SELECT 1", "--submission-ref-file", "original.json"],
      ["aql", "SELECT 1", "--request-id", "old-nonce"],
      ["sql", "SELECT 1", "--format", "sql"],
      ["sql", "SELECT 1", "--format", "JSON"],
    ] {
    assert_true(
      try {
        ignore(quick_query_arguments(args[:]))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "the existing file-backed AQL route retains original format and correlation" {
  let parsed = quick_query_arguments([
    "aql", "--program-file", "literal.sql", "--format", "sql", "--submission-ref-file",
    "original-submission.json", "--operation-attempt-id", "original-attempt", "--request-id",
    "original-nonce",
  ])
  let (_, child) = parsed.subcommand.unwrap()
  assert_false(local_quick_query_requested("aql", child))
  assert_eq(optional(child, "query"), None)
  let root = @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli"
  assert_eq(
    local_intent_wire(root, "aql", child),
    (
      #|{"input":{"format":"sql","text":"SELECT 1 AS id\n"},"kind":"aql","parameters":null}
    ),
  )
  assert_eq(required(child, "submission-ref-file"), "original-submission.json")
  assert_eq(required(child, "operation-attempt-id"), "original-attempt")
  assert_eq(optional(child, "request-id"), Some("original-nonce"))
}

///|
test "quick query Remote refusal precedes connection or input IO" {
  for operation in ["sql", "aql"] {
    let parsed = quick_query_arguments([
      "--mode", "remote", operation, "SELECT 1 AS id", "--format", "jsonl",
    ])
    let issue = try {
      ignore(execute(parsed))
      "unexpected success"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(issue, "QuickQueryRequiresLocalHost")
  }
}

///|
test "quick query payload routes do not append a second response or newline" {
  for operation in ["sql", "aql"] {
    let selected = quick_query_arguments([
      "--mode", "local", operation, "SELECT 1 AS id", "--format", "jsonl",
    ])
    assert_true(local_payload_already_streamed(selected))
    let remote = quick_query_arguments([
      "--mode", "remote", operation, "SELECT 1 AS id", "--format", "jsonl",
    ])
    assert_false(local_payload_already_streamed(remote))
  }
  let legacy = quick_query_arguments([
    "--mode", "local", "aql", "--program-file", "literal.sql", "--format", "sql",
    "--submission-ref-file", "original.json", "--operation-attempt-id", "original",
  ])
  assert_false(local_payload_already_streamed(legacy))
}
