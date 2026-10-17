///|
fn mutation_answer(
  marker? : String = mutation_marker(),
  generation? : String = "9007199254740993",
  meta? : String = "3",
  size? : String = "7",
  name? : String = "in/é%2F.csv",
  content_type? : String = "text/csv",
  extra? : String = "",
) -> Bytes {
  @utf8.encode(
    "{\"bucket\":\"bucket\",\"name\":\"" +
    name +
    "\",\"generation\":\"" +
    generation +
    "\",\"metageneration\":\"" +
    meta +
    "\",\"size\":\"" +
    size +
    "\",\"contentType\":\"" +
    content_type +
    "\",\"metadata\":{\"new\":\"=é\\r\\n\",\"actql-request\":\"" +
    marker +
    "\",\"keep\":\"kept\"}" +
    extra +
    "}",
  )
}

///|
test "GCS original PATCH outcome matches exact marker generation and user fields independent of map order" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    classify_object_mutation_response(binding, request, 200, mutation_answer()),
    Ok(Applied),
  )
  let observed = admit_object_metadata(
    mutation_answer(),
    "bucket",
    "in/",
    Some("in/é%2F.csv"),
    metadata_limits(),
  ).unwrap()
  assert_true(object_mutation_response_matches(binding, request, observed))
  for
    body in [
      mutation_answer(marker="copied-from-another-request"),
      mutation_answer(generation="9007199254740994"),
      mutation_answer(meta="2"),
      mutation_answer(meta="1"),
      mutation_answer(size="8"),
      mutation_answer(name="in/é%2F.csv"),
      mutation_answer(content_type="application/json"),
      mutation_answer(extra=",\"contentEncoding\":\"gzip\""),
      mutation_answer(extra=",\"crc32c\":\"AAAAAA==\""),
      b"{\"bucket\":\"bucket\",\"name\":\"in/é%2F.csv\",\"generation\":\"9007199254740993\",\"metageneration\":\"3\",\"size\":\"7\",\"contentType\":\"text/csv\",\"metadata\":{\"keep\":\"kept\",\"new\":\"=é\\r\\n\"}}",
      b"{}",
      b"\xff",
      b"{\"generation\":\"1\",\"generation\":\"2\"}",
    ] {
    assert_eq(
      classify_object_mutation_response(binding, request, 200, body),
      Ok(Unknown),
    )
  }
  let expected = "{\"kind\":\"typed-success-response\",\"outcome\":{\"result\":{},\"state\":\"applied\"}}"
  assert_eq(
    object_mutation_response_projection_json(
      binding,
      request,
      200,
      mutation_answer(),
      expected.length(),
    ),
    Ok(expected),
  )
  assert_eq(
    object_mutation_response_projection_json(
      binding,
      request,
      200,
      mutation_answer(),
      expected.length() - 1,
    ),
    Err(CapacityExceeded),
  )
}

///|
test "GCS response matching preserves omitted metadata and distinguishes explicit empty replacement" {
  let binding = mutation_binding()
  for
    (changes, answer) in [
      (
        b"{\"content_type\":\"text/csv\"}",
        "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.csv\",\"generation\":\"9007199254740993\",\"metageneration\":\"3\",\"size\":\"7\",\"contentType\":\"text/csv\",\"metadata\":{\"keep\":\"kept\",\"drop\":\"old\",\"actql-request\":\"" +
        mutation_marker() +
        "\"}}",
      ),
      (
        b"{\"metadata\":{}}",
        "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.csv\",\"generation\":\"9007199254740993\",\"metageneration\":\"3\",\"size\":\"7\",\"metadata\":{\"actql-request\":\"" +
        mutation_marker() +
        "\"}}",
      ),
    ] {
    let request = prepare_object_metadata_patch(
      binding,
      mutation_original(),
      changes,
      mutation_marker(),
    ).unwrap()
    assert_eq(
      classify_object_mutation_response(
        binding,
        request,
        200,
        @utf8.encode(answer),
      ),
      Ok(Applied),
    )
    assert_eq(
      classify_object_mutation_response(
        binding,
        request,
        200,
        mutation_answer(),
      ),
      Ok(Unknown),
    )
  }
}

///|
test "GCS original DELETE needs its direct empty 204 and never reconciles from metadata or absence" {
  let binding = mutation_binding(kind=DeleteObject, permissions=[
    "storage.objects.delete",
  ])
  let request = prepare_object_delete(binding, mutation_original()).unwrap()
  assert_eq(
    classify_object_mutation_response(binding, request, 204, b""),
    Ok(Applied),
  )
  for (status, body) in [(204, b"{}"), (200, b""), (404, b""), (500, b"")] {
    assert_eq(
      classify_object_mutation_response(binding, request, status, body),
      Ok(Unknown),
    )
  }
  assert_false(
    object_mutation_response_matches(binding, request, mutation_original()),
  )
  assert_eq(
    classify_object_mutation_response(binding, request, 412, b"{}"),
    Ok(Conflict),
  )
  assert_eq(
    object_mutation_response_projection_json(binding, request, 412, b"{}", 1024),
    Ok(
      "{\"kind\":\"typed-failure-response\",\"outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"The original GCS object precondition failed\"},\"state\":\"failed\"}}",
    ),
  )
}

///|
test "GCS mutation response refuses foreign original binding and input output capacity excess" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    classify_object_mutation_response(
      mutation_binding(),
      request,
      200,
      mutation_answer(),
    ),
    Err(ForeignBinding),
  )
  assert_eq(
    classify_object_mutation_response(
      binding,
      request,
      200,
      Bytes::make(metadata_limits().max_bytes + 1, 32),
    ),
    Err(CapacityExceeded),
  )
  assert_eq(
    object_mutation_response_projection_json(
      binding,
      request,
      200,
      mutation_answer(),
      0,
    ),
    Err(CapacityExceeded),
  )
  for status in [0, 201, 204, 308, 400, 401, 403, 404, 429, 500, 503] {
    assert_eq(
      classify_object_mutation_response(
        binding,
        request,
        status,
        mutation_answer(),
      ),
      Ok(Unknown),
    )
  }
}
