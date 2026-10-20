///|
test "Result file selection preserves explicit formats names and normalized destinations" {
  let child = result_command_child([
    "result", "original-run", "--result", "answer", "--output", "./output.jsonl",
    "--receipt", "receipt.json", "--json",
  ])
  let selected = local_result_delivery_selection(child, "/project")
  assert_eq(selected.files.length(), 1)
  assert_eq(selected.files[0].result_name, Some("answer"))
  assert_eq(selected.files[0].format, "jsonl")
  assert_eq(selected.files[0].path, "/project/output.jsonl")
  assert_eq(selected.receipt, Some("/project/receipt.json"))
  assert_true(selected.json)
  let multiple = result_command_child([
    "result", "original-run", "--deliver", "first=csv:first.csv", "--deliver", "second=json:sub/second=copy:2.json",
  ])
  let selected = local_result_delivery_selection(multiple, "/project")
  assert_eq(selected.files.length(), 2)
  assert_eq(selected.files[0].result_name, Some("first"))
  assert_eq(selected.files[0].format, "csv")
  assert_eq(selected.files[1].result_name, Some("second"))
  assert_eq(selected.files[1].path, "/project/sub/second=copy:2.json")
}

///|
test "Result file selection rejects conflicting destinations before acquisition" {
  for
    (tail, expected) in [
      (
        ["--deliver", "answer=json:a.json", "--output", "b.json"],
        "ConflictingLocalResultDelivery",
      ),
      (
        ["--deliver", "answer=json:a.json", "--result", "answer"],
        "ConflictingLocalResultDelivery",
      ),
      (
        ["--deliver", "answer=json:a.json", "--format", "json"],
        "ConflictingLocalResultDelivery",
      ),
      (
        ["--deliver", "one=json:a.json", "--deliver", "two=csv:./sub/../a.json"],
        "ConflictingLocalResultDestination",
      ),
      (
        ["--output", "a.json", "--receipt", "./a.json"],
        "ConflictingLocalResultDestination",
      ),
      (["--receipt", "receipt.json"], "LocalResultReceiptRequiresFile"),
      (["--json"], "LocalResultJsonEnvelopeUnavailable"),
    ] {
    let argv = ["result", "original-run"]
    argv.append(tail)
    let child = result_command_child(argv)
    let issue = try {
      ignore(local_result_delivery_selection(child, "/project"))
      "unexpected acceptance"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(issue, expected)
  }
}

///|
test "Result file selection bounds input and preserves the ordinary stdout route" {
  for
    value in [
      "answer",
      "=json:a",
      "answer=:a",
      "answer=json:",
      "answer=json:/",
      "answer=json:bad\u{0000}file",
      "answer=json:" + "x".repeat(4097),
    ] {
    let child = result_command_child([
      "result", "original-run", "--deliver", value,
    ])
    let refused = try {
      ignore(local_result_delivery_selection(child, "/project"))
      false
    } catch {
      ClientStop(_) => true
    }
    assert_true(refused)
  }
  let selected = local_result_delivery_selection(
    result_command_child(["result", "original-run", "--format", "json"]),
    "/project",
  )
  assert_eq(selected.files.length(), 0)
  assert_eq(selected.receipt, None)
  assert_false(selected.json)
}
