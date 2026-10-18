///|
fn recovery_response() -> Bytes {
  // Original, non-reserialized UTF-8 fixture including exact NFD data.
  @utf8.encode(
    "{\"bucket\":\"bucket\",\"name\":\"in/é%2F.csv\",\"generation\":\"9007199254740993\",\"metageneration\":\"2\",\"size\":\"7\",\"metadata\":{\"drop\":\"old\",\"keep\":\"kept\",\"actql-request\":\"old\"}}",
  )
}

///|
fn recovery_restore(
  binding : ObjectMutationBinding,
  request : ObjectMutationRequest,
  response? : Bytes = recovery_response(),
  digest? : String = @sha.hex(recovery_response()),
  name? : String = "in/é%2F.csv",
  status? : Int = 200,
  headers? : Array[(String, String)] = [],
  changes? : Bytes = effect_patch_changes(),
  body? : String = request.body,
  cid? : String = request.cid,
) -> Result[ObjectMutationRequest, ObjectRequestIssue] {
  restore_object_mutation_value_wire(
    binding, name, status, headers, response, digest, changes, body, cid,
  )
}

///|
test "GCS restore retains original raw guard exact conditional bytes and Value intent" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  let restored = recovery_restore(binding, request).unwrap()
  assert_eq(
    restored.cid,
    "sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179",
  )
  assert_eq(restored.path, request.path)
  assert_eq(restored.body, request.body)
  assert_eq(restored.authored_changes, request.authored_changes)
  assert_eq(restored.original.response_sha256, request.original.response_sha256)
  assert_eq(
    metadata_fields_json(object_mutation_after(restored).unwrap()),
    metadata_fields_json(object_mutation_after(request).unwrap()),
  )
  assert_true(physical_equal(restored.binding, binding))
  assert_false(physical_equal(restored, request))
}

///|
test "GCS restore refuses same-field raw replacement independently of equal request CID" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  let replacement = @utf8.encode(" " + @utf8.decode(recovery_response()))
  let changed = admit_object_metadata(
    replacement,
    "bucket",
    "in/",
    Some("in/é%2F.csv"),
    metadata_limits(),
  ).unwrap()
  let equal_request = prepare_object_metadata_patch_value_wire(
    binding,
    changed,
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(equal_request.cid, request.cid)
  assert_true(changed.response_sha256 != request.original.response_sha256)
  assert_true(
    recovery_restore(binding, request, response=replacement)
    is Err(StaleObservation),
  )
  assert_true(
    recovery_restore(binding, request, digest="0".repeat(64))
    is Err(StaleObservation),
  )
}

///|
test "GCS restore binds original name scope purpose and new local binding not equal pointer" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  let new_binding = mutation_binding()
  let restored = recovery_restore(new_binding, request).unwrap()
  assert_eq(
    admit_object_mutation_request(new_binding, request),
    Err(ForeignBinding),
  )
  assert_eq(admit_object_mutation_request(new_binding, restored), Ok(()))
  assert_true(
    recovery_restore(binding, request, name="in/other") is Err(ForeignBinding),
  )
  assert_true(
    recovery_restore(mutation_binding(kind=DeleteObject), request)
    is Err(InvalidChanges),
  )
  assert_true(
    recovery_restore(mutation_binding(permissions=["other"]), request)
    is Err(InvalidChanges),
  )
}

///|
test "GCS restore never canonicalizes substituted intent body or marker into acceptance" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  assert_true(
    recovery_restore(binding, request, changes=mutation_changes())
    is Err(InvalidChanges),
  )
  assert_true(
    recovery_restore(
      binding,
      request,
      changes=@utf8.encode(" " + request.authored_changes),
    )
    is Err(InvalidChanges),
  )
  assert_true(
    recovery_restore(binding, request, body=" " + request.body)
    is Err(InvalidChanges),
  )
  assert_true(
    recovery_restore(
      binding,
      request,
      body=request.body.replace(
        old=mutation_marker(),
        new="sha256:" + "e".repeat(64),
      ),
    )
    is Err(InvalidChanges),
  )
  assert_true(
    recovery_restore(binding, request, cid="sha256:" + "0".repeat(64))
    is Err(InvalidChanges),
  )
}

///|
test "GCS restore preserves DELETE absence and NULL-to-empty PATCH behavior without permission" {
  let binding = mutation_binding(kind=DeleteObject)
  let request = prepare_object_delete(binding, mutation_original()).unwrap()
  let restored = recovery_restore(binding, request, changes=b"{}").unwrap()
  assert_eq(restored.verb, "DELETE")
  assert_eq(restored.body, "")
  assert_true(restored.logical_after is None)
  assert_true(
    recovery_restore(binding, request, changes=b" {}") is Err(InvalidChanges),
  )
  let raw = b"{\"bucket\":\"bucket\",\"name\":\"in/a\",\"generation\":\"1\",\"metageneration\":\"2\",\"size\":\"0\"}"
  let before = admit_object_metadata(
    raw,
    "bucket",
    "in/",
    Some("in/a"),
    metadata_limits(),
  ).unwrap()
  let patch = prepare_object_metadata_patch_value_wire(
    mutation_binding(),
    before,
    b"{}",
    mutation_marker(),
  ).unwrap()
  let restored = recovery_restore(
    patch.binding,
    patch,
    response=raw,
    digest=@sha.hex(raw),
    name="in/a",
    changes=b"{}",
  ).unwrap()
  assert_eq(restored.original.fields.metadata, None)
  assert_eq(restored.logical_after.unwrap().metadata, Some([]))
  assert_eq(restored.authored_changes, "{}")
}

///|
test "GCS restore rejects bounds and malformed raw guard material before reinterpretation" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  for digest in ["", "0".repeat(65), "A".repeat(64)] {
    assert_true(
      recovery_restore(binding, request, digest~) is Err(InvalidBinding),
    )
  }
  assert_true(
    recovery_restore(
      binding,
      request,
      response=@utf8.encode("x".repeat(metadata_limits().max_bytes + 1)),
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    recovery_restore(
      binding,
      request,
      body="x".repeat(mutation_limits().max_body_bytes + 1),
    )
    is Err(CapacityExceeded),
  )
  let malformed = b"{\"bucket\":\"bucket\",\"bucket\":\"bucket\"}"
  assert_true(
    recovery_restore(binding, request, status=404) is Err(InvalidChanges),
  )
  for
    headers in [
      [("content-encoding", "gzip")],
      [("x-goog-generation", "9007199254740992")],
      [("x-goog-metageneration", "3")],
    ] {
    assert_true(
      recovery_restore(binding, request, headers~) is Err(InvalidChanges),
    )
  }
  assert_true(
    recovery_restore(
      binding,
      request,
      response=malformed,
      digest=@sha.hex(malformed),
    )
    is Err(InvalidChanges),
  )
}
