///|
test "GCS original DELETE target has exact before and no invented after or value" {
  let binding = { ..mutation_binding(), kind: DeleteObject, }
  let request = prepare_object_delete(binding, mutation_original()).unwrap()
  let wire = object_delete_effect_target_json(binding, request, 8192).unwrap()
  let root = @json.parse(wire)
  let expected : Json = {
    "identity": "in/é%2F.csv",
    "versionCid": ("sha256:" + mutation_original().response_sha256).to_json(),
    "before": {
      "name": "in/é%2F.csv",
      "content_type": Json::null(),
      "metadata": { "$json": { "drop": "old", "keep": "kept" } },
    },
    "requestCid": object_mutation_cid(request).to_json(),
  }
  assert_eq(root, expected)
  assert_eq(request.body, "")
  assert_eq(request.authored_changes, "{}")
}

///|
test "GCS DELETE target refuses foreign binding PATCH purpose and insufficient projection" {
  let binding = { ..mutation_binding(), kind: DeleteObject, }
  let request = prepare_object_delete(binding, mutation_original()).unwrap()
  assert_eq(
    object_delete_effect_target_json({ ..binding, }, request, 8192),
    Err(ForeignBinding),
  )
  let patch = mutation_binding()
  let patch_request = mutation_outcome_request(patch)
  assert_eq(
    object_delete_effect_target_json(patch, patch_request, 8192),
    Err(InvalidBinding),
  )
  for limit in [0, 1, 64] {
    assert_eq(
      object_delete_effect_target_json(binding, request, limit),
      Err(CapacityExceeded),
    )
  }
}

///|
test "GCS DELETE target keeps NULL and empty user metadata distinct" {
  let binding = { ..mutation_binding(), kind: DeleteObject, }
  let absent = metadata_read(
    "{\"bucket\":\"bucket\",\"name\":\"in/a\",\"generation\":\"1\",\"metageneration\":\"2\",\"size\":\"0\"}",
  ).unwrap()
  let empty = metadata_read(
    "{\"bucket\":\"bucket\",\"name\":\"in/a\",\"generation\":\"1\",\"metageneration\":\"2\",\"size\":\"0\",\"metadata\":{\"actql-request\":\"old\"}}",
  ).unwrap()
  let absent_wire = object_delete_effect_target_json(
    binding,
    prepare_object_delete(binding, absent).unwrap(),
    8192,
  ).unwrap()
  let empty_wire = object_delete_effect_target_json(
    binding,
    prepare_object_delete(binding, empty).unwrap(),
    8192,
  ).unwrap()
  assert_true(absent_wire.contains("\"metadata\":null"))
  assert_true(empty_wire.contains("\"metadata\":{\"$json\":{}}"))
  assert_false(empty_wire.contains("actql-request"))
  assert_true(absent_wire != empty_wire)
}
