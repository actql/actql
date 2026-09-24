///|
fn collection_request_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn collection_request_test_limits() -> WriteCollectionRequestLimits {
  {
    max_path_bytes: 256,
    max_target_bytes: 100,
    max_body_bytes: 2000,
    max_nodes: 100,
    max_depth: 5,
    max_rows: 200,
  }
}

///|
fn collection_case_write_body(case_metadata : String) -> WriteBody {
  let binding = observation_test_binding()
  let metadata = (
      #|{"name":"ActQL_Test_Record__c","queryable":true,"createable":true,"updateable":true,"fields":[{"name":"External_Key__c","type":"string","nillable":false,"defaultedOnCreate":false,"createable":true,"updateable":true,"externalId":true,"unique":true
    ) +
    case_metadata +
    (
      #|},{"name":"Optional_Value__c","type":"string","nillable":true,"defaultedOnCreate":false,"createable":true,"updateable":true}]}
    )
  let observation = write_test_observation_with(@utf8.encode(metadata), binding)
  let projection = prepare_write_projection(
    observation,
    binding,
    "ActQL_Test_Record__c",
    WriteUpsertByExternalId("External_Key__c"),
    ["Optional_Value__c"],
    1,
  ).unwrap()
  prepare_write_body(
    projection,
    @utf8.encode("{\"Optional_Value__c\":\"value\"}"),
    write_body_test_limits(),
  ).unwrap()
}

///|
test "continue collection preserves row order and exact response mapping" {
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
  assert_eq(write_collection_request_method(request), "POST")
  assert_eq(
    write_collection_request_path(request),
    "/services/data/v66.0/composite/sobjects",
  )
  assert_eq(
    write_collection_request_body(request),
    "{\"allOrNone\":false,\"records\":[{\"External_Key__c\":\"one\",\"attributes\":{\"type\":\"ActQL_Test_Record__c\"}},{\"External_Key__c\":\"one\",\"attributes\":{\"type\":\"ActQL_Test_Record__c\"}}]}",
  )
  assert_eq(write_collection_request_row_count(request), 2)
  assert_eq(
    write_collection_request_row_cid(request, 0),
    Some(collection_request_test_cid("1")),
  )
  assert_eq(
    write_collection_request_row_cid(request, 1),
    Some(collection_request_test_cid("2")),
  )
  assert_true(write_collection_request_row_cid(request, 2) is None)
  let response_result = project_write_collection_response(
    @utf8.encode(
      "[{\"id\":\"a001\",\"success\":true,\"errors\":[]},{\"id\":null,\"success\":false,\"errors\":[{\"statusCode\":\"REQUIRED_FIELD_MISSING\",\"message\":\"Missing Name\",\"fields\":[\"Name\"]}]}]",
    ),
    CollectionCreate,
    write_collection_request_row_count(request),
    collection_response_limits(),
  )
  let response = match response_result {
    Ok(value) => value
    Err(InvalidLimits) => abort("unexpected invalid response limits")
    Err(BudgetExceeded) => abort("unexpected response budget exhaustion")
    Err(UnexpectedStatus) => abort("unexpected HTTP status")
    Err(InvalidResponse) => abort("unexpected invalid response")
    Err(CountMismatch) => abort("unexpected response count mismatch")
  }
  assert_eq(
    (
      write_collection_request_row_cid(request, 0),
      write_collection_result_at(response, 0),
    ),
    (Some(collection_request_test_cid("1")), Some(RowApplied("a001", true))),
  )
  assert_eq(
    (
      write_collection_request_row_cid(request, 1),
      write_collection_result_at(response, 1),
    ),
    (
      Some(collection_request_test_cid("2")),
      Some(
        RowFailed([
          {
            status_code: "REQUIRED_FIELD_MISSING",
            message: "Missing Name",
            fields: ["Name"],
          },
        ]),
      ),
    ),
  )
}

///|
test "collections choose update and external ID upsert endpoints distinctly" {
  let update = prepare_continue_write_collection(
    [
      {
        row_preview_cid: collection_request_test_cid("1"),
        body: write_request_body(WriteUpdateById),
        target: RecordId("001000000000001"),
      },
    ],
    "v66.0",
    collection_request_test_limits(),
  ).unwrap()
  assert_eq(write_collection_request_method(update), "PATCH")
  assert_eq(
    write_collection_request_path(update),
    "/services/data/v66.0/composite/sobjects",
  )
  assert_eq(
    write_collection_request_body(update),
    "{\"allOrNone\":false,\"records\":[{\"Id\":\"001000000000001\",\"Optional_Value__c\":\"value\",\"attributes\":{\"type\":\"ActQL_Test_Record__c\"}}]}",
  )
  let upsert = prepare_continue_write_collection(
    [
      {
        row_preview_cid: collection_request_test_cid("2"),
        body: write_request_body(WriteUpsertByExternalId("External_Key__c")),
        target: ExternalText("e\u{301}"),
      },
    ],
    "v66.0",
    collection_request_test_limits(),
  ).unwrap()
  assert_eq(write_collection_request_method(upsert), "PATCH")
  assert_eq(
    write_collection_request_path(upsert),
    "/services/data/v66.0/composite/sobjects/ActQL_Test_Record__c/External_Key__c",
  )
  assert_eq(
    write_collection_request_body(upsert),
    "{\"allOrNone\":false,\"records\":[{\"External_Key__c\":\"é\",\"Optional_Value__c\":\"value\",\"attributes\":{\"type\":\"ActQL_Test_Record__c\"}}]}",
  )
}

///|
test "collection preparation rejects mixed, duplicate, and over-budget rows" {
  let create = write_request_body(WriteCreate)
  let update = write_request_body(WriteUpdateById)
  let first : WriteCollectionItem = {
    row_preview_cid: collection_request_test_cid("1"),
    body: create,
    target: NoWriteTarget,
  }
  assert_true(
    prepare_continue_write_collection(
      [],
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(InvalidRows),
  )
  assert_true(
    prepare_continue_write_collection(
      [first, first],
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(DuplicateRow),
  )
  assert_true(
    prepare_continue_write_collection(
      [
        first,
        {
          row_preview_cid: collection_request_test_cid("2"),
          body: update,
          target: RecordId("001000000000001"),
        },
      ],
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(MixedProjection),
  )
  assert_true(
    prepare_continue_write_collection([first], "v66.0", {
      ..collection_request_test_limits(),
      max_rows: 0,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_continue_write_collection(
      [first, { ..first, row_preview_cid: collection_request_test_cid("2"), }],
      "v66.0",
      { ..collection_request_test_limits(), max_rows: 1, },
    )
    is Err(InvalidRows),
  )
  assert_true(
    prepare_continue_write_collection([first], "v66.0", {
      ..collection_request_test_limits(),
      max_body_bytes: 80,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_continue_write_collection([first], "v66.0", {
      ..collection_request_test_limits(),
      max_path_bytes: 20,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_continue_write_collection(
      [first],
      "v41.0",
      collection_request_test_limits(),
    )
    is Err(InvalidVersion),
  )
  let upsert = write_request_body(WriteUpsertByExternalId("External_Key__c"))
  assert_true(
    prepare_continue_write_collection(
      [
        {
          row_preview_cid: collection_request_test_cid("2"),
          body: upsert,
          target: ExternalText("one"),
        },
      ],
      "v45.0",
      collection_request_test_limits(),
    )
    is Err(InvalidVersion),
  )
  assert_true(
    prepare_continue_write_collection(
      [
        {
          row_preview_cid: collection_request_test_cid("2"),
          body: upsert,
          target: ExternalText("e\u{301}"),
        },
        {
          row_preview_cid: collection_request_test_cid("3"),
          body: upsert,
          target: ExternalText("é"),
        },
      ],
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(DuplicateTarget),
  )
}

///|
test "collection rejects the same RecordId spelled with 15 or 18 characters" {
  let update = write_request_body(WriteUpdateById)
  assert_true(
    prepare_continue_write_collection(
      [
        {
          row_preview_cid: collection_request_test_cid("1"),
          body: update,
          target: RecordId("001000000000001"),
        },
        {
          row_preview_cid: collection_request_test_cid("2"),
          body: update,
          target: RecordId("001000000000001AAA"),
        },
      ],
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(DuplicateTarget),
  )
  assert_true(
    prepare_continue_write_collection(
      [
        {
          row_preview_cid: collection_request_test_cid("1"),
          body: update,
          target: RecordId("00100000000000A"),
        },
        {
          row_preview_cid: collection_request_test_cid("2"),
          body: update,
          target: RecordId("00100000000000a"),
        },
      ],
      "v66.0",
      collection_request_test_limits(),
    )
    is Ok(_),
  )
  assert_true(
    prepare_continue_write_collection(
      [
        {
          row_preview_cid: collection_request_test_cid("1"),
          body: update,
          target: RecordId("001000000000001AAB"),
        },
      ],
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(InvalidTarget),
  )
}

///|
test "collection uses confirmed external-ID case matching" {
  let insensitive = collection_case_write_body(",\"caseSensitive\":false")
  let sensitive = collection_case_write_body(",\"caseSensitive\":true")
  let unconfirmed = collection_case_write_body("")
  let rows = fn(body : WriteBody) -> Array[WriteCollectionItem] {
    [
      {
        row_preview_cid: collection_request_test_cid("1"),
        body,
        target: ExternalText("ABC123"),
      },
      {
        row_preview_cid: collection_request_test_cid("2"),
        body,
        target: ExternalText("abc123"),
      },
    ]
  }
  assert_true(
    prepare_continue_write_collection(
      rows(insensitive),
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(DuplicateTarget),
  )
  assert_true(
    prepare_continue_write_collection(
      rows(sensitive),
      "v66.0",
      collection_request_test_limits(),
    )
    is Ok(_),
  )
  assert_true(
    prepare_continue_write_collection(
      rows(unconfirmed),
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(InvalidTarget),
  )
  assert_true(
    prepare_continue_write_collection(
      [
        {
          row_preview_cid: collection_request_test_cid("1"),
          body: insensitive,
          target: ExternalText("É"),
        },
      ],
      "v66.0",
      collection_request_test_limits(),
    )
    is Err(InvalidTarget),
  )
}
