///|
fn upload_answer(
  marker? : String = mutation_marker(),
  generation? : String = "9007199254740994",
  meta? : String = "1",
  checksum? : String = "crxyRA==",
  encoding? : String = "",
) -> Bytes {
  @utf8.encode(
    "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.bin\",\"generation\":\"" +
    generation +
    "\",\"metageneration\":\"" +
    meta +
    "\",\"size\":\"4\",\"contentType\":\"application/octet-stream\",\"crc32c\":\"" +
    checksum +
    "\",\"metadata\":{\"actql-request\":\"" +
    marker +
    "\"}" +
    encoding +
    "}",
  )
}

///|
test "GCS original direct upload outcome requires exact marker bytes and replacement version" {
  let binding = upload_request_binding()
  let request = upload_request(
    binding,
    upload_existing(binding),
    overwrite=Some(true),
  ).unwrap()
  assert_eq(
    classify_object_upload_response(binding, request, 200, upload_answer()),
    Ok(Applied),
  )
  for
    body in [
      upload_answer(marker="foreign-copied-marker"),
      upload_answer(generation="9007199254740993"),
      upload_answer(meta="2"),
      upload_answer(checksum="AAAAAA=="),
      upload_answer(encoding=",\"contentEncoding\":\"gzip\""),
      b"{\"bucket\":\"bucket\",\"name\":\"in/é%2F.bin\",\"generation\":\"9007199254740994\",\"metageneration\":\"1\",\"size\":\"4\",\"contentType\":\"application/octet-stream\",\"crc32c\":\"crxyRA==\"}",
    ] {
    assert_eq(
      classify_object_upload_response(binding, request, 200, body),
      Ok(Unknown),
    )
  }
  let expected = "{\"kind\":\"typed-success-response\",\"outcome\":{\"result\":{},\"state\":\"applied\"}}"
  assert_eq(
    object_upload_response_projection_json(
      binding,
      request,
      200,
      upload_answer(),
      expected.length(),
    ),
    Ok(expected),
  )
  assert_eq(
    object_upload_response_projection_json(
      binding,
      request,
      200,
      upload_answer(),
      expected.length() - 1,
    ),
    Err(CapacityExceeded),
  )
}

///|
test "GCS direct conditional refusal is conflict while lost ambiguous and later errors stay unclassified" {
  let binding = upload_request_binding()
  let request = upload_request(binding, upload_absent(binding)).unwrap()
  assert_eq(
    classify_object_upload_response(binding, request, 412, b"{}"),
    Ok(Conflict),
  )
  assert_eq(
    object_upload_response_projection_json(binding, request, 412, b"{}", 1024),
    Ok(
      "{\"kind\":\"typed-failure-response\",\"outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"The original GCS upload precondition failed\"},\"state\":\"failed\"}}",
    ),
  )
  for status in [0, 201, 308, 400, 401, 403, 404, 429, 500, 503] {
    assert_eq(
      classify_object_upload_response(binding, request, status, upload_answer()),
      Ok(Unknown),
    )
  }
  assert_eq(
    object_upload_response_projection_json(binding, request, 503, b"{}", 1024),
    Ok("{\"kind\":\"provider-response\"}"),
  )
}

///|
test "GCS malformed outcome retains unknown and bounded parsing rejects foreign or excess input" {
  let binding = upload_request_binding()
  let request = upload_request(binding, upload_absent(binding)).unwrap()
  for body in [b"{}", b"\xff", b"{\"generation\":\"1\",\"generation\":\"2\"}"] {
    assert_eq(
      classify_object_upload_response(binding, request, 200, body),
      Ok(Unknown),
    )
  }
  assert_eq(
    classify_object_upload_response(
      upload_request_binding(),
      request,
      200,
      upload_answer(),
    ),
    Err(ForeignBinding),
  )
  assert_eq(
    classify_object_upload_response(
      binding,
      request,
      200,
      Bytes::make(metadata_limits().max_bytes + 1, 32),
    ),
    Err(CapacityExceeded),
  )
  assert_eq(
    object_upload_response_projection_json(
      binding,
      request,
      200,
      upload_answer(),
      0,
    ),
    Err(CapacityExceeded),
  )
}

///|
test "GCS upload replacement accepts a distinct lower generation with original response bytes" {
  let binding = upload_request_binding()
  let request = upload_request(
    binding,
    upload_existing(binding),
    overwrite=Some(true),
  ).unwrap()
  // Exact independent version identities straddle the JS safe-integer bound;
  // their ordering cannot establish whether the replacement is a new version.
  let response = upload_answer(generation="9007199254740992")
  assert_eq(
    classify_object_upload_response(binding, request, 200, response),
    Ok(Applied),
  )
  assert_eq(
    object_upload_response_projection_json(
      binding, request, 200, response, 1024,
    ),
    Ok(
      "{\"kind\":\"typed-success-response\",\"outcome\":{\"result\":{},\"state\":\"applied\"}}",
    ),
  )
}
