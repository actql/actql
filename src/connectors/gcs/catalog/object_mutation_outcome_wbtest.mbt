///|
fn mutation_outcome_request(
  binding : ObjectMutationBinding,
) -> ObjectMutationRequest {
  prepare_object_metadata_patch(
    binding,
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
}

///|
fn mutation_outcome_body() -> String {
  (
    // Independent provider response, not generated from the request projection.
    #|{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"3","size":"7","contentType":"text/csv","metadata":{"new":"=é\r\n","actql-request":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","keep":"kept"}}
  )
}

///|
test "GCS mutation outcome matches exact original metadata request and new metageneration" {
  let binding = mutation_binding()
  let request = mutation_outcome_request(binding)
  let body = @utf8.encode(mutation_outcome_body())
  assert_eq(
    classify_object_mutation_response(binding, request, 200, body),
    Ok(Applied),
  )
  let wire = object_mutation_response_projection_json(
    binding, request, 200, body, 1024,
  ).unwrap()
  assert_eq(
    wire, "{\"kind\":\"typed-success-response\",\"outcome\":{\"result\":{},\"state\":\"applied\"}}",
  )
  let observed = metadata_read(mutation_outcome_body()).unwrap()
  assert_true(object_mutation_response_matches(binding, request, observed))
  assert_false(
    object_mutation_response_matches(mutation_binding(), request, observed),
  )
}

///|
test "GCS mutation outcome refuses foreign marker changed properties generation and nonadvancing metadata" {
  let binding = mutation_binding()
  let request = mutation_outcome_request(binding)
  let original = mutation_outcome_body()
  for
    body in [
      original.replace(old="sha256:dddd", new="sha256:aaaa"),
      original.replace(old="\"actql-request\"", new="\"Actql-request\""),
      original.replace(old="=é", new="=é"),
      original.replace(old="\"size\":\"7\"", new="\"size\":\"8\""),
      original.replace(old="text/csv", new="text/plain"),
      original.replace(old="9007199254740993", new="9007199254740994"),
      original.replace(
        old="\"metageneration\":\"3\"",
        new="\"metageneration\":\"2\"",
      ),
      original.replace(
        old="\"metageneration\":\"3\"",
        new="\"metageneration\":\"1\"",
      ),
    ] {
    assert_eq(
      classify_object_mutation_response(
        binding,
        request,
        200,
        @utf8.encode(body),
      ),
      Ok(Unknown),
    )
  }
  for
    body in [
      b"{}",
      b"\xff",
      b"{\"x\":1,\"x\":2}",
      @utf8.encode(
        original.replace(old="\"keep\":\"kept\"", new="\"drop\":\"old\""),
      ),
    ] {
    assert_eq(
      classify_object_mutation_response(binding, request, 200, body),
      Ok(Unknown),
    )
  }
}

///|
test "GCS mutation outcome distinguishes metadata omission and explicit empty map" {
  let binding = mutation_binding()
  let original = mutation_original()
  let keep = prepare_object_metadata_patch(
    binding,
    original,
    b"{}",
    mutation_marker(),
  ).unwrap()
  let clear = prepare_object_metadata_patch(
    binding,
    original,
    b"{\"metadata\":{}}",
    mutation_marker(),
  ).unwrap()
  let preserved =
    #|{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"3","size":"7","metadata":{"drop":"old","keep":"kept","actql-request":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}
  let cleared =
    #|{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"3","size":"7","metadata":{"actql-request":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}
  assert_eq(
    classify_object_mutation_response(
      binding,
      keep,
      200,
      @utf8.encode(preserved),
    ),
    Ok(Applied),
  )
  assert_eq(
    classify_object_mutation_response(
      binding,
      clear,
      200,
      @utf8.encode(cleared),
    ),
    Ok(Applied),
  )
  assert_eq(
    classify_object_mutation_response(
      binding,
      clear,
      200,
      @utf8.encode(preserved),
    ),
    Ok(Unknown),
  )
  assert_eq(
    classify_object_mutation_response(binding, keep, 200, @utf8.encode(cleared)),
    Ok(Unknown),
  )
}

///|
test "GCS mutation outcome confirms only original direct empty delete and conditional conflict" {
  let binding = mutation_binding(kind=DeleteObject)
  let request = prepare_object_delete(binding, mutation_original()).unwrap()
  assert_eq(
    classify_object_mutation_response(binding, request, 204, b""),
    Ok(Applied),
  )
  assert_eq(
    classify_object_mutation_response(binding, request, 204, b"{}"),
    Ok(Unknown),
  )
  assert_eq(
    classify_object_mutation_response(
      binding,
      request,
      200,
      @utf8.encode(mutation_outcome_body()),
    ),
    Ok(Unknown),
  )
  for status in [0, 200, 201, 202, 308, 400, 401, 403, 404, 429, 500, 503] {
    assert_eq(
      classify_object_mutation_response(binding, request, status, b""),
      Ok(Unknown),
    )
  }
  assert_eq(
    classify_object_mutation_response(binding, request, 412, b"{}"),
    Ok(Conflict),
  )
  assert_true(
    object_mutation_response_projection_json(binding, request, 412, b"{}", 1024)
    .unwrap()
    .contains("typed-failure-response"),
  )
  assert_true(
    object_mutation_response_projection_json(binding, request, 404, b"{}", 1024)
    .unwrap()
    .contains("provider-response"),
  )
}

///|
test "GCS mutation outcome bounds raw response and control projection before classification" {
  let binding = mutation_binding()
  let request = mutation_outcome_request(binding)
  assert_eq(
    classify_object_mutation_response(
      binding,
      request,
      412,
      Bytes::make(metadata_limits().max_bytes + 1, 32),
    ),
    Err(CapacityExceeded),
  )
  assert_eq(
    classify_object_mutation_response(mutation_binding(), request, 412, b"{}"),
    Err(ForeignBinding),
  )
  for maximum in [0, 1] {
    assert_true(
      object_mutation_response_projection_json(
        binding,
        request,
        200,
        @utf8.encode(mutation_outcome_body()),
        maximum,
      )
      is Err(CapacityExceeded),
    )
  }
  let patch = mutation_outcome_request(binding)
  assert_eq(
    classify_object_mutation_response(binding, patch, 204, b""),
    Ok(Unknown),
  )
}
