///|
fn mutation_limits() -> ObjectRequestLimits {
  {
    metadata: metadata_limits(),
    max_path_bytes: 4096,
    max_body_bytes: 8192,
    max_identity_bytes: 16384,
  }
}

///|
fn mutation_binding(
  kind? : ObjectMutationKind = PatchMetadata,
  permissions? : Array[String] = ["storage.objects.update"],
  limits? : ObjectRequestLimits = mutation_limits(),
) -> ObjectMutationBinding {
  prepare_object_mutation_binding(
    kind,
    "bucket",
    "in/",
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    permissions,
    limits,
  ).unwrap()
}

///|
fn mutation_original(metageneration? : String = "2") -> ObjectMetadata {
  metadata_read(
    "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.csv\",\"generation\":\"9007199254740993\",\"metageneration\":\"" +
    metageneration +
    "\",\"size\":\"7\",\"metadata\":{\"drop\":\"old\",\"keep\":\"kept\",\"actql-request\":\"old\"}}",
  ).unwrap()
}

///|
fn mutation_changes() -> Bytes {
  @utf8.encode(
    "{\"content_type\":\"text/csv\",\"metadata\":{\"keep\":\"kept\",\"new\":\"=é\\r\\n\"}}",
  )
}

///|
fn mutation_marker() -> String {
  "sha256:" + "d".repeat(64)
}

///|
// Independently calculated with Node crypto/JSON, not the product encoder.
test "GCS conditional metadata PATCH keeps exact bytes preconditions and request CID" {
  let binding = mutation_binding()
  let original = mutation_original()
  let request = prepare_object_metadata_patch(
    binding,
    original,
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(object_mutation_method(request), "PATCH")
  assert_eq(
    object_mutation_path(request),
    "/storage/v1/b/bucket/o/in%2Fe%CC%81%252F.csv?generation=9007199254740993&ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2",
  )
  assert_eq(
    object_mutation_body(request),
    "{\"contentType\":\"text/csv\",\"metadata\":{\"actql-request\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"drop\":null,\"keep\":\"kept\",\"new\":\"=é\\r\\n\"}}",
  )
  assert_eq(
    object_mutation_cid(request),
    "sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179",
  )
  assert_eq(recheck_object_mutation(binding, request, original), Ok(()))
}

///|
test "GCS same physical bytes under different permissions cannot substitute original binding" {
  let allowed = ["storage.objects.update"]
  let binding = mutation_binding(permissions=allowed)
  allowed[0] = "changed.after.binding"
  let request = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    object_mutation_cid(request),
    "sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179",
  )
  let foreign = mutation_binding(permissions=["different.permission"])
  let changed = prepare_object_metadata_patch(
    foreign,
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(object_mutation_path(changed), object_mutation_path(request))
  assert_eq(object_mutation_body(changed), object_mutation_body(request))
  assert_not_eq(object_mutation_cid(changed), object_mutation_cid(request))
  assert_eq(
    recheck_object_mutation(foreign, request, mutation_original()),
    Err(ForeignBinding),
  )
  assert_eq(
    recheck_object_mutation(mutation_binding(), request, mutation_original()),
    Err(ForeignBinding),
  )
}

///|
test "GCS apply refuses a changed original version rather than adopting current head" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    recheck_object_mutation(
      binding,
      request,
      mutation_original(metageneration="3"),
    ),
    Err(StaleObservation),
  )
  let changed = prepare_object_metadata_patch(
    binding,
    mutation_original(metageneration="3"),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_not_eq(object_mutation_cid(changed), object_mutation_cid(request))
  let other = admit_object_metadata(
    @utf8.encode(
      "{\"bucket\":\"foreign\",\"name\":\"in/file\",\"generation\":\"1\",\"metageneration\":\"1\",\"size\":\"0\"}",
    ),
    "foreign",
    "in/",
    None,
    metadata_limits(),
  ).unwrap()
  assert_true(
    prepare_object_metadata_patch(
      binding,
      other,
      mutation_changes(),
      mutation_marker(),
    )
    is Err(StaleObservation),
  )
}

///|
test "GCS metadata patch retains omitted keys but clears a supplied whole empty map" {
  let binding = mutation_binding()
  let keep = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    b"{}",
    mutation_marker(),
  ).unwrap()
  assert_eq(
    object_mutation_body(keep),
    "{\"metadata\":{\"actql-request\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}}",
  )
  let clear = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    b"{\"metadata\":{}}",
    mutation_marker(),
  ).unwrap()
  assert_eq(
    object_mutation_body(clear),
    "{\"metadata\":{\"actql-request\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"drop\":null,\"keep\":null}}",
  )
  for
    wire in [
      b"{\"metadata\":null}", b"{\"metadata\":{\"key\":null}}", b"{\"content_type\":null}",
      b"{\"content_type\":\"x\",\"content_type\":\"y\"}", b"{\"unknown\":true}",
    ] {
    assert_true(
      prepare_object_metadata_patch(
        binding,
        mutation_original(),
        wire,
        mutation_marker(),
      )
      is Err(InvalidChanges),
    )
  }
  assert_true(
    prepare_object_metadata_patch(
      binding,
      mutation_original(),
      b"{\"metadata\":{\"actql-request\":\"foreign\"}}",
      mutation_marker(),
    )
    is Err(ReservedMetadata),
  )
}

///|
test "GCS request output enforces exact body and identity capacities without growing ceilings" {
  let limits = {
    ..mutation_limits(),
    max_body_bytes: 172,
    max_identity_bytes: 775,
  }
  assert_true(
    prepare_object_metadata_patch(
      mutation_binding(limits~),
      mutation_original(),
      mutation_changes(),
      mutation_marker(),
    )
    is Ok(_),
  )
  assert_true(
    prepare_object_metadata_patch(
      mutation_binding(limits={ ..limits, max_body_bytes: 171, }),
      mutation_original(),
      mutation_changes(),
      mutation_marker(),
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_object_metadata_patch(
      mutation_binding(limits={ ..limits, max_identity_bytes: 774, }),
      mutation_original(),
      mutation_changes(),
      mutation_marker(),
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_object_metadata_patch(
      mutation_binding(limits={ ..limits, max_path_bytes: 20, }),
      mutation_original(),
      mutation_changes(),
      mutation_marker(),
    )
    is Err(CapacityExceeded),
  )
}

///|
test "GCS delete is bodyless conditional material and has no metadata marker" {
  let binding = mutation_binding(kind=DeleteObject, permissions=[
    "storage.objects.delete",
  ])
  let request = prepare_object_delete(binding, mutation_original()).unwrap()
  assert_eq(object_mutation_method(request), "DELETE")
  assert_eq(object_mutation_body(request), "")
  assert_true(
    object_mutation_path(request).contains(
      "ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2",
    ),
  )
  assert_true(
    prepare_object_metadata_patch(
      binding,
      mutation_original(),
      mutation_changes(),
      mutation_marker(),
    )
    is Err(InvalidBinding),
  )
  assert_true(
    prepare_object_delete(mutation_binding(), mutation_original())
    is Err(InvalidBinding),
  )
}

///|
test "GCS request Preview preserves user removals and declares fresh private marker assignment" {
  let request = prepare_object_metadata_patch(
    mutation_binding(),
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    object_mutation_before(request).metadata,
    Some([("drop", "old"), ("keep", "kept")]),
  )
  let after = object_mutation_after(request).unwrap()
  assert_eq(after.metadata, Some([("keep", "kept"), ("new", "=é\r\n")]))
  assert_eq(after.content_type, Some("text/csv"))
  assert_eq(
    object_mutation_protocol_behavior(request),
    Some("assign_original_request_marker:actql-request"),
  )
  after.metadata.unwrap()[0] = ("changed", "detached")
  assert_eq(
    object_mutation_after(request).unwrap().metadata.unwrap()[0],
    ("keep", "kept"),
  )
  assert_eq(
    request.original.fields.metadata.unwrap()[2],
    ("actql-request", "old"),
  )
  assert_true(object_mutation_body(request).contains(mutation_marker()))
  assert_true(!object_mutation_body(request).contains("\"old\""))
  let deletion = prepare_object_delete(
    mutation_binding(kind=DeleteObject),
    mutation_original(),
  ).unwrap()
  assert_eq(object_mutation_after(deletion), None)
  assert_eq(object_mutation_protocol_behavior(deletion), None)
}

///|
test "GCS reserved collision is exact and replacement preserves other opaque keys" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    @utf8.encode(
      "{\"metadata\":{\"Actql-request\":\"case\",\"actql-request-extra\":\"prefix\",\"é\":\"decomposed\",\"é\":\"composed\"}}",
    ),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    object_mutation_after(request).unwrap().metadata,
    Some([
      ("Actql-request", "case"),
      ("actql-request-extra", "prefix"),
      ("é", "decomposed"),
      ("é", "composed"),
    ]),
  )
  assert_true(object_mutation_body(request).contains("\"drop\":null"))
  assert_true(object_mutation_body(request).contains("\"keep\":null"))
  assert_true(
    prepare_object_metadata_patch(
      binding,
      mutation_original(),
      b"{\"metadata\":{\"actql-request\":\"same-or-foreign\"}}",
      mutation_marker(),
    )
    is Err(ReservedMetadata),
  )
  // This is only the before-send version guard, not reconciliation or an apply
  // classifier. Its success emits no receipt or applied outcome. A copied
  // marker cannot bypass the original metageneration check.
  let copied = metadata_read(
    metadata_wire(
      extra=",\"metadata\":{\"actql-request\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}",
    ),
  ).unwrap()
  assert_eq(recheck_object_mutation(binding, request, copied), Ok(()))
  assert_eq(
    recheck_object_mutation(
      binding,
      request,
      mutation_original(metageneration="3"),
    ),
    Err(StaleObservation),
  )
}
