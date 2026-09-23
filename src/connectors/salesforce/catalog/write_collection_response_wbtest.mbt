///|
fn collection_response_limits() -> WriteCollectionResponseLimits {
  { max_bytes: 2000, max_nodes: 100, max_depth: 5, max_rows: 200, }
}

///|
test "collection response preserves positional partial success and failures" {
  let bytes = @utf8.encode(
    (
      #|[{"id":"a001","success":true,"errors":[]},{"id":null,"success":false,"errors":[{"statusCode":"REQUIRED_FIELD_MISSING","message":"Missing Name","fields":["Name"]}]},{"id":"a003","success":true,"errors":[]}]
    ),
  )
  let result = project_write_collection_response(
    bytes,
    CollectionCreate,
    3,
    collection_response_limits(),
  ).unwrap()
  assert_eq(write_collection_result_count(result), 3)
  assert_eq(
    write_collection_result_at(result, 0),
    Some(RowApplied("a001", true)),
  )
  assert_eq(
    write_collection_result_at(result, 1),
    Some(
      RowFailed([
        {
          status_code: "REQUIRED_FIELD_MISSING",
          message: "Missing Name",
          fields: ["Name"],
        },
      ]),
    ),
  )
  assert_eq(
    write_collection_result_at(result, 2),
    Some(RowApplied("a003", true)),
  )
  assert_true(write_collection_result_at(result, 3) is None)
  assert_eq(write_collection_response_sha256(result), @sha.hex(bytes))
}

///|
test "collection upsert requires created evidence for each applied row" {
  let rows = @utf8.encode(
    (
      #|[{"id":"a001","success":true,"created":true,"errors":[]},{"id":"a002","success":true,"created":false,"errors":[]}]
    ),
  )
  let result = project_write_collection_response(
    rows,
    CollectionUpsert,
    2,
    collection_response_limits(),
  ).unwrap()
  assert_eq(
    write_collection_result_at(result, 0),
    Some(RowApplied("a001", true)),
  )
  assert_eq(
    write_collection_result_at(result, 1),
    Some(RowApplied("a002", false)),
  )
  assert_true(
    project_write_collection_response(
      @utf8.encode("[{\"id\":\"a001\",\"success\":true,\"errors\":[]}]"),
      CollectionUpsert,
      1,
      collection_response_limits(),
    )
    is Err(InvalidResponse),
  )
}

///|
test "collection update cannot claim a created row" {
  let update = @utf8.encode(
    "[{\"id\":\"a001\",\"success\":true,\"errors\":[]}]",
  )
  let result = project_write_collection_response(
    update,
    CollectionUpdate,
    1,
    collection_response_limits(),
  ).unwrap()
  assert_eq(
    write_collection_result_at(result, 0),
    Some(RowApplied("a001", false)),
  )
  assert_true(
    project_write_collection_response(
      @utf8.encode(
        "[{\"id\":\"a001\",\"success\":true,\"created\":true,\"errors\":[]}]",
      ),
      CollectionUpdate,
      1,
      collection_response_limits(),
    )
    is Err(InvalidResponse),
  )
}

///|
test "collection response never treats incomplete evidence as row success" {
  let success = @utf8.encode(
    "[{\"id\":\"a001\",\"success\":true,\"errors\":[]}]",
  )
  assert_true(
    project_write_collection_response(
      success,
      CollectionCreate,
      2,
      collection_response_limits(),
    )
    is Err(CountMismatch),
  )
  for
    text in [
      "[{\"id\":\"a001\",\"success\":true,\"errors\":[{}]}]", "[{\"id\":null,\"success\":false,\"errors\":[]}]",
      "[{\"id\":\"a001\",\"success\":false,\"errors\":[{}]}]", "[{\"id\":null,\"success\":true,\"errors\":[]}]",
      "[{\"id\":\"a001\",\"success\":true,\"errors\":[]}] trailing",
    ] {
    assert_true(
      project_write_collection_response(
        @utf8.encode(text),
        CollectionCreate,
        1,
        collection_response_limits(),
      )
      is Err(InvalidResponse),
    )
  }
  assert_true(
    project_write_collection_response(success, CollectionCreate, 1, {
      ..collection_response_limits(),
      max_bytes: 10,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_write_collection_response(success, CollectionCreate, 1, {
      ..collection_response_limits(),
      max_nodes: 2,
    })
    is Err(BudgetExceeded),
  )
}
