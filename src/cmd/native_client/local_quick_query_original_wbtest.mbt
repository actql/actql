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
