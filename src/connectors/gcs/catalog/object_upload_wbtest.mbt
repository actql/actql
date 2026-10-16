///|
fn upload_request_limits() -> ObjectUploadLimits {
  {
    metadata: metadata_limits(),
    max_content_bytes: 32,
    max_body_bytes: 2048,
    max_path_bytes: 4096,
    max_identity_bytes: 4096,
  }
}

///|
fn upload_request_binding(
  permissions? : Array[String] = [
    "storage.objects.create", "storage.objects.delete", "storage.objects.get",
  ],
  limits? : ObjectUploadLimits = upload_request_limits(),
) -> ObjectUploadBinding {
  let collection = prepare_object_collection_binding(
    "project",
    "bucket",
    "in/",
    "connector://exports/objects",
    "file_collection",
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    { max_bytes: 8192, max_nodes: 100, max_depth: 8, },
  ).unwrap()
  prepare_object_upload_binding(
    collection,
    "sha256:" + "c".repeat(64),
    permissions,
    limits,
  ).unwrap()
}

///|
fn upload_absent(binding : ObjectUploadBinding) -> ObjectUploadObservation {
  admit_object_upload_observation(
    binding, "in/é%2F.bin", 404, b"{\"error\":{\"code\":404}}",
  ).unwrap()
}

///|
fn upload_existing(
  binding : ObjectUploadBinding,
  generation? : String = "9007199254740993",
  metageneration? : String = "2",
) -> ObjectUploadObservation {
  admit_object_upload_observation(
    binding,
    "in/é%2F.bin",
    200,
    @utf8.encode(
      "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.bin\",\"generation\":\"" +
      generation +
      "\",\"metageneration\":\"" +
      metageneration +
      "\",\"size\":\"7\"}",
    ),
  ).unwrap()
}

///|
fn upload_binary() -> Bytes {
  Bytes::from_array([0, 255, 13, 10])
}

///|
fn upload_request(
  binding : ObjectUploadBinding,
  before : ObjectUploadObservation,
  overwrite? : Bool? = None,
) -> Result[ObjectUploadRequest, ObjectUploadIssue] {
  prepare_object_multipart_upload(
    binding,
    before,
    upload_binary(),
    "sha256:" + "f".repeat(64),
    "sha256:e9489f37fb3051e9efa1dc916004d7274e7b63975e3209708947267f2393a9be",
    "application/octet-stream",
    overwrite,
    mutation_marker(),
  )
}

///|
// Independent Node crypto/JSON and bitwise Castagnoli calculation, without
// importing the product encoder or obtaining expectations from its output.
test "GCS multipart seals binary body marker CRC and independent request identity" {
  let binding = upload_request_binding()
  let request = upload_request(binding, upload_absent(binding)).unwrap()
  assert_eq(
    object_upload_path(request),
    "/upload/storage/v1/b/bucket/o?uploadType=multipart&ifGenerationMatch=0",
  )
  assert_eq(
    object_upload_cid(request),
    "sha256:6c286b44b63592dd69d7ab707b710fdf6b5bd0199594589d70fe9e27a535a4de",
  )
  let boundary = "actql-e9489f37fb3051e9efa1dc916004d7274e7b63975e3209708947267f2393a9be"
  assert_eq(
    object_upload_body_media_type(request),
    "multipart/related; boundary=" + boundary,
  )
  let body = object_upload_body_for(binding, request).unwrap()
  assert_eq(body.length(), 511)
  assert_eq(
    @sha.hex(body),
    "d0bbda939f3adf67d2f13e4ab4138769a075ab50c459a0ddde5d56b3583e719c",
  )
  let head = @utf8.encode(
    "--" +
    boundary +
    "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n" +
    "{\"contentType\":\"application/octet-stream\",\"crc32c\":\"crxyRA==\",\"metadata\":{\"actql-request\":\"" +
    mutation_marker() +
    "\"},\"name\":\"in/é%2F.bin\"}\r\n--" +
    boundary +
    "\r\nContent-Type: application/octet-stream\r\n\r\n",
  )
  let tail = @utf8.encode("\r\n--" + boundary + "--\r\n")
  assert_eq(body, head + upload_binary() + tail)
  assert_eq(
    recheck_object_upload(binding, request, upload_absent(binding)),
    Ok(()),
  )
}

///|
test "GCS multipart preserves original binding and permission identities" {
  let permissions = [
    "storage.objects.create", "storage.objects.delete", "storage.objects.get",
  ]
  let binding = upload_request_binding(permissions~)
  permissions[0] = "changed.after.constructor"
  let request = upload_request(binding, upload_absent(binding)).unwrap()
  assert_eq(
    object_upload_cid(request),
    "sha256:6c286b44b63592dd69d7ab707b710fdf6b5bd0199594589d70fe9e27a535a4de",
  )
  let copied = upload_request_binding()
  assert_true(
    upload_request(copied, upload_absent(binding)) is Err(ForeignBinding),
  )
  assert_eq(
    object_upload_body_for(copied, request).map(_ => ()),
    Err(ForeignBinding),
  )
  assert_eq(
    recheck_object_upload(copied, request, upload_absent(copied)),
    Err(ForeignBinding),
  )
  let foreign = upload_request_binding(permissions=["different.permission"])
  let changed = upload_request(foreign, upload_absent(foreign)).unwrap()
  assert_eq(object_upload_path(changed), object_upload_path(request))
  assert_eq(
    object_upload_body_for(foreign, changed).unwrap(),
    object_upload_body_for(binding, request).unwrap(),
  )
  assert_not_eq(object_upload_cid(changed), object_upload_cid(request))
}

///|
test "GCS multipart replacement retains exact generation and metageneration" {
  let binding = upload_request_binding()
  let before = upload_existing(binding)
  assert_true(upload_request(binding, before) is Err(TargetExists))
  assert_true(
    upload_request(binding, before, overwrite=Some(false)) is Err(TargetExists),
  )
  let request = upload_request(binding, before, overwrite=Some(true)).unwrap()
  assert_eq(
    object_upload_path(request),
    "/upload/storage/v1/b/bucket/o?uploadType=multipart&ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2",
  )
  assert_eq(
    recheck_object_upload(binding, request, upload_existing(binding)),
    Ok(()),
  )
  assert_eq(
    recheck_object_upload(
      binding,
      request,
      upload_existing(binding, generation="9007199254740994"),
    ),
    Err(StaleObservation),
  )
  assert_eq(
    recheck_object_upload(
      binding,
      request,
      upload_existing(binding, metageneration="3"),
    ),
    Err(StaleObservation),
  )
  assert_eq(
    recheck_object_upload(binding, request, upload_absent(binding)),
    Err(StaleObservation),
  )
  let create = upload_request(binding, upload_absent(binding)).unwrap()
  assert_eq(
    recheck_object_upload(binding, create, before),
    Err(StaleObservation),
  )
}

///|
test "GCS multipart distinguishes original absence response and optional input presence" {
  let binding = upload_request_binding()
  let before = upload_absent(binding)
  let absent = upload_request(binding, before).unwrap()
  let explicit = upload_request(binding, before, overwrite=Some(false)).unwrap()
  assert_eq(
    object_upload_body_for(binding, absent).unwrap(),
    object_upload_body_for(binding, explicit).unwrap(),
  )
  assert_not_eq(object_upload_cid(absent), object_upload_cid(explicit))
  let another = admit_object_upload_observation(
    binding, "in/é%2F.bin", 404, b"{\"error\":\"other original\"}",
  ).unwrap()
  assert_not_eq(
    object_upload_cid(absent),
    object_upload_cid(upload_request(binding, another).unwrap()),
  )
  for status in [0, 201, 403, 410, 500] {
    assert_true(
      admit_object_upload_observation(binding, "in/é%2F.bin", status, b"{}").is_err(),
    )
  }
  for name in ["elsewhere/file", "in/file\r\n", ""] {
    assert_true(
      admit_object_upload_observation(binding, name, 404, b"{}").is_err(),
    )
  }
}

///|
test "GCS multipart validates original content and exact bounded body allocation" {
  let binding = upload_request_binding()
  let before = upload_absent(binding)
  assert_true(
    prepare_object_multipart_upload(
      binding,
      before,
      b"changed",
      "sha256:" + "f".repeat(64),
      "sha256:e9489f37fb3051e9efa1dc916004d7274e7b63975e3209708947267f2393a9be",
      "application/octet-stream",
      None,
      mutation_marker(),
    )
    is Err(ContentMismatch),
  )
  for maximum in [511, 510] {
    let exact = upload_request_binding(limits={
      ..upload_request_limits(),
      max_body_bytes: maximum,
    })
    let result = upload_request(exact, upload_absent(exact))
    assert_eq(result.is_ok(), maximum == 511)
    if maximum == 510 {
      assert_true(result is Err(CapacityExceeded))
    }
  }
  let short = upload_request_binding(limits={
    ..upload_request_limits(),
    max_content_bytes: 3,
  })
  assert_true(
    upload_request(short, upload_absent(short)) is Err(CapacityExceeded),
  )
  let short = upload_request_binding(limits={
    ..upload_request_limits(),
    max_identity_bytes: 1,
  })
  assert_true(
    upload_request(short, upload_absent(short)) is Err(CapacityExceeded),
  )
}

///|
test "GCS multipart never silently replaces the required resumable route" {
  let limit = 8 * 1024 * 1024 + 1
  let binding = upload_request_binding(limits={
    ..upload_request_limits(),
    max_content_bytes: limit,
  })
  assert_true(
    prepare_object_multipart_upload(
      binding,
      upload_absent(binding),
      Bytes::make(limit, 0),
      "sha256:" + "f".repeat(64),
      "sha256:" + "e".repeat(64),
      "application/octet-stream",
      None,
      mutation_marker(),
    )
    is Err(RequiresResumable),
  )
}

///|
test "GCS multipart uses the existing canonical media descriptor without normalizing opaque values" {
  let binding = upload_request_binding()
  let before = upload_absent(binding)
  for media in ["Text/Plain", "text/plain\r\nx: injected", "not media"] {
    assert_true(
      prepare_object_multipart_upload(
        binding,
        before,
        upload_binary(),
        "sha256:" + "f".repeat(64),
        "sha256:e9489f37fb3051e9efa1dc916004d7274e7b63975e3209708947267f2393a9be",
        media,
        None,
        mutation_marker(),
      )
      is Err(InvalidInput),
    )
  }
  let media = "text/plain; label=\"é\""
  let request = prepare_object_multipart_upload(
    binding,
    before,
    upload_binary(),
    "sha256:" + "f".repeat(64),
    "sha256:e9489f37fb3051e9efa1dc916004d7274e7b63975e3209708947267f2393a9be",
    media,
    None,
    mutation_marker(),
  ).unwrap()
  assert_true(
    object_upload_body_for(binding, request)
    .unwrap()
    .find(@utf8.encode("Content-Type: " + media + "\r\n").view())
    is Some(_),
  )
}

///|
test "GCS upload response data alone never supplies missing original correlation" {
  let binding = upload_request_binding()
  let request = upload_request(
    binding,
    upload_existing(binding),
    overwrite=Some(true),
  ).unwrap()
  let response = fn(
    marker : String,
    generation : String,
    meta : String,
    checksum : String,
  ) {
    admit_object_metadata(
      @utf8.encode(
        "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.bin\",\"generation\":\"" +
        generation +
        "\",\"metageneration\":\"" +
        meta +
        "\",\"size\":\"4\",\"contentType\":\"application/octet-stream\",\"crc32c\":\"" +
        checksum +
        "\",\"metadata\":{\"actql-request\":\"" +
        marker +
        "\"}}",
      ),
      "bucket",
      "in/",
      Some("in/é%2F.bin"),
      metadata_limits(),
    ).unwrap()
  }
  assert_true(
    object_upload_response_matches(
      binding,
      request,
      response(mutation_marker(), "9007199254740994", "1", "crxyRA=="),
    ),
  )
  for
    observed in [
      response(
        "foreign-or-copied-original-marker", "9007199254740994", "1", "crxyRA==",
      ),
      response(mutation_marker(), "9007199254740993", "1", "crxyRA=="),
      response(mutation_marker(), "9007199254740994", "2", "crxyRA=="),
      response(mutation_marker(), "9007199254740994", "1", "AAAAAA=="),
    ] {
    assert_false(object_upload_response_matches(binding, request, observed))
  }
  assert_false(
    object_upload_response_matches(
      upload_request_binding(),
      request,
      response(mutation_marker(), "9007199254740994", "1", "crxyRA=="),
    ),
  )
}
