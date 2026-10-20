///|
fn language_operation_reply(argv : Array[String]) -> String raise {
  local_command_diagnostic_reset()
  let pending : Ref[String?] = Ref(None)
  let parsed = command().parse(argv~, env=Map([]))
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
  execute_and_write_native_reply(parsed, pending)
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
  guard pending.val is Some(wire) else {
    fail("operation discovery must retain output for ordinary main")
  }
  wire
}

///|
test "public op list discovers complete signatures before Host or project acquisition" {
  let wire = language_operation_reply([
    "--config-root", "/not-an-existing-project", "op", "list", "--json",
  ])
  guard @json.parse(wire) is Array(rows) else { fail("operation array") }
  assert_eq(rows.length(), 69)
  let mut previous = ""
  for row in rows {
    let (name, family, signature, _) = local_language_operation_parts(row)
    assert_true(name > previous)
    previous = name
    assert_true(name.has_prefix(family + "."))
    assert_true(signature is Object(_))
    assert_true(name != "EFFECT.plan")
  }
}

///|
test "public op filters preserve exact families and output carriers" {
  let wire = language_operation_reply([
    "op", "list", "--family", "REL", "--output", "relation", "--json",
  ])
  guard @json.parse(wire) is Array(rows) else { fail("filtered array") }
  assert_true(!rows.is_empty())
  for row in rows {
    let (_, family, _, output) = local_language_operation_parts(row)
    assert_eq(family, "REL")
    assert_eq(output, "relation")
  }
  assert_eq(
    language_operation_reply(["op", "list", "--family", "rel", "--json"]),
    "[]",
  )
}

///|
test "public op show retains original alternatives and policy inputs" {
  for
    (name, field) in [
      ("SGA.shortest_path", "input_alternatives"),
      ("VEC.merge_rankings", "policy_inputs"),
      ("BRIDGE.rows.to_graph", "finite_inputs"),
    ] {
    let wire = language_operation_reply(["op", "show", name, "--json"])
    let (operation, _, signature, _) = local_language_operation_parts(
      @json.parse(wire),
    )
    assert_eq(operation, name)
    guard signature is Object(original) else { fail("complete signature") }
    assert_true(original.contains(field))
  }
}

///|
test "public op search requires all words without changing the retained signature" {
  let wire = language_operation_reply([
    "op", "search", "sGa", "SHORTEST_PATH", "--json",
  ])
  guard @json.parse(wire) is Array(rows) else { fail("search array") }
  assert_true(!rows.is_empty())
  for row in rows {
    let (name, _, signature, _) = local_language_operation_parts(row)
    let text = local_language_operation_search_text(
      name + " " + encode_request_json(signature, 1048576),
    )
    assert_true(text.contains("sga"))
    assert_true(text.contains("shortest_path"))
  }
  assert_eq(
    language_operation_reply(["op", "search", "absent-operation-word", "--json"]),
    "[]",
  )
  let human = language_operation_reply(["op", "show", "SGA.shortest_path"])
  assert_true(human.has_prefix("SGA.shortest_path {"))
  assert_true(human.contains("input_alternatives"))
}

///|
test "public op rejects missing extra and unknown selections before Host acquisition" {
  for
    argv in [
      ["op"],
      ["op", "show"],
      ["op", "show", "REL.select", "extra"],
      ["op", "list", "extra"],
      ["op", "search"],
      ["op", "show", "unknown.operation", "--json"],
    ] {
    let rejected = try {
      ignore(language_operation_reply(argv))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_true(command_preparation_invocation.val is None)
    assert_true(initial_crypto_invocation.val is None)
  }
}

///|
test "public op preserves the configured response limit without acquiring a Host" {
  let rejected = try {
    ignore(
      language_operation_reply([
        "--max-response-bytes", "16", "op", "list", "--json",
      ]),
    )
    false
  } catch {
    ClientStop(_) => true
    other => raise other
  }
  assert_true(rejected)
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}

///|
test "public op metadata rejection selects diagnostics without reinterpreting legacy Run carriers" {
  let original = try {
    ignore(
      language_operation_reply(["op", "show", "unknown.operation", "--json"]),
    )
    fail("unknown operation must reject before a Host exists")
  } catch {
    ClientStop(issue) => issue
    other => raise other
  }
  let output = local_command_failure_text(original, true)
  guard @json.parse(output) is Object(fields) else {
    fail("metadata rejection must be one diagnostic object")
  }
  assert_eq(fields.get("code"), Some(Json::string("ACTQL_E_COMMAND_FAILED")))
  assert_eq(fields.get("message"), Some(Json::string(original)))
  assert_eq(fields.length(), 2)
  assert_true(
    local_command_failure_text(original, false).has_prefix(
      "ACTQL_E_COMMAND_FAILED:",
    ),
  )
  local_command_diagnostic_reset()
  assert_eq(
    local_command_failure_text("retained-original-Run-carrier", true),
    "actql-native-client: retained-original-Run-carrier",
  )
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}
