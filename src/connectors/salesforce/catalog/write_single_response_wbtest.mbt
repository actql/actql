///|
test "single REST create and upsert require exact success evidence" {
  let created = @utf8.encode("{\"id\":\"a001\",\"success\":true,\"errors\":[]}")
  let create = project_write_single_success(
    201,
    created,
    SingleCreate,
    collection_response_limits(),
  ).unwrap()
  assert_eq(write_single_result(create), RowApplied("a001", true))
  assert_eq(write_single_response_sha256(create), @sha.hex(created))
  let upsert_create = @utf8.encode(
    "{\"id\":\"a002\",\"success\":true,\"created\":true,\"errors\":[]}",
  )
  assert_eq(
    write_single_result(
      project_write_single_success(
        201,
        upsert_create,
        SingleUpsert,
        collection_response_limits(),
      ).unwrap(),
    ),
    RowApplied("a002", true),
  )
  let upsert_update = @utf8.encode(
    "{\"id\":\"a002\",\"success\":true,\"created\":false,\"errors\":[]}",
  )
  assert_eq(
    write_single_result(
      project_write_single_success(
        200,
        upsert_update,
        SingleUpsert,
        collection_response_limits(),
      ).unwrap(),
    ),
    RowApplied("a002", false),
  )
  assert_true(
    project_write_single_success(
      201,
      upsert_update,
      SingleUpsert,
      collection_response_limits(),
    )
    is Err(InvalidResponse),
  )
}

///|
test "single REST update requires empty confirmed 204 response" {
  let empty = @utf8.encode("")
  let result = project_write_single_success(
    204,
    empty,
    SingleUpdateById("a003"),
    collection_response_limits(),
  ).unwrap()
  assert_eq(write_single_result(result), RowApplied("a003", false))
  assert_true(
    project_write_single_success(
      204,
      @utf8.encode("{}"),
      SingleUpdateById("a003"),
      collection_response_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    project_write_single_success(
      204,
      empty,
      SingleUpdateById(""),
      collection_response_limits(),
    )
    is Err(UnexpectedStatus),
  )
}

///|
test "single REST does not infer success from status or malformed body" {
  let created = @utf8.encode("{\"id\":\"a001\",\"success\":true,\"errors\":[]}")
  assert_true(
    project_write_single_success(
      200,
      created,
      SingleCreate,
      collection_response_limits(),
    )
    is Err(UnexpectedStatus),
  )
  assert_true(
    project_write_single_success(
      500,
      created,
      SingleCreate,
      collection_response_limits(),
    )
    is Err(UnexpectedStatus),
  )
  assert_true(
    project_write_single_success(
      201,
      @utf8.encode(
        "{\"id\":null,\"success\":false,\"errors\":[{\"statusCode\":\"INVALID\",\"message\":\"no\",\"fields\":[]}]}",
      ),
      SingleCreate,
      collection_response_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    project_write_single_success(201, created, SingleCreate, {
      ..collection_response_limits(),
      max_bytes: 10,
    })
    is Err(BudgetExceeded),
  )
}
