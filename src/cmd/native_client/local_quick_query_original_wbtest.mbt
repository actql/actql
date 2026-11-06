///|
test "Ordinary literal queries select Local preparation without a project or a replacement operation" {
  for operation in ["sql", "aql"] {
    let selected = quick_query_arguments([
      operation, "SELECT 1 AS id", "--format", "jsonl",
    ])
    assert_true(local_command_preparation_selected(selected))
    local_project_apply_selection(selected, None)
    assert_eq(required(selected, "mode"), "local")
    assert_eq(optional(selected, "state-dir"), None)
    assert_true(
      local_command_preparation_operation_selected(selected, operation, true),
    )
    assert_false(
      local_command_preparation_operation_selected(selected, operation, false),
    )
    assert_false(
      local_command_preparation_operation_selected(selected, "result", true),
    )
    assert_true(local_payload_already_streamed(selected))
    assert_true(command_preparation_invocation.val is None)
  }
}

///|
test "Literal query discovery preserves explicit Remote and legacy file backed selection" {
  for operation in ["sql", "aql"] {
    for
      prefix in [
        ["--mode", "remote"],
        ["--endpoint", "https://example.invalid/"],
      ] {
      let arguments = prefix.copy()
      for argument in [operation, "SELECT 1 AS id", "--format", "jsonl"] {
        arguments.push(argument)
      }
      let selected = quick_query_arguments(arguments[:])
      assert_false(local_command_preparation_selected(selected))
      local_project_apply_selection(selected, None)
      assert_eq(required(selected, "mode"), "remote")
      assert_false(local_payload_already_streamed(selected))
    }
  }
  let legacy = quick_query_arguments([
    "aql", "--program-file", "original.sql", "--format", "sql", "--submission-ref-file",
    "original.json", "--operation-attempt-id", "original",
  ])
  local_project_apply_selection(legacy, None)
  assert_eq(required(legacy, "mode"), "remote")
  assert_false(local_command_preparation_selected(legacy))
}

///|
test "Unsupplied literal query destinations refuse before any original submission" {
  for
    (args, expected) in [
      (["sql", "SELECT 1"], "LocalQueryTablePresentationUnavailable"),
      (
        ["aql", "SELECT 1", "--format", "jsonl", "--output", "rows.jsonl"],
        "LocalResultFileDeliveryUnavailable",
      ),
    ] {
    let selected = quick_query_arguments(args[:])
    let issue = try {
      ignore(local_quick_query_delivery(selected.subcommand.unwrap().1))
      "unexpected delivery"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(issue, expected)
    assert_true(command_preparation_invocation.val is None)
    assert_true(initial_crypto_invocation.val is None)
  }
}

///|
test "ordinary literal File selection retains bounded exact presentation metadata" {
  for operation in ["sql", "aql"] {
    for format in ["json", "jsonl", "csv"] {
      let parsed = quick_query_arguments([
        operation, "SELECT 1 AS id", "--format", format, "--output", "results éé.jsonl",
      ])
      let (_, child) = parsed.subcommand.unwrap()
      assert_eq(
        local_quick_query_file_output(child, "/explicit-project"),
        Some("/explicit-project/results éé.jsonl"),
      )
      assert_true(command_preparation_invocation.val is None)
      assert_true(initial_crypto_invocation.val is None)
    }
  }
  let stdout = quick_query_arguments(["sql", "SELECT 1"])
  assert_eq(
    local_quick_query_file_output(
      stdout.subcommand.unwrap().1,
      "/explicit-project",
    ),
    None,
  )
}

///|
test "ordinary literal File selection refuses unsupported or invalid destinations before submission" {
  for
    (arguments, expected) in [
      (
        ["sql", "SELECT 1", "--output", "rows.txt"],
        "LocalResultFileDeliveryUnavailable",
      ),
      (
        ["aql", "SELECT 1", "--format", "jsonl", "--output", "directory/"],
        "InvalidLocalResultDestination",
      ),
      (
        ["sql", "SELECT 1", "--format", "csv", "--output", ""],
        "invalid or repeated option --output",
      ),
    ] {
    let parsed = quick_query_arguments(arguments[:])
    let issue = try {
      local_quick_query_file_output(
        parsed.subcommand.unwrap().1,
        "/explicit-project",
      )
      |> ignore
      "unexpected destination"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(issue, expected)
    assert_true(command_preparation_invocation.val is None)
    assert_true(initial_crypto_invocation.val is None)
  }
  let empty_destination = try {
    ignore(local_result_output_path("/explicit-project", ""))
    "unexpected destination"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(empty_destination, "InvalidLocalResultDestination")
}

///|
test "literal File delivery selects only the exact original final Run and keeps its correlation" {
  let original =
    #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"succeeded","revision":0,"updated_at":"2026-10-20T00:00:00.000Z","next_action":{"kind":"refresh_availability","results":["answer"]},"result_available":false,"result_availability":{"answer":{"state":"unknown","observed_at":"2026-10-20T00:00:00.000Z","reason":"verification_pending"}}}
  let (file, correlation) = local_quick_query_result(
    original,
    "jsonl",
    output=Some("/explicit-project/results éé.jsonl"),
  )
  assert_eq(required(file, "run"), "original-run")
  assert_eq(
    optional(file, "output"),
    Some("/explicit-project/results éé.jsonl"),
  )
  assert_eq(optional(file, "format"), Some("jsonl"))
  assert_true(correlation.contains("originalRunId=\"original-run\""))
  let (stdout, same) = local_quick_query_result(original, "jsonl")
  assert_eq(optional(stdout, "output"), None)
  assert_eq(required(stdout, "run"), required(file, "run"))
  assert_eq(same, correlation)
  // A running original must also carry its normative nonfinal next action.
  let pending = original
    .replace_all(old="\"status\":\"succeeded\"", new="\"status\":\"running\"")
    .replace_all(
      old="\"next_action\":{\"kind\":\"refresh_availability\",\"results\":[\"answer\"]}",
      new="\"next_action\":{\"kind\":\"none\"}",
    )
  let issue = try {
    local_quick_query_result(
      pending,
      "jsonl",
      output=Some("/explicit-project/not-opened.jsonl"),
    )
    |> ignore
    "unexpected nonfinal Run"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(issue, "LocalQueryNotFinal" + correlation)
}
