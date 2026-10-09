///|
// Independently sealed canonical preimage, with no Iceberg field IDs/types.
fn independent_storage_mapping_wire() -> String {
  "{\"mapping_cid\":\"sha256:312298dfb3ae7e4ca0e8397b48b75c52fb2bb3f257d13a716083ffd70bd85efd\",\"schema_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"independent-storage-mapping/0.1\",\"writer_contract\":\"not-iceberg\"}"
}

///|
test "shared storage reference binds exact content without interpreting backend fields" {
  for
    kind in [
      @carrier.RelationKind,
      @carrier.GraphKind,
      @carrier.VectorsKind,
      @carrier.EventsKind,
    ] {
    let reference = admit_storage_mapping_reference(
      kind,
      independent_storage_mapping_wire(),
      8192,
      256,
      8,
    ).unwrap()
    assert_eq(storage_mapping_reference_kind(reference), kind)
    assert_eq(
      storage_mapping_reference_cid(reference),
      "sha256:312298dfb3ae7e4ca0e8397b48b75c52fb2bb3f257d13a716083ffd70bd85efd",
    )
    assert_eq(
      storage_mapping_reference_schema_cid(reference),
      "sha256:" + "1".repeat(64),
    )
    assert_eq(
      storage_mapping_reference_json(reference),
      independent_storage_mapping_wire(),
    )
  }
  // Reference admission makes no claim that these kinds have physical writers.
  assert_true(
    admit_storage_mapping_reference(
      @carrier.RelationKind,
      independent_storage_mapping_wire() + " ",
      8192,
      256,
      8,
    )
    is Err(InvalidWire),
  )
  assert_true(
    admit_storage_mapping_reference(
      @carrier.RelationKind,
      independent_storage_mapping_wire().replace(
        old="not-iceberg",
        new="changed",
      ),
      8192,
      256,
      8,
    )
    is Err(InvalidIdentity),
  )
  assert_true(
    admit_storage_mapping_reference(
      @carrier.RelationKind,
      independent_storage_mapping_wire(),
      8192,
      0,
      8,
    )
    is Err(InvalidLimits),
  )
}

///|
test "Relation Table input cannot bind another Carrier kind through the same mapping CID" {
  let scope = @request_scope.prepare_logical_request_scope(
    "sha256:" + "e".repeat(64),
    "storage-reference",
    128,
  ).unwrap()
  let operation_wire = table_test_reseal(
    table_vector_create()
    .replace(
      old="\"logical_request_scope_cid\":\"sha256:" + "1".repeat(64),
      new="\"logical_request_scope_cid\":\"" +
        @request_scope.logical_request_scope_cid(scope),
    )
    .replace(
      old="\"schema_cid\":\"sha256:" + "6".repeat(64),
      new="\"schema_cid\":\"sha256:" + "1".repeat(64),
    )
    .replace(
      old="\"storage_mapping_cid\":\"sha256:" + "7".repeat(64),
      new="\"storage_mapping_cid\":\"sha256:312298dfb3ae7e4ca0e8397b48b75c52fb2bb3f257d13a716083ffd70bd85efd",
    ),
    "request_cid",
  )
  let operation = admit_table_operation(operation_wire, 8192, 256, 8).unwrap()
  for
    kind in [
      @carrier.RelationKind,
      @carrier.GraphKind,
      @carrier.VectorsKind,
      @carrier.EventsKind,
    ] {
    let reference = admit_storage_mapping_reference(
      kind,
      independent_storage_mapping_wire(),
      8192,
      256,
      8,
    ).unwrap()
    assert_eq(
      table_operation_matches_input(
        operation,
        scope,
        "sha256:" + "2".repeat(64),
        "sha256:" + "4".repeat(64),
        @carrier.RelationKind,
        "sha256:" + "5".repeat(64),
        reference,
        "sha256:" + "8".repeat(64),
      ),
      kind == @carrier.RelationKind,
    )
    let name = match kind {
      @carrier.RelationKind => "relation"
      @carrier.GraphKind => "graph"
      @carrier.VectorsKind => "vectors"
      @carrier.EventsKind => "events"
    }
    let same_kind = admit_table_operation(
      table_test_reseal(
        operation_wire.replace(
          old="\"kind\":\"relation\"",
          new="\"kind\":\"" + name + "\"",
        ),
        "request_cid",
      ),
      8192,
      256,
      8,
    ).unwrap()
    assert_true(
      table_operation_matches_input(
        same_kind,
        scope,
        "sha256:" + "2".repeat(64),
        "sha256:" + "4".repeat(64),
        kind,
        "sha256:" + "5".repeat(64),
        reference,
        "sha256:" + "8".repeat(64),
      ),
    )
    // This proves shared content correspondence, not a captured input owner,
    // installed writer, authorization or an implemented Graph/Vector/Event I/O.
  }
}
