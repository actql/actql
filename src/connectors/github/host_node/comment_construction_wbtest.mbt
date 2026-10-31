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
  assert_eq(@json.parse(exported)["body"], original.to_json())
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
  assert_eq(@json.parse(exported)["body"], original.to_json())
  assert_eq(
    github_add_comment_request_json(subject, body + "x"),
    "{\"refused\":\"InvalidBody\"}",
  )
  assert_eq(
    github_add_comment_request_json("x".repeat(257), "original"),
    "{\"refused\":\"InvalidSubjectId\"}",
  )
  assert_eq(github_add_comment_request_json(subject, ""), "{\"refused\":\"InvalidBody\"}")
}

///|
test "GitHub subject-check inventory is separate and prices the same original export" {
  let subject = "\u{1}".repeat(256)
  let original = @catalog.comment_subject_request(subject).unwrap()
  let exported = github_comment_subject_request_json(subject)
  let (inner, outer) = github_comment_request_wire_bounds(true)
  assert_eq(original.length().to_int64(), inner)
  assert_eq(exported.length().to_int64(), outer)
  assert_eq(@json.parse(exported)["body"], original.to_json())
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
