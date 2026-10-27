///|
fn compose_binding(
  target? : ObjectUploadBinding = upload_request_binding(),
  count? : Int = 32,
  maximum? : Int64 = 1000000L,
) -> ObjectComposeBinding {
  prepare_object_compose_binding(target, count, maximum).unwrap()
}

///|
fn compose_source(
  name? : String = "in/é%2F.bin",
  generation? : String = "9007199254740993",
  meta? : String = "2",
  size? : String = "4",
  crc? : String = "crxyRA==",
  storage_class? : String = "STANDARD",
  bucket? : String = "bucket",
  content_type? : String = "application/octet-stream",
) -> ObjectMetadata {
  admit_object_metadata(
    @utf8.encode(
      "{\"bucket\":\"" +
      bucket +
      "\",\"name\":\"" +
      name +
      "\",\"generation\":\"" +
      generation +
      "\",\"metageneration\":\"" +
      meta +
      "\",\"size\":\"" +
      size +
      "\",\"crc32c\":\"" +
      crc +
      "\",\"storageClass\":\"" +
      storage_class +
      "\",\"contentType\":\"" +
      content_type +
      "\"}",
    ),
    bucket,
    "",
    None,
    metadata_limits(),
  ).unwrap()
}

///|
fn compose_existing(
  binding : ObjectComposeBinding,
  meta? : String = "2",
  metadata? : String = "{\"é\":\"=exact\\r\\n\",\"\":\"\",\"actql-request\":\"old-marker\"}",
) -> ObjectUploadObservation {
  admit_object_upload_observation(
    binding.target,
    "in/é%2F.bin",
    200,
    @utf8.encode(
      "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.bin\",\"generation\":\"9007199254740993\",\"metageneration\":\"" +
      meta +
      "\",\"size\":\"7\",\"contentType\":\"text/csv\",\"metadata\":" +
      metadata +
      "}",
    ),
  ).unwrap()
}

///|
fn compose_sources() -> Array[ObjectMetadata] {
  [
    compose_source(),
    compose_source(name="in/part2", size="2", crc="QtGpAA=="),
    compose_source(),
  ]
}

///|
fn compose_request(
  binding : ObjectComposeBinding,
  sources? : Array[ObjectMetadata] = compose_sources(),
  before? : ObjectUploadObservation? = None,
) -> Result[ObjectComposeRequest, ObjectUploadIssue] {
  prepare_object_compose(
    binding,
    before.unwrap_or(upload_absent(binding.target)),
    sources,
    mutation_marker(),
  )
}

///|
test "GCS compose CRC algebra matches independently authored exact binary concatenation" {
  // Independent byte-wise Castagnoli oracle: 00 ff 0d 0a + 42 0a + 00 ff 0d 0a.
  let a = compose_crc_value("crxyRA==").unwrap()
  let b = compose_crc_value("QtGpAA==").unwrap()
  assert_eq(
    compose_crc_text(compose_crc_join(compose_crc_join(a, b, 2L), a, 4L)),
    "ml8N0A==",
  )
  assert_eq(compose_crc_text(compose_crc_join(b, a, 4L)), "DTxq6A==")
  assert_eq(compose_crc_join(a, 0, 0L), a)
  assert_eq(compose_crc_join(0, 0, 9223372036854775807L), 0)
  for text in ["", "crxyRA", "crxyRB==", "AAAA", "AAAAAAAA"] {
    assert_eq(compose_crc_value(text), None)
  }
}

///|
test "GCS compose seals original source order repetitions and exact generation guards" {
  let binding = compose_binding()
  let request = compose_request(binding).unwrap()
  assert_eq(
    request.path,
    "/storage/v1/b/bucket/o/in%2Fe%CC%81%252F.bin/compose?ifGenerationMatch=0",
  )
  assert_eq(request.size, 10L)
  assert_eq(request.crc32c, "ml8N0A==")
  assert_eq(
    request.body,
    "{\"deleteSourceObjects\":false,\"destination\":{\"contentType\":\"application/octet-stream\",\"metadata\":{\"actql-request\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"},\"name\":\"in/é%2F.bin\",\"storageClass\":\"STANDARD\"},\"sourceObjects\":[{\"generation\":\"9007199254740993\",\"name\":\"in/é%2F.bin\",\"objectPreconditions\":{\"ifGenerationMatch\":\"9007199254740993\"}},{\"generation\":\"9007199254740993\",\"name\":\"in/part2\",\"objectPreconditions\":{\"ifGenerationMatch\":\"9007199254740993\"}},{\"generation\":\"9007199254740993\",\"name\":\"in/é%2F.bin\",\"objectPreconditions\":{\"ifGenerationMatch\":\"9007199254740993\"}}]}",
  )
  assert_eq(object_compose_body_for(binding, request), Ok(request.body))
  assert_eq(
    request.cid,
    "sha256:31ba23a210776b18fd6c4bc8c6f22c435e856997930c538373c2d01ea8f42c07",
  )
  assert_eq(
    recheck_object_compose(binding, request, request.before, request.sources),
    Ok(()),
  )
}

///|
test "GCS compose copies caller arrays without merging repeated originals or normalizing metadata" {
  let binding = compose_binding()
  let sources = compose_sources()
  let before = compose_existing(binding)
  let request = compose_request(binding, sources~, before=Some(before)).unwrap()
  sources[0] = compose_source(name="in/replaced")
  object_metadata_fields(before.original.unwrap()).metadata.unwrap()[0] = (
    "é", "changed",
  )
  assert_eq(request.sources[0].fields.name, "in/é%2F.bin")
  assert_eq(request.properties.metadata[0], ("é", "=exact\r\n"))
  assert_eq(request.sources.length(), 3)
  assert_eq(request.body.find("changed"), None)
  assert_eq(
    recheck_object_compose(binding, request, request.before, sources),
    Err(StaleObservation),
  )
  assert_not_eq(
    request.cid,
    compose_request(binding, sources~, before=Some(before)).unwrap().cid,
  )
}

///|
test "GCS compose bounds zero one 32 and 33 sources and checks Int64 sum before overflow" {
  let binding = compose_binding()
  assert_true(compose_request(binding, sources=[]) is Err(InvalidInput))
  assert_true(compose_request(binding, sources=[compose_source()]) is Ok(_))
  // Larger node/body declarations for this explicit 32-member control only.
  // No production profile or existing declaration is raised.
  let target = upload_request_binding(limits={
    ..upload_request_limits(),
    metadata: { ..metadata_limits(), max_nodes: 1000, },
    max_body_bytes: 16384,
    max_identity_bytes: 16384,
  })
  let wide = compose_binding(target~)
  assert_true(
    compose_request(wide, sources=Array::make(32, compose_source())) is Ok(_),
  )
  assert_true(
    compose_request(wide, sources=Array::make(33, compose_source()))
    is Err(CapacityExceeded),
  )
  assert_true(
    compose_request(compose_binding(count=1), sources=compose_sources())
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_object_compose_binding(target, 0, 1L) is Err(InvalidBinding),
  )
  assert_true(
    prepare_object_compose_binding(target, 33, 1L) is Err(InvalidBinding),
  )
  assert_true(
    prepare_object_compose_binding(target, 32, -1L) is Err(InvalidBinding),
  )
  let maximum = compose_binding(maximum=5497558138880L)
  let huge = compose_source(size="9223372036854775807", crc="AAAAAA==")
  assert_true(compose_request(maximum, sources=[huge]) is Err(CapacityExceeded))
  assert_true(
    compose_request(maximum, sources=[huge, compose_source()])
    is Err(CapacityExceeded),
  )
  let full = compose_source(size="5497558138880", crc="AAAAAA==")
  assert_eq(
    compose_request(maximum, sources=[full]).unwrap().size,
    5497558138880L,
  )
  assert_true(
    compose_request(maximum, sources=[full, compose_source()])
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_object_compose_binding(target, 32, 5497558138881L)
    is Err(InvalidBinding),
  )
  let exact = compose_binding(maximum=10L)
  assert_true(compose_request(exact) is Ok(_))
  assert_true(
    compose_request(compose_binding(maximum=9L)) is Err(CapacityExceeded),
  )
  let empty = compose_source(size="0", crc="AAAAAA==")
  assert_eq(
    compose_request(compose_binding(maximum=0L), sources=[empty]).unwrap().size,
    0L,
  )
  assert_true(
    compose_request(binding, sources=[compose_source(size="0")])
    is Err(InvalidInput),
  )
}

///|
test "GCS compose refuses missing integrity foreign scope and incompatible storage classes" {
  let binding = compose_binding()
  for
    source in [
      compose_source(name="outside/file"),
      compose_source(bucket="foreign"),
      compose_source(crc="not-a-digest"),
      compose_source(storage_class=""),
    ] {
    assert_true(compose_request(binding, sources=[source]) is Err(InvalidInput))
  }
  assert_true(
    compose_request(binding, sources=[
      compose_source(),
      compose_source(storage_class="COLDLINE"),
    ])
    is Err(InvalidInput),
  )
  let missing = metadata_read(metadata_wire()).unwrap()
  assert_true(compose_request(binding, sources=[missing]) is Err(InvalidInput))
}

///|
test "GCS compose independent exact body path and identity ceilings refuse one byte short" {
  // Independent preimages: 611-byte body, 72-byte path, 1666-byte identity.
  let make = (body, path, identity) => {
    compose_binding(
      target=upload_request_binding(limits={
        ..upload_request_limits(),
        max_body_bytes: body,
        max_path_bytes: path,
        max_identity_bytes: identity,
      }),
    )
  }
  assert_true(compose_request(make(611, 72, 1666)) is Ok(_))
  for binding in [make(610, 72, 1666), make(611, 71, 1666), make(611, 72, 1665)] {
    assert_true(compose_request(binding) is Err(CapacityExceeded))
  }
}

///|
test "GCS compose preserves captured metadata replaces only original marker and accounts physical entry" {
  let binding = compose_binding()
  let before = compose_existing(binding)
  let request = compose_request(binding, before=Some(before)).unwrap()
  assert_eq(
    request.cid,
    "sha256:da581736847bc40a432009ea6943d3ebcdd5cd3560efac680f1bd057539ba456",
  )
  assert_eq(request.properties.content_type, "text/csv")
  assert_eq(request.properties.metadata, [("é", "=exact\r\n"), ("", "")])
  assert_eq(request.body.find("old-marker"), None)
  let legal = compose_existing(
    binding,
    metadata="{\"Actql-request\":\"user\",\"actql-request-extra\":\"user\",\"é\":\"NFD\"}",
  )
  assert_true(compose_request(binding, before=Some(legal)) is Ok(_))
  let full = compose_existing(
    binding,
    metadata="{\"one\":\"1\",\"two\":\"2\",\"three\":\"3\",\"four\":\"4\"}",
  )
  assert_true(
    compose_request(binding, before=Some(full)) is Err(CapacityExceeded),
  )
  assert_true(
    compose_request(binding, sources=[compose_source(content_type="TEXT/CSV")])
    is Err(InvalidInput),
  )
}

///|
test "GCS compose Preview preserves captured user properties without exposing old or new marker values" {
  let binding = compose_binding()
  let request = compose_request(binding, before=Some(compose_existing(binding))).unwrap()
  let wire = object_compose_projection_json(binding, request, 8192).unwrap()
  assert_true(wire.contains("\"property_selection\":\"captured_destination\""))
  assert_true(wire.contains("\"content_type\":\"text/csv\""))
  assert_true(wire.contains("\"é\":\"=exact\\r\\n\""))
  assert_false(wire.contains("old-marker"))
  assert_false(wire.contains(mutation_marker()))
  assert_true(wire.contains("assign_original_request_marker:actql-request"))
  assert_true(
    object_compose_projection_json(binding, request, 1) is Err(CapacityExceeded),
  )
  assert_true(
    object_compose_projection_json(compose_binding(), request, 8192)
    is Err(ForeignBinding),
  )
}

///|
test "GCS compose only classifies original direct conflict or matching applied response" {
  let binding = compose_binding()
  let request = compose_request(binding).unwrap()
  let unknown = "{\"kind\":\"provider-response\"}"
  for status in [0, 201, 308, 400, 401, 403, 404, 429, 500, 503] {
    assert_eq(
      object_compose_response_projection_json(
        binding, request, status, b"{}", 1024,
      ),
      Ok(unknown),
    )
  }
  for body in [b"{}", b"\xff", b"{\"generation\":\"1\",\"generation\":\"2\"}"] {
    assert_eq(
      object_compose_response_projection_json(binding, request, 200, body, 1024),
      Ok(unknown),
    )
  }
  let answer =
    #|{"bucket":"bucket","name":"in/é%2F.bin","generation":"9007199254740994","metageneration":"1","size":"10","crc32c":"ml8N0A==","storageClass":"STANDARD","contentType":"application/octet-stream","metadata":{"actql-request":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}
  assert_eq(
    object_compose_response_projection_json(
      binding,
      request,
      200,
      @utf8.encode(answer),
      1024,
    ),
    Ok(
      "{\"kind\":\"typed-success-response\",\"outcome\":{\"result\":{},\"state\":\"applied\"}}",
    ),
  )
  assert_true(
    object_compose_response_projection_json(binding, request, 412, b"{}", 1024)
    .unwrap()
    .contains("typed-failure-response"),
  )
  assert_true(
    object_compose_response_projection_json(binding, request, 412, b"{}", 1)
    is Err(CapacityExceeded),
  )
  assert_true(
    object_compose_response_projection_json(
      binding,
      request,
      200,
      Bytes::make(8193, 32),
      1024,
    )
    is Err(CapacityExceeded),
  )
}

///|
test "GCS compose refuses equal wire foreign binding and changed original destination or source" {
  let binding = compose_binding()
  let request = compose_request(binding).unwrap()
  let foreign = compose_binding()
  assert_eq(object_compose_body_for(foreign, request), Err(ForeignBinding))
  assert_eq(
    recheck_object_compose(foreign, request, request.before, request.sources),
    Err(ForeignBinding),
  )
  assert_true(
    prepare_object_compose(
      binding,
      upload_absent(foreign.target),
      request.sources,
      mutation_marker(),
    )
    is Err(ForeignBinding),
  )
  let before = compose_existing(binding)
  let replacement = prepare_object_compose(
    binding,
    before,
    request.sources,
    mutation_marker(),
  ).unwrap()
  assert_true(
    replacement.path.contains(
      "ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2",
    ),
  )
  assert_eq(
    recheck_object_compose(
      binding,
      replacement,
      compose_existing(binding, meta="3"),
      request.sources,
    ),
    Err(StaleObservation),
  )
  assert_eq(
    recheck_object_compose(
      binding,
      replacement,
      request.before,
      request.sources,
    ),
    Err(StaleObservation),
  )
  for
    source in [
      compose_source(meta="3"),
      compose_source(generation="9007199254740994"),
    ] {
    assert_eq(
      recheck_object_compose(binding, request, request.before, [
        source,
        request.sources[1],
        request.sources[2],
      ]),
      Err(StaleObservation),
    )
  }
  let permissions = compose_binding(
    target=upload_request_binding(permissions=["different.permission"]),
  )
  let other = compose_request(permissions).unwrap()
  assert_eq(other.body, request.body)
  assert_not_eq(other.cid, request.cid)
}

///|
test "GCS compose response matching requires original marker checksum exact properties and new version" {
  let binding = compose_binding()
  let request = prepare_object_compose(
    binding,
    compose_existing(binding),
    compose_sources(),
    mutation_marker(),
  ).unwrap()
  let answer =
    #|{"bucket":"bucket","name":"in/é%2F.bin","generation":"9007199254740994","metageneration":"1","size":"10","crc32c":"ml8N0A==","storageClass":"STANDARD","contentType":"text/csv","metadata":{"":"","é":"=exact\r\n","actql-request":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}
  let read = text => {
    admit_object_metadata(
      @utf8.encode(text),
      "bucket",
      "in/",
      None,
      metadata_limits(),
    ).unwrap()
  }
  assert_true(object_compose_response_matches(binding, request, read(answer)))
  for
    body in [
      answer.replace(old="ml8N0A==", new="AAAAAA=="),
      answer.replace(old="\"size\":\"10\"", new="\"size\":\"9\""),
      answer.replace(old="sha256:dddd", new="sha256:aaaa"),
      answer.replace(old="=exact", new="changed"),
      answer.replace(old="STANDARD", new="COLDLINE"),
      answer.replace(old="9007199254740994", new="9007199254740993"),
    ] {
    assert_false(object_compose_response_matches(binding, request, read(body)))
  }
  assert_false(
    object_compose_response_matches(compose_binding(), request, read(answer)),
  )
}

///|
test "GCS compose accepts a distinct lower generation without weakening response correlation" {
  // Generation is a version identity, not a monotonic counter. These Int64
  // values are independently authored beyond the exact JavaScript Number range.
  let binding = compose_binding()
  let request = compose_request(binding, before=Some(compose_existing(binding))).unwrap()
  let answer =
    #|{"bucket":"bucket","name":"in/é%2F.bin","generation":"9007199254740992","metageneration":"1","size":"10","crc32c":"ml8N0A==","storageClass":"STANDARD","contentType":"text/csv","metadata":{"":"","é":"=exact\r\n","actql-request":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}
  let response = admit_object_metadata(
    @utf8.encode(answer),
    "bucket",
    "in/",
    None,
    metadata_limits(),
  ).unwrap()
  assert_true(object_compose_response_matches(binding, request, response))
  assert_eq(
    object_compose_response_projection_json(
      binding,
      request,
      200,
      @utf8.encode(answer),
      1024,
    ),
    Ok(
      "{\"kind\":\"typed-success-response\",\"outcome\":{\"result\":{},\"state\":\"applied\"}}",
    ),
  )
  for
    body in [
      answer.replace(old="9007199254740992", new="9007199254740993"),
      answer.replace(
        old="\"metageneration\":\"1\"",
        new="\"metageneration\":\"2\"",
      ),
      answer.replace(old="sha256:dddd", new="sha256:aaaa"),
    ] {
    assert_eq(
      object_compose_response_projection_json(
        binding,
        request,
        200,
        @utf8.encode(body),
        1024,
      ),
      Ok("{\"kind\":\"provider-response\"}"),
    )
  }
  assert_eq(
    object_compose_response_projection_json(
      compose_binding(),
      request,
      200,
      @utf8.encode(answer),
      1024,
    ),
    Err(ForeignBinding),
  )
}
