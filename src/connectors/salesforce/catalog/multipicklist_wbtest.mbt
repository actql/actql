///|
/// Original synthetic Describe, admitted through the existing catalog sync.
fn choices_describe() -> String {
  (
    #|{"name":"Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"Id","type":"id","nillable":false},{"name":"Name","type":"string","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true},{"name":"Choices__c","type":"multipicklist","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true,"externalId":true,"unique":true}]}
  )
}

///|
fn choices_read() -> ReadProjection {
  let (observation, binding) = declared_observation(choices_describe())
  prepare_read_projection(
    observation,
    binding,
    "Record__c",
    ["Choices__c"],
    256,
  ).unwrap()
}

///|
fn choices_write() -> WriteProjection {
  let (observation, binding) = declared_observation(choices_describe())
  prepare_write_projection(
    observation,
    binding,
    "Record__c",
    WriteUpdateById,
    ["Choices__c"],
    1,
  ).unwrap()
}

///|
fn choices_page(
  plan : ReadProjection,
  value : String,
  limits? : QueryPageLimits = query_test_limits(),
) -> Result[QueryPage, QueryPageIssue] {
  project_query_page(
    @utf8.encode(
      "{\"totalSize\":1,\"done\":true,\"records\":[{\"Choices__c\":" +
      value +
      "}]}",
    ),
    plan,
    "v62.0",
    limits,
  )
}

///|
fn choices_wire(page : QueryPage) -> String {
  let output = @encode.writer(4096, 1000, 10) catch {
    _ => abort("test writer")
  }
  @admitted.emit_checked_wire_value(
    query_page_cell(page, 0, 0).unwrap(),
    output,
  ) catch {
    _ => abort("test checked value")
  }
  @encode.finish(output) catch {
    _ => abort("test finish")
  }
}

///|
fn choices_body(
  plan : WriteProjection,
  value : String,
) -> Result[WriteBody, WriteBodyIssue] {
  prepare_write_body(plan, @utf8.encode("{\"Choices__c\":" + value + "}"), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 5,
  })
}

///|
test "multi-select declaration carries the original nullable array of non-null strings" {
  let declaration = declared_for(choices_describe())
  assert_eq(declaration.views[0].fields, ["Id", "Name", "Choices__c"])
  assert_true(
    declaration.catalog.contains(
      "\"Choices__c\":{\"items\":{\"nullable\":false,\"type\":\"string\"},\"nullable\":true,\"type\":\"array\"}",
    ),
  )
  assert_eq(
    declaration.writables[0].create_fields,
    Some(["Choices__c", "Name"]),
  )
  assert_eq(
    declaration.writables[0].update_fields,
    Some(["Choices__c", "Name"]),
  )
  assert_eq(declaration.exclusions.length(), 0)
}

///|
test "multi-select reads preserve original order duplicates Unicode and whitespace" {
  let plan = choices_read()
  for
    (value, expected) in [
      ("\"red;東京;red\"", "[\"red\",\"東京\",\"red\"]"),
      ("\"  red ;blue \\t\"", "[\"  red \",\"blue \\t\"]"),
      ("\"one\"", "[\"one\"]"),
      ("null", "null"),
    ] {
    assert_eq(choices_wire(choices_page(plan, value).unwrap()), expected)
  }
}

///|
test "multi-select provider non-text is a typed array refusal" {
  let plan = choices_read()
  for value in ["1", "true", "[]", "{}"] {
    let issue = choices_page(plan, value).unwrap_err()
    let refusal = query_page_value_violation(issue, plan).unwrap()
    assert_eq(refusal.expected_type, "array")
    assert_eq(refusal.field, "Choices__c")
    assert_eq(refusal.kind, "type")
  }
}

///|
test "multi-select expansion consumes the original caller node budget" {
  let plan = choices_read()
  let body = "\"" + "x;".repeat(200) + "last\""
  assert_true(
    choices_page(plan, body, limits={ ..query_test_limits(), max_nodes: 20, })
    is Err(BudgetExceeded),
  )
}

///|
test "approved multi-select arrays retain their value wire and exact semicolon physical body" {
  let plan = choices_write()
  let body = choices_body(plan, "[\"red\",\"東京\",\"red\"]").unwrap()
  assert_eq(write_body_json(body), "{\"Choices__c\":\"red;東京;red\"}")
  assert_eq(
    write_body_value_json(body),
    "{\"Choices__c\":[\"red\",\"東京\",\"red\"]}",
  )
  let nulled = choices_body(plan, "null").unwrap()
  assert_eq(write_body_json(nulled), "{\"Choices__c\":null}")
}

///|
test "multi-select writes refuse wrong item types and an unrepresentable semicolon item before request" {
  let plan = choices_write()
  for
    value in [
      "\"red\"", "[1]", "[null]", "[true]", "[[\"red\"]]", "[\"red;blue\"]",
    ] {
    assert_true(
      choices_body(plan, value) is Err(InvalidValue("Choices__c")),
      msg=value,
    )
  }
}

///|
test "multi-select original target observation preview and recovered request retain the same arrays" {
  let plan = choices_write()
  let request = prepare_single_write_request(
    choices_body(plan, "[\"next\",\"次\"]").unwrap(),
    "v62.0",
    RecordId("a01000000000001"),
    write_request_test_limits(),
  ).unwrap()
  let before = @utf8.encode(
    "{\"Id\":\"a01000000000001AAA\",\"Choices__c\":\"old;元\"}",
  )
  let observed = prepare_target_observation(
    request,
    200,
    before,
    target_observation_test_limits(),
  ).unwrap()
  assert_eq(target_observation_response_sha256(observed), @sha.hex(before))
  assert_eq(
    target_observation_before_value_wire(observed),
    "{\"Choices__c\":[\"old\",\"元\"]}",
  )
  let preview = prepare_observed_target_preview_row(request, observed, 1024).unwrap()
  assert_eq(
    target_preview_row_after_wire(preview),
    "{\"Choices__c\":[\"next\",\"次\"]}",
  )
  let recovered = recover_single_write_request(
    plan,
    single_write_request_value(request),
    "\"a01000000000001\"",
    "v62.0",
    { max_bytes: 4096, max_nodes: 100, max_depth: 5, },
    write_request_test_limits(),
  ).unwrap()
  assert_eq(
    single_write_request_body(recovered),
    "{\"Choices__c\":\"next;次\"}",
  )
  assert_true(physical_equal(recovered.projection, plan))
}

///|
test "multi-select admission does not open an external target key or hide native type drift" {
  let (observation, binding) = declared_observation(choices_describe())
  assert_true(
    prepare_write_projection(
      observation,
      binding,
      "Record__c",
      WriteUpsertByExternalId("Choices__c"),
      ["Name"],
      1,
    )
    is Err(UnsupportedWriteType("Choices__c")),
  )
  let read = choices_read()
  let write = choices_write()
  let changed = choices_describe().replace_all(
    old="multipicklist",
    new="picklist",
  )
  let (current, _) = declared_observation(changed)
  assert_true(
    recheck_read_projection(read, current) is Err(SchemaChanged("Choices__c")),
  )
  assert_true(
    recheck_write_projection(write, current) is Err(SchemaChanged("Choices__c")),
  )
}

///|
test "multi-select empty text array and representable empty elements have exact distinct projections" {
  let read = choices_read()
  let write = choices_write()
  // Independent fixed expectations of the adopted physical codec, not product output.
  for
    (provider, logical) in [
      ("\"\"", "[]"),
      ("\";\"", "[\"\",\"\"]"),
      ("\"a;\"", "[\"a\",\"\"]"),
      ("\";a\"", "[\"\",\"a\"]"),
      ("\"a;;a\"", "[\"a\",\"\",\"a\"]"),
    ] {
    assert_eq(choices_wire(choices_page(read, provider).unwrap()), logical)
    let body = choices_body(write, logical).unwrap()
    assert_eq(write_body_json(body), "{\"Choices__c\":" + provider + "}")
    assert_eq(write_body_value_json(body), "{\"Choices__c\":" + logical + "}")
  }
  assert_true(choices_body(write, "[\"\"]") is Err(InvalidValue("Choices__c")))
}

///|
test "a cleared multi-select does not convert an actual observed null into an empty array" {
  let request = prepare_single_write_request(
    choices_body(choices_write(), "[]").unwrap(),
    "v62.0",
    RecordId("a01000000000001"),
    write_request_test_limits(),
  ).unwrap()
  assert_eq(single_write_request_body(request), "{\"Choices__c\":\"\"}")
  let empty = prepare_target_observation(
    request,
    200,
    @utf8.encode("{\"Id\":\"a01000000000001AAA\",\"Choices__c\":\"\"}"),
    target_observation_test_limits(),
  ).unwrap()
  let nulled = prepare_target_observation(
    request,
    200,
    @utf8.encode("{\"Id\":\"a01000000000001AAA\",\"Choices__c\":null}"),
    target_observation_test_limits(),
  ).unwrap()
  assert_eq(target_observation_before_value_wire(empty), "{\"Choices__c\":[]}")
  assert_eq(
    target_observation_before_value_wire(nulled),
    "{\"Choices__c\":null}",
  )
  assert_true(
    target_observation_version_cid(empty) !=
    target_observation_version_cid(nulled),
  )
}

///|
test "multi-select expanded Array limits cover each row and target observation" {
  let plan = choices_read()
  let small : QueryPageLimits = {
    max_bytes: 4096,
    max_nodes: 8,
    max_depth: 5,
    max_rows: 2,
    max_locator_units: 128,
  }
  let records = @utf8.encode(
    "{\"totalSize\":2,\"done\":true,\"records\":[{\"Choices__c\":\"a;b;c;d\"},{\"Choices__c\":\"e;f;g;h\"}]}",
  )
  assert_true(
    project_query_page(records, plan, "v62.0", small) is Err(BudgetExceeded),
  )
  let exact = @utf8.encode("{\"totalSize\":2,\"done\":true,\"records\":[{\"Choices__c\":\"a;b;c\"},{\"Choices__c\":\"d;e;f\"}]}")
  assert_true(project_query_page(exact, plan, "v62.0", small) is Ok(_))
  let request = prepare_single_write_request(
    choices_body(choices_write(), "[\"new\"]").unwrap(),
    "v62.0",
    RecordId("a01000000000001"),
    write_request_test_limits(),
  ).unwrap()
  let bytes = @utf8.encode(
    "{\"Id\":\"a01000000000001AAA\",\"Choices__c\":\"a;b;c;d;e;f;g;h;i\"}",
  )
  assert_true(
    prepare_target_observation(request, 200, bytes, {
      ..target_observation_test_limits(),
      max_nodes: 6,
    })
    is Err(CapacityExceeded),
  )
}

///|
test "multi-select approved values do not escape the original body byte node or depth bounds" {
  let plan = choices_write()
  let bytes = @utf8.encode("{\"Choices__c\":[\"東京\",\"a\"]}")
  let cases : Array[WriteBodyLimits] = [
    { max_bytes: 4, max_nodes: 100, max_depth: 5, },
    { max_bytes: 4096, max_nodes: 3, max_depth: 5, },
    { max_bytes: 4096, max_nodes: 100, max_depth: 1, },
  ]
  for limits in cases {
    assert_true(prepare_write_body(plan, bytes, limits) is Err(BudgetExceeded))
  }
}
