///|
test "GCS checked PATCH target Preview borrows the original response guard and typed fields" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  let wire = object_metadata_patch_effect_target_json(binding, request, 8192).unwrap()
  assert_eq(
    wire,
    (
      #|{"after":{"content_type":"text/csv","metadata":{"$json":{"keep":"kept","new":"=é\r\n"}}},"before":{"content_type":null,"metadata":{"$json":{"drop":"old","keep":"kept"}}},"identity":"in/é%2F.csv","protocol_behavior":"assign_original_request_marker:actql-request","requestCid":"sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179","value":{"content_type":"text/csv","metadata":{"$json":{"keep":"kept","new":"=é\r\n"}}},"versionCid":"sha256:a255da12181025e4a6ce594ad9ab3fb7a672ba774bf81b8277cba04294e94fed"}
    ),
  )
  assert_true(!wire.contains(mutation_marker()))
  assert_eq(request.marker, Some(mutation_marker()))
  assert_eq(
    object_metadata_patch_effect_target_json(
      binding,
      request,
      @utf8.encode(wire).length(),
    ),
    Ok(wire),
  )
  assert_eq(
    object_metadata_patch_effect_target_json(
      binding,
      request,
      @utf8.encode(wire).length() - 1,
    ),
    Err(CapacityExceeded),
  )
}

///|
test "GCS target Preview keeps changed-field omission missing metadata and empty metadata distinct" {
  let binding = mutation_binding()
  let missing = metadata_read(
    (
      #|{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"2","size":"7"}
    ),
  ).unwrap()
  let empty = metadata_read(
    (
      #|{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"2","size":"7","metadata":{}}
    ),
  ).unwrap()
  let changes = b"{\"metadata\":{\"$json\":{}}}"
  let missing_request = prepare_object_metadata_patch_value_wire(
    binding,
    missing,
    changes,
    mutation_marker(),
  ).unwrap()
  let empty_request = prepare_object_metadata_patch_value_wire(
    binding,
    empty,
    changes,
    mutation_marker(),
  ).unwrap()
  let missing_wire = object_metadata_patch_effect_target_json(
    binding, missing_request, 8192,
  ).unwrap()
  let empty_wire = object_metadata_patch_effect_target_json(
    binding, empty_request, 8192,
  ).unwrap()
  assert_true(missing_wire.contains("\"before\":{\"metadata\":null}"))
  assert_true(empty_wire.contains("\"before\":{\"metadata\":{\"$json\":{}}}"))
  assert_true(!missing_wire.contains("content_type"))
  let omitted = prepare_object_metadata_patch_value_wire(
    binding,
    empty,
    b"{}",
    mutation_marker(),
  ).unwrap()
  assert_true(
    object_metadata_patch_effect_target_json(binding, omitted, 8192)
    .unwrap()
    .contains("\"before\":{}"),
  )
}

///|
test "GCS target Preview refuses a foreign binding raw Json payload or DELETE purpose" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    object_metadata_patch_effect_target_json(mutation_binding(), request, 8192),
    Err(ForeignBinding),
  )
  let raw = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    object_metadata_patch_effect_target_json(binding, raw, 8192),
    Err(InvalidChanges),
  )
  let deleting = mutation_binding(kind=DeleteObject, permissions=[
    "storage.objects.delete",
  ])
  let request = prepare_object_delete(deleting, mutation_original()).unwrap()
  assert_eq(request.marker, None)
  assert_eq(
    object_metadata_patch_effect_target_json(deleting, request, 8192),
    Err(InvalidBinding),
  )
}
