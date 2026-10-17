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
) -> ObjectMetadata {
  admit_object_metadata(
    @utf8.encode(
      "{\"bucket\":\"" + bucket + "\",\"name\":\"" + name +
      "\",\"generation\":\"" + generation + "\",\"metageneration\":\"" + meta +
      "\",\"size\":\"" + size + "\",\"crc32c\":\"" + crc +
      "\",\"storageClass\":\"" + storage_class + "\"}",
    ),
    bucket, "", None, metadata_limits(),
  ).unwrap()
}

///|
fn compose_properties_fixture() -> ObjectComposeProperties {
  { content_type: Some("application/octet-stream"), content_encoding: None,
    metadata: [("é", "=exact\r\n"), ("", "")], }
}

///|
fn compose_sources() -> Array[ObjectMetadata] {
  [compose_source(), compose_source(name="in/part2", size="2", crc="QtGpAA=="), compose_source()]
}

///|
fn compose_request(
  binding : ObjectComposeBinding,
  sources? : Array[ObjectMetadata] = compose_sources(),
  properties? : ObjectComposeProperties = compose_properties_fixture(),
) -> Result[ObjectComposeRequest, ObjectUploadIssue] {
  prepare_object_compose(binding, upload_absent(binding.target), sources,
    properties, mutation_marker())
}

///|
test "GCS compose CRC algebra matches independently authored exact binary concatenation" {
  // Independent byte-wise Castagnoli oracle: 00 ff 0d 0a + 42 0a + 00 ff 0d 0a.
  let a = compose_crc_value("crxyRA==").unwrap()
  let b = compose_crc_value("QtGpAA==").unwrap()
  assert_eq(compose_crc_text(compose_crc_join(compose_crc_join(a, b, 2L), a, 4L)), "ml8N0A==")
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
  assert_eq(request.path,
    "/storage/v1/b/bucket/o/in%2Fe%CC%81%252F.bin/compose?ifGenerationMatch=0")
  assert_eq(request.size, 10L)
  assert_eq(request.crc32c, "ml8N0A==")
  assert_eq(request.body,
    "{\"deleteSourceObjects\":false,\"destination\":{\"contentType\":\"application/octet-stream\",\"metadata\":{\"\":\"\",\"actql-request\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"é\":\"=exact\\r\\n\"},\"name\":\"in/é%2F.bin\",\"storageClass\":\"STANDARD\"},\"sourceObjects\":[{\"generation\":\"9007199254740993\",\"name\":\"in/é%2F.bin\",\"objectPreconditions\":{\"ifGenerationMatch\":\"9007199254740993\"}},{\"generation\":\"9007199254740993\",\"name\":\"in/part2\",\"objectPreconditions\":{\"ifGenerationMatch\":\"9007199254740993\"}},{\"generation\":\"9007199254740993\",\"name\":\"in/é%2F.bin\",\"objectPreconditions\":{\"ifGenerationMatch\":\"9007199254740993\"}}]}")
  assert_eq(object_compose_body_for(binding, request), Ok(request.body))
  assert_true(request.cid.has_prefix("sha256:"))
  assert_eq(recheck_object_compose(binding, request, request.before, request.sources), Ok(()))
}

///|
test "GCS compose copies caller arrays without merging repeated originals or normalizing metadata" {
  let binding = compose_binding()
  let sources = compose_sources()
  let properties = compose_properties_fixture()
  let request = compose_request(binding, sources~, properties~).unwrap()
  sources[0] = compose_source(name="in/replaced")
  properties.metadata[0] = ("é", "changed")
  assert_eq(request.sources[0].fields.name, "in/é%2F.bin")
  assert_eq(request.properties.metadata[0], ("é", "=exact\r\n"))
  assert_eq(request.sources.length(), 3)
  assert_eq(request.body.find("changed"), None)
  assert_eq(recheck_object_compose(binding, request, request.before, sources), Err(StaleObservation))
  assert_not_eq(request.cid, compose_request(binding, sources~).unwrap().cid)
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
  assert_true(compose_request(wide, sources=Array::make(32, compose_source())) is Ok(_))
  assert_true(compose_request(wide, sources=Array::make(33, compose_source())) is Err(CapacityExceeded))
  assert_true(compose_request(compose_binding(count=1), sources=compose_sources()) is Err(CapacityExceeded))
  assert_true(prepare_object_compose_binding(target, 0, 1L) is Err(InvalidBinding))
  assert_true(prepare_object_compose_binding(target, 33, 1L) is Err(InvalidBinding))
  assert_true(prepare_object_compose_binding(target, 32, -1L) is Err(InvalidBinding))
  let maximum = compose_binding(maximum=9223372036854775807L)
  let huge = compose_source(size="9223372036854775807", crc="AAAAAA==")
  assert_eq(compose_request(maximum, sources=[huge]).unwrap().size, 9223372036854775807L)
  assert_true(compose_request(maximum, sources=[huge, compose_source()]) is Err(CapacityExceeded))
  let exact = compose_binding(maximum=10L)
  assert_true(compose_request(exact) is Ok(_))
  assert_true(compose_request(compose_binding(maximum=9L)) is Err(CapacityExceeded))
  let empty = compose_source(size="0", crc="AAAAAA==")
  assert_eq(compose_request(compose_binding(maximum=0L), sources=[empty]).unwrap().size, 0L)
  assert_true(compose_request(binding, sources=[compose_source(size="0")]) is Err(InvalidInput))
}

///|
test "GCS compose refuses missing integrity foreign scope and incompatible storage classes" {
  let binding = compose_binding()
  for source in [
    compose_source(name="outside/file"), compose_source(bucket="foreign"),
    compose_source(crc="not-a-digest"), compose_source(storage_class=""),
  ] {
    assert_true(compose_request(binding, sources=[source]) is Err(InvalidInput))
  }
  assert_true(compose_request(binding, sources=[compose_source(), compose_source(storage_class="COLDLINE")]) is Err(InvalidInput))
  let missing = metadata_read(metadata_wire()).unwrap()
  assert_true(compose_request(binding, sources=[missing]) is Err(InvalidInput))
}

///|
test "GCS compose reserves only exact marker key and accounts its physical entry" {
  let binding = compose_binding()
  for entries in [
    [("actql-request", "foreign")], [("key", "one"), ("key", "two")],
  ] {
    assert_true(compose_request(binding, properties={ ..compose_properties_fixture(), metadata: entries, }) is Err(InvalidInput))
  }
  let legal = { ..compose_properties_fixture(), metadata: [("Actql-request", "user"), ("actql-request-extra", "user"), ("é", "NFD")], }
  assert_true(compose_request(binding, properties=legal) is Ok(_))
  let entries = legal.metadata.copy()
  entries.push(("fourth", "user"))
  let full = { ..legal, metadata: entries, }
  assert_true(compose_request(binding, properties=full) is Err(CapacityExceeded))
  assert_true(compose_request(binding, properties={ ..legal, content_type: Some("TEXT/CSV"), }) is Err(InvalidInput))
}

///|
test "GCS compose refuses equal wire foreign binding and changed original destination or source" {
  let binding = compose_binding()
  let request = compose_request(binding).unwrap()
  let foreign = compose_binding()
  assert_eq(object_compose_body_for(foreign, request), Err(ForeignBinding))
  assert_eq(recheck_object_compose(foreign, request, request.before, request.sources), Err(ForeignBinding))
  assert_true(prepare_object_compose(binding, upload_absent(foreign.target), request.sources, request.properties, mutation_marker()) is Err(ForeignBinding))
  let before = upload_existing(binding.target)
  let replacement = prepare_object_compose(binding, before, request.sources, request.properties, mutation_marker()).unwrap()
  assert_true(replacement.path.contains("ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2"))
  assert_eq(recheck_object_compose(binding, replacement, upload_existing(binding.target, metageneration="3"), request.sources), Err(StaleObservation))
  assert_eq(recheck_object_compose(binding, replacement, request.before, request.sources), Err(StaleObservation))
  for source in [compose_source(meta="3"), compose_source(generation="9007199254740994")] {
    assert_eq(recheck_object_compose(binding, request, request.before, [source, request.sources[1], request.sources[2]]), Err(StaleObservation))
  }
  let permissions = compose_binding(target=upload_request_binding(permissions=["different.permission"]))
  let other = compose_request(permissions).unwrap()
  assert_eq(other.body, request.body)
  assert_not_eq(other.cid, request.cid)
}

///|
test "GCS compose response matching requires original marker checksum exact properties and new version" {
  let binding = compose_binding()
  let request = prepare_object_compose(binding, upload_existing(binding.target),
    compose_sources(), compose_properties_fixture(), mutation_marker()).unwrap()
  let answer =
    #|{"bucket":"bucket","name":"in/é%2F.bin","generation":"9007199254740994","metageneration":"1","size":"10","crc32c":"ml8N0A==","storageClass":"STANDARD","contentType":"application/octet-stream","metadata":{"":"","é":"=exact\r\n","actql-request":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}
  let read = text => admit_object_metadata(@utf8.encode(text), "bucket", "in/", None, metadata_limits()).unwrap()
  assert_true(object_compose_response_matches(binding, request, read(answer)))
  for body in [
    answer.replace(old="ml8N0A==", new="AAAAAA=="),
    answer.replace(old="\"size\":\"10\"", new="\"size\":\"9\""),
    answer.replace(old="sha256:dddd", new="sha256:aaaa"),
    answer.replace(old="=exact", new="changed"),
    answer.replace(old="STANDARD", new="COLDLINE"),
    answer.replace(old="9007199254740994", new="9007199254740993"),
  ] {
    assert_false(object_compose_response_matches(binding, request, read(body)))
  }
  assert_false(object_compose_response_matches(compose_binding(), request, read(answer)))
}
