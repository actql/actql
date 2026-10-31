///|
test "GitHub CREATE native inventory covers both escaped request Strings before HTTP admission" {
  // These values satisfy the ORIGINAL native character/unit bounds. Each SOH
  // becomes six units in the body and seven when that body is exported again.
  // HTTP's later 300000-byte refusal cannot back this earlier constructor.
  let subject = "\u{1}".repeat(256)
  let body = "\u{1}".repeat(65536)
  let original = @catalog.add_comment_request(subject, body).unwrap()
  let exported = github_add_comment_request_json(subject, body)
  let inventory = github_comment_request_construction_inventory(false).unwrap()
  let (inner, outer) = github_comment_request_wire_bounds(false)
  assert_eq(original.length().to_int64(), inner)
  assert_eq(exported.length().to_int64(), outer)
  assert_true(inner > 300000L)
  // Both Strings and each builder's old/new concatenation coexist in this
  // conservative retained envelope; borrowed subject/body are counted outside.
  assert_eq(inventory.owned_utf16_units, 2L * inner + 2L * outer + 8L)
  let capacity = github_add_comment_request_construction_capacity().unwrap()
  let cost = @execution.preparation_representation_cost(inventory).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), cost)
  assert_eq(@execution.execution_capacity_execution_bytes(capacity), cost)
  assert_eq(@json.parse(exported), ({ "body": original.to_json() } : Json))
}

///|
test "GitHub CREATE constructor inventory does not change original Unicode or refusal boundaries" {
  let subject = "I_original"
  let body = "\u{1F600}".repeat(65536)
  let original = @catalog.add_comment_request(subject, body).unwrap()
  let exported = github_add_comment_request_json(subject, body)
  let (inner, outer) = github_comment_request_wire_bounds(false)
  assert_true(original.length().to_int64() < inner)
  assert_true(exported.length().to_int64() < outer)
  assert_eq(@json.parse(exported), ({ "body": original.to_json() } : Json))
  assert_eq(
    github_add_comment_request_json(subject, body + "x"),
    "{\"refused\":\"InvalidBody\"}",
  )
  assert_eq(
    github_add_comment_request_json("x".repeat(257), "original"),
    "{\"refused\":\"InvalidSubjectId\"}",
  )
  assert_eq(
    github_add_comment_request_json(subject, ""),
    "{\"refused\":\"InvalidBody\"}",
  )
}

///|
test "GitHub subject-check inventory is separate and prices the same original export" {
  let subject = "\u{1}".repeat(256)
  let original = @catalog.comment_subject_request(subject).unwrap()
  let exported = github_comment_subject_request_json(subject)
  let (inner, outer) = github_comment_request_wire_bounds(true)
  assert_eq(original.length().to_int64(), inner)
  assert_eq(exported.length().to_int64(), outer)
  assert_eq(@json.parse(exported), ({ "body": original.to_json() } : Json))
  let capacity = github_comment_subject_request_construction_capacity().unwrap()
  let mutation = github_add_comment_request_construction_capacity().unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(capacity) <
    @execution.execution_capacity_retained_bytes(mutation),
  )
  assert_eq(
    github_comment_subject_request_json(""),
    "{\"refused\":\"InvalidSubjectId\"}",
  )
}

///|
test "standard CREATE native profile preserves original HTTP bounds and opaque constructor entries" {
  assert_eq(installed_standard_create_http_limits(), [300000, 100000, 10000, 32])
  let native = installed_standard_create_construction_profile().unwrap()
  assert_eq(native.length(), 4)
  let (write, write_input, write_output) = native[0]
  let (read, read_input, read_output) = native[1]
  assert_true(write_input is None && read_input is None)
  assert_eq(
    @execution.execution_capacity_retained_bytes(write),
    @execution.execution_capacity_retained_bytes(
      github_add_comment_request_construction_capacity().unwrap(),
    ),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(read),
    @execution.execution_capacity_execution_bytes(
      github_comment_subject_request_construction_capacity().unwrap(),
    ),
  )
  // Actual original constructor outputs, including early over-HTTP material.
  let subject = "\u{1}".repeat(256)
  let mutation = github_add_comment_request_json(subject, "\u{1}".repeat(65536))
  let subject_wire = github_comment_subject_request_json(subject)
  assert_true(@utf8.encode(mutation).length() > 300000)
  assert_true(@source.parse_json(mutation, write_output) is Ok(_))
  assert_true(@source.parse_json(subject_wire, read_output) is Ok(_))
  for index in [2, 3] {
    let (_, input, output) = native[index]
    assert_true(
      input
      is Some({ max_input_bytes: 100000, max_nodes: 10000, max_depth: 32, }),
    )
    assert_true(output.max_input_bytes > 6 * 100000)
    assert_eq(output.max_nodes, 8)
    assert_eq(output.max_depth, 3)
  }
}

///|
// Actual native profile crosses the SAME typed Core constructor adapter.
// This is neither Node bridge ABI nor a complete Plan/physical/Host recipe.
test "standard CREATE native JSON profile funds indexed input and literal returned String separately" {
  let original = installed_standard_create_construction_profile()
  let native = original.unwrap()
  let combined = @client_host.installed_standard_create_constructor_capacities(
    original,
  ).unwrap()
  assert_eq(combined.length(), 4)
  for index in 0..<4 {
    assert_true(
      @execution.execution_capacity_retained_bytes(combined[index]) >
      @execution.execution_capacity_retained_bytes(native[index].0),
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(combined[index]) >
      @execution.execution_capacity_execution_bytes(native[index].0),
    )
  }
  // Both reply roles may share immutable quantities but remain separate role
  // entries. The original profile is never changed into issued capacity.
  assert_eq(
    @execution.execution_capacity_retained_bytes(combined[2]),
    @execution.execution_capacity_retained_bytes(combined[3]),
  )
  assert_eq(native[0].2.max_nodes, 2)
  assert_true(
    @client_host.installed_standard_create_constructor_capacities(None)
    is Err(Unsupported),
  )
  assert_true(
    @client_host.installed_standard_create_constructor_capacities(Some([]))
    is Err(Unsupported),
  )
}

///|
test "standard CREATE response geometry admits original success and nested refusal exports unchanged" {
  let profile = installed_standard_create_construction_profile().unwrap()
  let limits = profile[2].2
  let body = b"{\"data\":{\"addComment\":{\"commentEdge\":{\"node\":{\"id\":\"comment\",\"databaseId\":3}},\"subject\":{\"__typename\":\"Issue\",\"id\":\"issue\"}}}}"
  let success = github_comment_outcome_json(
    200,
    [],
    [],
    body,
    100000,
    10000,
    32,
    "issue",
  )
  assert_eq(
    @json.parse(success),
    ({ "outcome": "Created", "id": 3, "nodeId": "comment" } : Json),
  )
  assert_true(@source.parse_json(success, limits) is Ok(_))
  // Use the ORIGINAL nominal refusal projection, including nested Row output.
  let refused : Json = {
    "refused": graphql_issue_name(Row(MissingRequiredField("original"))),
  }
  assert_true(@source.parse_json(refused.stringify(), profile[3].2) is Ok(_))
  assert_eq(
    @json.parse(github_add_comment_request_json("", "original")),
    ({ "refused": "InvalidSubjectId" } : Json),
  )
}
