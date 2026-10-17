///|
test "GCS mutation target read preserves exact path versions and original response hash" {
  let binding = mutation_binding()
  let name = "in/é%2F.bin"
  assert_eq(
    object_mutation_metadata_path(binding, name),
    Ok("/storage/v1/b/bucket/o/in%2Fe%CC%81%252F.bin"),
  )
  let body = b"{\"bucket\":\"bucket\",\"name\":\"in/e\xCC\x81%2F.bin\",\"generation\":\"9007199254740993\",\"metageneration\":\"2\",\"size\":\"7\"}"
  let original = admit_object_mutation_target_observation(
    binding,
    name,
    200,
    body,
    [
      ("x-goog-generation", "9007199254740993"),
      ("x-goog-metageneration", "2"),
      ("content-encoding", "identity"),
    ],
  ).unwrap()
  assert_eq(original.fields.name, name)
  assert_eq(original.fields.generation, 9007199254740993L)
  assert_eq(original.fields.metageneration, 2L)
  assert_eq(
    original.response_sha256,
    "339823cc8338e2e0db12486efead1e17b618c62129f82d7f9bacf515de60289e",
  )
}

///|
test "GCS mutation target read refuses missing partial foreign and malformed representations" {
  let binding = mutation_binding()
  let name = "in/é%2F.csv"
  for status in [0, 201, 204, 206, 304, 403, 404, 412, 500, 600] {
    assert_true(
      admit_object_mutation_target_observation(binding, name, status, b"{}", [])
      is Err(InvalidResponse),
    )
  }
  assert_true(
    admit_object_mutation_target_observation(binding, name, 200, b"\xFF", [])
    is Err(Metadata(_)),
  )
  let body = @utf8.encode(
    "{\"bucket\":\"bucket\",\"name\":\"in/other\",\"generation\":\"1\",\"metageneration\":\"2\",\"size\":\"0\"}",
  )
  assert_true(
    admit_object_mutation_target_observation(binding, name, 200, body, [])
    is Err(Metadata(_)),
  )
}

///|
test "GCS mutation target read refuses contradictory duplicate and over-budget headers" {
  let binding = mutation_binding()
  let body = @utf8.encode(
    "{\"bucket\":\"bucket\",\"name\":\"in/a\",\"generation\":\"1\",\"metageneration\":\"2\",\"size\":\"0\"}",
  )
  for
    headers in [
      [("x-goog-generation", "2")],
      [("x-goog-metageneration", "3")],
      [("x-goog-generation", "01")],
      [("content-encoding", "gzip")],
      [("Content-Encoding", "identity")],
      [("content-range", "bytes 0-0/1")],
      [("x-goog-generation", "1"), ("x-goog-generation", "1")],
    ] {
    assert_true(
      admit_object_mutation_target_observation(
        binding, "in/a", 200, body, headers,
      )
      is Err(InvalidResponse),
    )
  }
  assert_true(
    admit_object_mutation_target_observation(binding, "in/a", 200, body, [
      ("content-encoding", "a".repeat(metadata_limits().max_bytes + 1)),
    ])
    is Err(CapacityExceeded),
  )
}

///|
test "GCS mutation target read validates original name and exact path capacity before acquisition" {
  let path = "/storage/v1/b/bucket/o/in%2Fa"
  let limits = mutation_limits()
  let exact = mutation_binding(limits={
    ..limits,
    max_path_bytes: path.length(),
  })
  assert_eq(object_mutation_metadata_path(exact, "in/a"), Ok(path))
  let short = mutation_binding(limits={
    ..limits,
    max_path_bytes: path.length() - 1,
  })
  assert_eq(object_mutation_metadata_path(short, "in/a"), Err(CapacityExceeded))
  for name in ["", "outside/a", "in/a\rb", "in/a\nb"] {
    assert_eq(object_mutation_metadata_path(exact, name), Err(InvalidName))
  }
  assert_eq(
    object_mutation_metadata_max_bytes(exact),
    metadata_limits().max_bytes,
  )
}
