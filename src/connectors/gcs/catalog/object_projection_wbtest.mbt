///|
test "GCS logical JSON keeps exact integer text and excludes only private metadata" {
  let original = mutation_original()
  let wire = object_metadata_logical_json(original, metadata_limits()).unwrap()
  assert_true(wire.contains("\"generation\":\"9007199254740993\""))
  assert_true(wire.contains("\"metageneration\":\"2\""))
  assert_true(wire.contains("\"name\":\"in/é%2F.csv\""))
  assert_true(
    wire.contains("\"metadata\":{\"drop\":\"old\",\"keep\":\"kept\"}"),
  )
  assert_true(!wire.contains("actql-request"))
  assert_true(
    object_metadata_logical_json(original, {
      ..metadata_limits(),
      max_metadata_entries: 2,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    object_metadata_logical_json(original, {
      ..metadata_limits(),
      max_bytes: 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "GCS physical projection borrows the same request and preserves authored changes" {
  let binding = mutation_binding()
  let request = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(
    object_mutation_changes_json(binding, request),
    Ok(
      "{\"content_type\":\"text/csv\",\"metadata\":{\"keep\":\"kept\",\"new\":\"=é\\r\\n\"}}",
    ),
  )
  assert_eq(
    object_mutation_body_for(binding, request),
    Ok(object_mutation_body(request)),
  )
  let wire = object_mutation_projection_json(binding, request, 8192).unwrap()
  assert_true(wire.contains("\"operation\":\"gcs:object:metadata:update\""))
  assert_true(wire.contains("\"has_body\":true"))
  assert_true(wire.contains("\"original_response_sha256\":"))
  assert_true(!wire.contains(mutation_marker()))
  assert_true(
    object_mutation_projection_json(binding, request, 1)
    is Err(CapacityExceeded),
  )
  assert_true(
    object_mutation_projection_json(mutation_binding(), request, 8192)
    is Err(ForeignBinding),
  )
  assert_true(
    object_mutation_changes_json(mutation_binding(), request)
    is Err(ForeignBinding),
  )
}

///|
test "GCS delete projection remains bodyless without inventing an applied state" {
  let binding = mutation_binding(kind=DeleteObject)
  let request = prepare_object_delete(binding, mutation_original()).unwrap()
  let wire = object_mutation_projection_json(binding, request, 8192).unwrap()
  assert_true(wire.contains("\"operation\":\"gcs:object:delete\""))
  assert_true(wire.contains("\"has_body\":false"))
  assert_true(wire.contains("\"after\":null"))
  assert_true(wire.contains("\"protocol_behavior\":null"))
  assert_eq(object_mutation_changes_json(binding, request), Ok("{}"))
  assert_eq(object_mutation_body_for(binding, request), Ok(""))
}
