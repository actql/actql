///|
test "UPDATE Mapping initialization prices original construction and keeps complete Mapping admission" {
  let original = update_mapping_declaration(update_mapping_form())
  let limits = delete_declaration_limits()
  let capacity = record_update_mapping_construction_capacity(
    original, 2, 64L, limits,
  ).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(capacity) > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) >
    @execution.execution_capacity_retained_bytes(capacity),
  )
  let mapping = prepare_record_update_mapping(
    original,
    "inquiries",
    update_mapping_sources(),
    "required",
    limits,
  ).unwrap()
  assert_true(record_update_mapping_matches_declaration(mapping, original))
  let wire = record_update_mapping(mapping).body
  assert_true(wire.contains("\"primary_identity\":\"$id\""))
  assert_true(wire.contains("\"Computed\""))
  assert_true(wire.contains("kintone:records:update"))
  assert_true(
    prepare_record_update_mapping(
      original,
      "inquiries",
      [{ target: "Computed", field: "value", null_behavior: "reject", }],
      "required",
      limits,
    )
    is Err(_),
  )
  println(
    "UPDATE Mapping retained=\{@execution.execution_capacity_retained_bytes(capacity)} peak=\{@execution.execution_capacity_execution_bytes(capacity)}",
  )
}

///|
test "UPDATE initialization quantity refuses invalid selected dimensions" {
  let original = update_mapping_declaration(update_mapping_form())
  let limits = delete_declaration_limits()
  assert_true(
    record_update_mapping_construction_capacity(original, 0, 64L, limits)
    is None,
  )
  assert_true(
    record_update_mapping_construction_capacity(
      original,
      limits.max_fields + 1,
      64L,
      limits,
    )
    is None,
  )
  assert_true(
    record_update_mapping_construction_capacity(original, 1, -1L, limits)
    is None,
  )
  assert_true(
    record_update_mapping_construction_capacity(
      original, 1, 9223372036854775807L, limits,
    )
    is None,
  )
  assert_true(
    record_update_mapping_construction_capacity(original, 1, 64L, {
      ..limits,
      max_depth: 0,
    })
    is None,
  )
  assert_true(
    record_update_installation_construction_capacity(0, 64, 12) is None,
  )
  assert_true(
    record_update_installation_construction_capacity(1, 0, 12) is None,
  )
  assert_true(
    record_update_installation_construction_capacity(1, 64, -1) is None,
  )
}

///|
test "UPDATE installed driver separates borrowed input workspace from newly retained text" {
  let original = record_update_installation_construction_capacity(3, 4096, 200).unwrap()
  let larger_borrow = record_update_installation_construction_capacity(
    3, 8192, 200,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(original),
    @execution.execution_capacity_retained_bytes(larger_borrow),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(larger_borrow) >
    @execution.execution_capacity_execution_bytes(original),
  )
  let larger_return = record_update_installation_construction_capacity(
    3, 8192, 400,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(larger_return) >
    @execution.execution_capacity_retained_bytes(larger_borrow),
  )
}
