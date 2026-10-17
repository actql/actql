///|
fn write_response_request(
  operation : RecordWriteOperation,
) -> RecordBatchRequest {
  let catalog = request_catalog()
  let inputs = []
  for index in 0..<2 {
    let target = match operation {
      Create => None
      Update =>
        Some(
          request_target(
            catalog,
            "id",
            if index == 0 {
              "\"1\""
            } else {
              "\"2\""
            },
          ),
        )
      Upsert(key) =>
        Some(
          request_target(
            catalog,
            key,
            if index == 0 {
              "\"a\""
            } else {
              "\"b\""
            },
          ),
        )
    }
    inputs.push({
      body: request_body(catalog),
      target,
      trace_id: "trace-\{index}",
    })
  }
  prepare_record_batch_request(catalog, operation, inputs, request_limits()).unwrap()
}

///|
fn write_response_project(
  request : RecordBatchRequest,
  wire : String,
  status? : Int = 200,
) -> Result[RecordWriteResponse, RecordWriteResponseIssue] {
  project_record_write_success(
    request,
    status,
    @utf8.encode(wire),
    10000,
    1000,
    20,
    100,
  )
}

///|
test "write acknowledgement correlates updates by exact IDs instead of array order" {
  let request = write_response_request(Update)
  let wire = "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"2\",\"archived\":false,\"properties\":{}},{\"id\":\"1\",\"archived\":false,\"properties\":{}}]}"
  let response = write_response_project(request, wire).unwrap()
  assert_eq(record_write_response_result(response, 0).unwrap().id, "1")
  assert_eq(record_write_response_result(response, 1).unwrap().id, "2")
  assert_false(record_write_response_result(response, 0).unwrap().created)
  assert_eq(response.response_sha256, @sha.hex(@utf8.encode(wire)))
  assert_eq(
    record_batch_request_body(record_write_response_request(response)),
    record_batch_request_body(request),
  )
}

///|
test "multi-create and upsert correlate traces with exact created state" {
  for operation in [Create, Upsert("external_key")] {
    let request = write_response_request(operation)
    let status = if operation is Create { 201 } else { 200 }
    let response = write_response_project(
      request,
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"2\",\"archived\":false,\"new\":false,\"properties\":{},\"objectWriteTraceId\":\"trace-1\"},{\"id\":\"9007199254740993\",\"archived\":false,\"new\":true,\"properties\":{},\"objectWriteTraceId\":\"trace-0\"}]}",
      status~,
    ).unwrap()
    assert_eq(
      record_write_response_result(response, 0).unwrap().id,
      "9007199254740993",
    )
    assert_true(record_write_response_result(response, 0).unwrap().created)
    assert_eq(
      record_write_response_result(response, 1).unwrap().created,
      operation is Create,
    )
  }
}

///|
test "single create accepts the documented untraced acknowledgement without an order inference" {
  let catalog = request_catalog()
  let request = prepare_record_batch_request(
    catalog,
    Create,
    [{ body: request_body(catalog), target: None, trace_id: "original", }],
    request_limits(),
  ).unwrap()
  assert_true(
    write_response_project(
      request,
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"9007199254740993\",\"archived\":false,\"properties\":{}}]}",
      status=201,
    )
    is Ok(_),
  )
}

///|
test "missing duplicate foreign and contradictory correlations never become success" {
  let request = write_response_request(Update)
  for
    wire in [
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"archived\":false,\"properties\":{}}]}",
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"archived\":false,\"properties\":{}},{\"id\":\"1\",\"archived\":false,\"properties\":{}}]}",
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"foreign\",\"archived\":false,\"properties\":{}},{\"id\":\"2\",\"archived\":false,\"properties\":{}}]}",
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"objectWriteTraceId\":\"trace-1\",\"archived\":false,\"properties\":{}},{\"id\":\"2\",\"archived\":false,\"properties\":{}}]}",
    ] {
    assert_true(write_response_project(request, wire) is Err(_))
  }
  let untraced = "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"archived\":false,\"properties\":{}},{\"id\":\"2\",\"archived\":false,\"properties\":{}}]}"
  assert_true(
    write_response_project(write_response_request(Create), untraced, status=201)
    is Err(UncorrelatedResult),
  )
  assert_true(
    write_response_project(
      write_response_request(Upsert("external_key")),
      untraced,
    )
    is Err(UncorrelatedResult),
  )
}

///|
test "HTTP success pending canceled partial errors malformed and oversized remain unclassified" {
  let request = write_response_request(Update)
  for
    wire in [
      "{}", "null", "{", "{\"status\":\"PENDING\",\"results\":[]}", "{\"status\":\"CANCELED\",\"results\":[]}",
      "{\"status\":\"COMPLETE\",\"errors\":[{}],\"results\":[]}", "{\"status\":\"COMPLETE\",\"numErrors\":1,\"results\":[]}",
    ] {
    assert_true(write_response_project(request, wire) is Err(_))
  }
  for status in [201, 202, 204, 207, 400, 401, 409, 429, 500] {
    assert_true(
      write_response_project(request, "{}", status~) is Err(UnexpectedStatus),
    )
  }
  assert_true(
    project_record_write_success(request, 200, b"{}", 1, 100, 10, 2)
    is Err(BudgetExceeded),
  )
  assert_true(
    project_record_write_success(request, 200, b"{}", 100, 0, 10, 2)
    is Err(InvalidLimits),
  )
}

///|
test "upsert needs explicit created state and every success keeps actual unarchived string identity" {
  let request = write_response_request(Upsert("external_key"))
  for
    wire in [
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"archived\":false,\"properties\":{},\"objectWriteTraceId\":\"trace-0\"},{\"id\":\"2\",\"archived\":false,\"new\":false,\"properties\":{},\"objectWriteTraceId\":\"trace-1\"}]}",
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"archived\":true,\"new\":true,\"properties\":{},\"objectWriteTraceId\":\"trace-0\"},{\"id\":\"2\",\"archived\":false,\"new\":false,\"properties\":{},\"objectWriteTraceId\":\"trace-1\"}]}",
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":1,\"archived\":false,\"new\":true,\"properties\":{},\"objectWriteTraceId\":\"trace-0\"},{\"id\":\"2\",\"archived\":false,\"new\":false,\"properties\":{},\"objectWriteTraceId\":\"trace-1\"}]}",
      "{\"status\":\"COMPLETE\",\"results\":[{\"id\":\"1\",\"archived\":false,\"new\":\"true\",\"properties\":{},\"objectWriteTraceId\":\"trace-0\"},{\"id\":\"2\",\"archived\":false,\"new\":false,\"properties\":{},\"objectWriteTraceId\":\"trace-1\"}]}",
    ] {
    assert_true(write_response_project(request, wire) is Err(InvalidResponse))
  }
}
