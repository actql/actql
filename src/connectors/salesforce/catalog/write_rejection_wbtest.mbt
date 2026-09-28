///|
fn rejection_test_requests() -> (
  SingleWriteRequest,
  SingleWriteRequest,
  SingleWriteRequest,
) {
  let create = prepare_single_write_request(
    write_request_body(WriteCreate),
    "v66.0",
    NoWriteTarget,
    write_request_test_limits(),
  ).unwrap()
  let update = prepare_single_write_request(
    write_request_body(WriteUpdateById),
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
  let upsert = prepare_single_write_request(
    write_request_body(WriteUpsertByExternalId("External_Key__c")),
    "v66.0",
    ExternalText("key-1"),
    write_request_test_limits(),
  ).unwrap()
  (create, update, upsert)
}

///|
fn rejected(
  status : Int,
  body : String,
  request : SingleWriteRequest,
) -> Result[WriteSingleResponse, WriteSingleResponseIssue] {
  project_write_single_rejection(
    status,
    @utf8.encode(body),
    request,
    collection_response_limits(),
  )
}

///|
fn rejection_wire(response : WriteSingleResponse) -> String {
  project_single_effect_outcome(
    response,
    collection_request_test_cid("9"),
    4096,
    128,
    8,
  ).unwrap().outcome_wire
}

///|
test "documented single-record rejections are definite failures" {
  let (create, update, upsert) = rejection_test_requests()
  // 400: a pre-save error with a declared field; the message is withheld.
  let invalid = rejected(
    400, "[{\"message\":\"secret value 42\",\"errorCode\":\"FIELD_CUSTOM_VALIDATION_EXCEPTION\",\"fields\":[\"External_Key__c\"]}]",
    create,
  ).unwrap()
  assert_eq(
    write_single_rejection(invalid),
    Some({ code: "SalesforceWriteRejected", http_status: 400, }),
  )
  let wire = rejection_wire(invalid)
  assert_eq(
    wire, "{\"error\":{\"code\":\"SalesforceWriteRejected\",\"details\":{\"errors\":[{\"error_code\":\"FIELD_CUSTOM_VALIDATION_EXCEPTION\",\"fields\":[\"External_Key__c\"]}],\"http_status\":400},\"message\":\"Salesforce rejected the write before saving it\"},\"state\":\"failed\"}",
  )
  assert_false(wire.contains("secret value"))
  // 401, 403 (refused, including the request limit), 404 and 428.
  for
    case in [
      (401, "INVALID_SESSION_ID"),
      (403, "REQUEST_LIMIT_EXCEEDED"),
      (403, "INSUFFICIENT_ACCESS_OR_READONLY"),
      (404, "NOT_FOUND"),
      (428, "PRECONDITION_REQUIRED"),
    ] {
    let (status, code) = case
    let response = rejected(
      status,
      "[{\"message\":\"m\",\"errorCode\":\"" + code + "\"}]",
      update,
    ).unwrap()
    assert_eq(
      write_single_result(response),
      RowFailed([{ status_code: code, message: "", fields: [], }]),
    )
  }
  // One error object alone is the same evidence.
  assert_true(
    rejected(404, "{\"message\":\"m\",\"errorCode\":\"NOT_FOUND\"}", upsert)
    is Ok(_),
  )
}

///|
test "declared fields only are published from a rejection" {
  let (create, _, _) = rejection_test_requests()
  let response = rejected(
    400, "[{\"message\":\"m\",\"errorCode\":\"INVALID_FIELD\",\"fields\":[\"External_Key__c\",\"Secret__c\",\"<script>\",\"External_Key__c\"]}]",
    create,
  ).unwrap()
  assert_eq(
    write_single_result(response),
    RowFailed([
      {
        status_code: "INVALID_FIELD",
        message: "",
        fields: ["External_Key__c"],
      },
    ]),
  )
}

///|
test "responses without documented rejection evidence stay unknown" {
  let (create, update, upsert) = rejection_test_requests()
  let error = "[{\"message\":\"m\",\"errorCode\":\"INVALID_FIELD\"}]"
  // Statuses that report no rejection before the save: provider failures,
  // timeouts, conflicts, gateway errors, and a precondition this request
  // never sent.
  for status in [500, 502, 503, 409, 410, 412, 420, 429, 405, 415, 302] {
    assert_true(rejected(status, error, create) is Err(UnexpectedStatus))
  }
  // A 300 is never evidence here: the transport refuses 3xx before reading
  // the body.
  for request in [create, update, upsert] {
    assert_true(
      rejected(300, "[\"/a\",\"/b\"]", request) is Err(UnexpectedStatus),
    )
  }
  // Error codes that report provider uncertainty.
  for
    code in [
      "SERVER_UNAVAILABLE", "UNKNOWN_EXCEPTION", "QUERY_TIMEOUT", "REQUEST_RUNNING_TOO_LONG",
    ] {
    assert_true(
      rejected(
        400,
        "[{\"message\":\"m\",\"errorCode\":\"INVALID_FIELD\"},{\"message\":\"m\",\"errorCode\":\"" +
        code +
        "\"}]",
        update,
      )
      is Err(UnexpectedStatus),
    )
  }
  // Malformed or unrecognizable bodies: a proxy page, an empty body, an
  // empty list, a missing or non-enumeration code, a missing message, and
  // fields that are not names.
  for
    body in [
      "<html>Bad Request</html>", "", "[]", "[{\"message\":\"m\"}]", "[{\"message\":\"m\",\"errorCode\":\"invalid field\"}]",
      "[{\"message\":\"m\",\"errorCode\":\"\"}]", "[{\"errorCode\":\"INVALID_FIELD\"}]",
      "[{\"message\":\"m\",\"errorCode\":\"INVALID_FIELD\",\"fields\":\"Name\"}]",
      "[{\"message\":\"m\",\"errorCode\":\"INVALID_FIELD\",\"fields\":[1]}]", "[1]",
    ] {
    assert_true(rejected(400, body, create) is Err(InvalidResponse))
  }
  // A response over the bound is not read as evidence.
  assert_true(
    project_write_single_rejection(400, @utf8.encode(error), create, {
      max_bytes: 4,
      max_nodes: 100,
      max_depth: 10,
      max_rows: 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "a request-level Collections rejection fails every row" {
  let create = write_request_body(WriteCreate)
  let rows : Array[WriteCollectionItem] = [
    {
      row_preview_cid: collection_request_test_cid("1"),
      body: create,
      target: NoWriteTarget,
    },
    {
      row_preview_cid: collection_request_test_cid("2"),
      body: create,
      target: NoWriteTarget,
    },
  ]
  let request = prepare_continue_write_collection(
    rows,
    "v66.0",
    collection_request_test_limits(),
  ).unwrap()
  let limits = collection_response_limits()
  let rejected = project_write_collection_response_for_request(
    400,
    @utf8.encode(
      "[{\"message\":\"m\",\"errorCode\":\"JSON_PARSER_ERROR\",\"fields\":[\"Secret__c\"]}]",
    ),
    request,
    limits,
  ).unwrap()
  assert_eq(write_collection_result_count(rejected), 2)
  for index in 0..<2 {
    let outcome = project_collection_effect_outcome_at(
      rejected, index, 4096, 128, 8,
    ).unwrap()
    assert_eq(
      outcome.outcome_wire,
      "{\"error\":{\"code\":\"SalesforceWriteRejected\",\"details\":{\"errors\":[{\"error_code\":\"JSON_PARSER_ERROR\",\"fields\":[]}],\"http_status\":400},\"message\":\"Salesforce rejected the write before saving it\"},\"state\":\"failed\"}",
    )
    assert_eq(
      outcome.row_preview_cid,
      collection_request_test_cid((index + 1).to_string()),
    )
  }
  // Anything else keeps every row unknown.
  for status in [500, 503, 429, 201, 300] {
    assert_true(
      project_write_collection_response_for_request(
        status,
        @utf8.encode("[{\"message\":\"m\",\"errorCode\":\"INVALID_FIELD\"}]"),
        request,
        limits,
      )
      is Err(_),
    )
  }
}
