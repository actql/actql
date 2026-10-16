///|
test "GCS target read accepts only the original full metadata representation and exact version headers" {
  let binding = upload_request_binding()
  let name = "in/é%2F.bin"
  let body = b"{\"bucket\":\"bucket\",\"name\":\"in/e\u0301%2F.bin\",\"generation\":\"9007199254740993\",\"metageneration\":\"2\",\"size\":\"7\"}"
  let original = admit_object_upload_target_observation(
    binding,
    name,
    200,
    body,
    [
      ("content-encoding", "identity"),
      ("x-goog-generation", "9007199254740993"),
      ("x-goog-metageneration", "2"),
    ],
  ).unwrap()
  assert_eq(original.response_sha256, @sha.hex(body))
  assert_eq(original.original.unwrap().fields.generation, 9007199254740993L)
  for
    (header, value) in [
      ("x-goog-generation", "9007199254740994"),
      ("x-goog-metageneration", "3"),
      ("x-goog-generation", "09007199254740993"),
    ] {
    assert_true(
      admit_object_upload_target_observation(binding, name, 200, body, [
        (header, value),
      ])
      is Err(StaleObservation),
    )
  }
}

///|
test "GCS target read does not convert refused or contradictory metadata into absence" {
  let binding = upload_request_binding()
  let name = "in/é%2F.bin"
  let body = b"{\"error\":{\"code\":404}}"
  let absent = admit_object_upload_target_observation(
    binding,
    name,
    404,
    body,
    [],
  ).unwrap()
  assert_true(absent.original is None)
  assert_eq(
    object_upload_cid(upload_request(binding, absent).unwrap()),
    "sha256:6c286b44b63592dd69d7ab707b710fdf6b5bd0199594589d70fe9e27a535a4de",
  )
  for
    headers in [
      [("x-goog-generation", "1")],
      [("x-goog-metageneration", "1")],
      [("content-encoding", "gzip")],
      [("content-encoding", "")],
    ] {
    assert_true(
      admit_object_upload_target_observation(binding, name, 404, body, headers)
      is Err(InvalidInput),
    )
  }
  for status in [0, 201, 204, 206, 304, 403, 412, 500, 600] {
    assert_true(
      admit_object_upload_target_observation(binding, name, status, body, [])
      is Err(InvalidInput),
    )
  }
}

///|
test "GCS target read rejects duplicate foreign or over-budget observed headers" {
  let binding = upload_request_binding()
  let name = "in/é%2F.bin"
  for
    headers in [
      [("content-encoding", "identity"), ("content-encoding", "identity")],
      [("x-goog-generation", "1"), ("x-goog-generation", "1")],
      [("Content-Encoding", "identity")],
      [("content-range", "bytes 0-0/1")],
    ] {
    assert_true(
      admit_object_upload_target_observation(binding, name, 404, b"{}", headers)
      is Err(InvalidInput),
    )
  }
  assert_true(
    admit_object_upload_target_observation(binding, name, 404, b"{}", [
      ("content-encoding", "identity"),
      ("x-goog-generation", "1"),
      ("x-goog-metageneration", "1"),
      ("x-goog-generation", "1"),
    ])
    is Err(CapacityExceeded),
  )
  assert_true(
    admit_object_upload_target_observation(binding, name, 404, b"{}", [
      ("content-encoding", "a".repeat(metadata_limits().max_bytes + 1)),
    ])
    is Err(CapacityExceeded),
  )
}
