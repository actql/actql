///|
test "public Run file options retain input interpretation and separate receipt purposes" {
  let parsed = command().parse(argv=[
    "run", "--program-file", "literal.sql", "--format", "sql", "--output", "rows.jsonl",
    "--receipt", "run.json", "--json",
  ])
  normalize_native_program_arguments(parsed)
  let child = parsed.subcommand.unwrap().1
  let selected = local_result_delivery_selection(
    child,
    "/project",
    run_presentation=true,
  )
  assert_eq(required(child, "format"), "sql")
  assert_eq(selected.files.length(), 1)
  assert_eq(selected.files[0].format, "jsonl")
  assert_eq(selected.files[0].path, "/project/rows.jsonl")
  assert_eq(selected.receipt, Some("/project/run.json"))
  assert_true(selected.json)
  let root = @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli"
  let input = local_intent_wire(root, local_run_original_operation(), child)
  let original = @run_host.prepare_client_submitted_intent(
    input, 65536, 8192, 64,
  ).unwrap()
  assert_eq(
    @run_host.client_submitted_intent_wire(original),
    (
      #|{"input":{"format":"sql","text":"SELECT 1 AS id\n"},"kind":"aql","parameters":null}
    ),
  )
  let receipt_only = command().parse(argv=[
      "run", "program.aql", "--receipt", "run.json", "--json",
    ]).subcommand.unwrap().1
  let receipt = local_result_delivery_selection(
    receipt_only,
    "/project",
    run_presentation=true,
  )
  assert_eq(receipt.files.length(), 0)
  assert_eq(receipt.receipt, Some("/project/run.json"))
  assert_true(command_preparation_invocation.val is None)
}

///|
test "public Run validates all output destinations before original acquisition" {
  for
    argv in [
      [
        "run", "program.aql", "--output", "a.jsonl", "--deliver", "answer=json:b.json",
      ],
      ["run", "program.aql", "--output", "a.jsonl", "--receipt", "./a.jsonl"],
      [
        "run", "program.aql", "--deliver", "answer=json:a", "--deliver", "other=csv:./a",
      ],
      ["run", "program.aql", "--deliver", "answer=table:a"],
    ] {
    let selected = command().parse(argv=argv[:])
    let refused = try {
      normalize_native_program_arguments(selected)
      false
    } catch {
      ClientStop(_) => true
    }
    assert_true(refused)
    assert_true(command_preparation_invocation.val is None)
  }
  let selected = command().parse(argv=[
    "run", "program.aql", "--deliver", "answer=json:a.json", "--deliver", "other=csv:b.csv",
  ])
  normalize_native_program_arguments(selected)
  let delivery = local_result_delivery_selection(
    selected.subcommand.unwrap().1,
    "/project",
    run_presentation=true,
  )
  assert_eq(delivery.files.length(), 2)
  assert_eq(delivery.files[0].result_name, Some("answer"))
  assert_eq(delivery.files[1].format, "csv")
}

///|
test "Run output selects only its actual final returned ID without a new intent" {
  let child = command().parse(argv=[
      "run", "program.aql", "--output", "answer.jsonl", "--receipt", "run.json",
      "--json",
    ]).subcommand.unwrap().1
  let delivery = local_result_delivery_selection(
    child,
    "/project",
    run_presentation=true,
  )
  let original =
    #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"succeeded","revision":7,"updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"none"},"result_available":false,"result_availability":{}}
  let (result, correlation) = local_run_presentation_result(
    child, delivery, original,
  )
  assert_eq(required(result, "run"), "original-run")
  assert_eq(required(result, "output"), "/project/answer.jsonl")
  assert_eq(required(result, "format"), "jsonl")
  // Run receipt is exported independently; it never enters the per-delivery
  // Result receipt container or changes a delivery attempt's identity.
  assert_eq(optional(result, "receipt"), None)
  assert_true(correlation.contains("original-run"))
  let issue = try {
    ignore(local_run_presentation_result(child, delivery, run_display_minimal))
    "unexpected acceptance"
  } catch {
    ClientStop(issue) => issue
  }
  assert_true(issue.contains("LocalRunResultDeliveryNotReady"))
  assert_true(issue.contains("original-run"))
  assert_true(command_preparation_invocation.val is None)
}
