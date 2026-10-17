///|
fn effect_patch_changes() -> Bytes {
  @utf8.encode(
    (
      #|{"content_type":"text/csv","metadata":{"$json":{"keep":"kept","new":"=é\r\n"}}}
    ),
  )
}

///|
test "GCS Effect JSON Value wire produces unchanged physical PATCH and exact authored facts" {
  let request = prepare_object_metadata_patch_value_wire(
    mutation_binding(),
    mutation_original(),
    effect_patch_changes(),
    mutation_marker(),
  ).unwrap()
  let raw = prepare_object_metadata_patch(
    mutation_binding(),
    mutation_original(),
    mutation_changes(),
    mutation_marker(),
  ).unwrap()
  assert_eq(object_mutation_body(request), object_mutation_body(raw))
  assert_eq(object_mutation_path(request), object_mutation_path(raw))
  assert_eq(
    object_mutation_cid(request),
    "sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179",
  )
  assert_eq(
    request.authored_changes,
    (
      #|{"content_type":"text/csv","metadata":{"$json":{"keep":"kept","new":"=é\r\n"}}}
    ),
  )
}

///|
test "GCS receives the actual Value Owner JSON envelope without changing data keys" {
  let contract = @contract.primitive(@contract.JsonType, nullable=false)
  let source = metadata_cursor(
    @utf8.encode(
      (
        #|{"$json":"user-key","é":"é\r\n","é":"distinct"}
      ),
    ),
    metadata_limits(),
  ).unwrap()
  let checked = @admitted.admit(contract, source, {
    max_nodes: 1000,
    max_depth: 12,
    max_text_bytes: 8192,
  }).unwrap()
  let output = @encode.writer(8192, 1000, 12)
  @admitted.emit_checked_wire_value(checked, output)
  let wire = @encode.finish(output)
  assert_eq(
    wire,
    (
      #|{"$json":{"$json":"user-key","é":"é\r\n","é":"distinct"}}
    ),
  )
  let request = prepare_object_metadata_patch_value_wire(
    mutation_binding(),
    mutation_original(),
    @utf8.encode("{\"metadata\":" + wire + "}"),
    mutation_marker(),
  ).unwrap()
  assert_true(request.body.contains("\"$json\":\"user-key\""))
  assert_true(request.body.contains("\"é\":\"é\\r\\n\""))
  assert_true(request.body.contains("\"é\":\"distinct\""))
  assert_true(!request.body.contains("\"metadata\":{\"$json\":{"))
}

///|
test "GCS Effect JSON wire distinguishes omission empty map SQL NULL and JSON null" {
  let binding = mutation_binding()
  for
    invalid in [
      (
        #|{"metadata":null}
      ),
      (
        #|{"metadata":{"$json":null}}
      ),
      (
        #|{"metadata":{}}
      ),
      (
        #|{"metadata":{"keep":"raw-map"}}
      ),
      (
        #|{"metadata":{"$json":{},"extra":"unknown"}}
      ),
      (
        #|{"metadata":{"$json":{"bad":1}}}
      ),
      (
        #|{"metadata":{"$json":[]}}
      ),
      (
        #|{"metadata":{"$json":{"nested":{"$json":"not-string"}}}}
      ),
    ] {
    assert_eq(
      check_object_metadata_patch_input(
        binding,
        @utf8.encode(invalid),
        mutation_marker(),
        true,
      ),
      Err(InvalidChanges),
    )
  }
  let missing = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    b"{}",
    mutation_marker(),
  ).unwrap()
  assert_eq(missing.authored_changes, "{}")
  assert_eq(
    object_mutation_after(missing).unwrap().metadata,
    Some([("drop", "old"), ("keep", "kept")]),
  )
  let empty = prepare_object_metadata_patch_value_wire(
    binding,
    mutation_original(),
    b"{\"metadata\":{\"$json\":{}}}",
    mutation_marker(),
  ).unwrap()
  assert_eq(object_mutation_after(empty).unwrap().metadata, Some([]))
  assert_eq(empty.authored_changes, "{\"metadata\":{\"$json\":{}}}")
  assert_true(empty.body.contains("\"drop\":null,\"keep\":null"))
}

///|
test "GCS static authored metadata refusal needs no target observation" {
  let binding = mutation_binding()
  for
    (wire, effect_wire) in [
      ("{\"metadata\":{\"actql-request\":\"collision\"}}", false),
      ("{\"metadata\":{\"$json\":{\"actql-request\":\"collision\"}}}", true),
    ] {
    assert_eq(
      check_object_metadata_patch_input(
        binding,
        @utf8.encode(wire),
        mutation_marker(),
        effect_wire,
      ),
      Err(ReservedMetadata),
    )
  }
  let limited = mutation_binding(limits={
    ..mutation_limits(),
    metadata: { ..metadata_limits(), max_metadata_entries: 0, },
  })
  assert_eq(
    check_object_metadata_patch_input(
      limited,
      effect_patch_changes(),
      mutation_marker(),
      true,
    ),
    Err(CapacityExceeded),
  )
  for effect_wire in [false, true] {
    assert_eq(
      check_object_metadata_patch_input(
        binding, b"{}", "invalid-marker", effect_wire,
      ),
      Err(InvalidBinding),
    )
    assert_eq(
      check_object_metadata_patch_input(
        binding,
        b"{\"storage_class\":\"COLDLINE\"}",
        mutation_marker(),
        effect_wire,
      ),
      Err(InvalidChanges),
    )
  }
}

///|
test "GCS raw JSON ABI remains independent from typed Effect metadata wire" {
  let binding = mutation_binding()
  let raw = prepare_object_metadata_patch(
    binding,
    mutation_original(),
    b"{\"metadata\":{\"$json\":\"ordinary-user-key\"}}",
    mutation_marker(),
  ).unwrap()
  assert_eq(
    raw.authored_changes,
    "{\"metadata\":{\"$json\":\"ordinary-user-key\"}}",
  )
  assert_eq(
    check_object_metadata_patch_input(
      binding,
      @utf8.encode(raw.authored_changes),
      mutation_marker(),
      true,
    ),
    Err(InvalidChanges),
  )
  assert_eq(
    check_object_metadata_patch_input(
      binding,
      effect_patch_changes(),
      mutation_marker(),
      false,
    ),
    Err(InvalidChanges),
  )
}
