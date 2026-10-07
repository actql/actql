///|
fn table_mapping_schema(
  fields : Array[(@schema.FieldName, @contract.Contract, @schema.Presence)],
) -> (@schema.Schema, @execution.RelationSchemaIdentity) {
  let schema = @schema.from_presence_fields(
    fields,
    max_fields=1024,
    max_name_bytes=1024,
  ).unwrap()
  let identity = @execution.identify_relation_schema(schema, {
    max_fields: 1024,
    max_bytes: 65536,
    max_nodes: 16384,
    max_depth: 16,
  }).unwrap()
  (schema, identity)
}

///|
test "Table mapping fixes field IDs and presence from the complete schema" {
  // Independent preimages use number/string checked contracts and the
  // conditional wrapper; no product-generated expected mapping or CID.
  let (schema, identity) = table_mapping_schema([
    (
      @schema.Unqualified("s"),
      @contract.primitive(@contract.StringType, nullable=true),
      @schema.Required,
    ),
    (
      @schema.Unqualified("p"),
      @contract.primitive(@contract.NumberType, nullable=true),
      @schema.Conditional,
    ),
    (
      @schema.Unqualified("id"),
      @contract.primitive(@contract.NumberType, nullable=false),
      @schema.Required,
    ),
  ])
  assert_eq(
    @execution.relation_schema_cid(identity),
    "sha256:0cb67e87463a39d7a9f6e55dcc7cda1a00e18beb88790f6c793f0c2547ecd579",
  )
  let mapping = issue_table_storage_mapping_schema(
    schema, identity, 8192, 256, 8,
  ).unwrap()
  assert_eq(
    mapping.cid,
    "sha256:dc2091f5f63460997f1f0adb3b5e99d8f2e5d0e6a61adbcbd9395e8958213505",
  )
  assert_eq(
    table_storage_mapping_schema_cid(mapping),
    @execution.relation_schema_cid(identity),
  )
  let saved = admit_table_storage_mapping(mapping.wire, 8192, 256, 8).unwrap()
  assert_eq(
    saved.cid,
    "sha256:dc2091f5f63460997f1f0adb3b5e99d8f2e5d0e6a61adbcbd9395e8958213505",
  )
  assert_eq(saved.wire, mapping.wire)
  assert_eq(
    mapping.wire,
    "{\"columns\":[{\"name\":\"id\",\"nullable\":false,\"physical_type\":\"double\",\"presence\":\"required\",\"presence_field_id\":null,\"value_field_id\":1},{\"name\":\"p\",\"nullable\":true,\"physical_type\":\"double\",\"presence\":\"conditional\",\"presence_field_id\":3,\"value_field_id\":2},{\"name\":\"s\",\"nullable\":true,\"physical_type\":\"string\",\"presence\":\"required\",\"presence_field_id\":null,\"value_field_id\":4}],\"iceberg_format_version\":2,\"mapping_cid\":\"sha256:dc2091f5f63460997f1f0adb3b5e99d8f2e5d0e6a61adbcbd9395e8958213505\",\"schema_cid\":\"sha256:0cb67e87463a39d7a9f6e55dcc7cda1a00e18beb88790f6c793f0c2547ecd579\",\"version\":\"actql-table-storage-mapping/0.1\"}",
  )
  assert_true(
    issue_table_storage_mapping_schema(schema, identity, 8, 256, 8)
    is Err(Encoding),
  )
  assert_true(
    issue_table_storage_mapping_schema(schema, identity, 8192, 1, 8)
    is Err(Encoding),
  )
}

///|
test "saved Table mapping rejects malformed companions and noncanonical field IDs" {
  let (schema, identity) = table_mapping_schema([
    (
      @schema.Unqualified("id"),
      @contract.primitive(@contract.NumberType, nullable=false),
      @schema.Required,
    ),
    (
      @schema.Unqualified("p"),
      @contract.primitive(@contract.NumberType, nullable=true),
      @schema.Conditional,
    ),
  ])
  let mapping = issue_table_storage_mapping_schema(
    schema, identity, 8192, 256, 8,
  ).unwrap()
  assert_true(
    admit_table_storage_mapping(mapping.wire + " ", 8192, 256, 8)
    is Err(SavedMapping(InvalidWire)),
  )
  for
    (before, after) in [
      ("\"value_field_id\":1", "\"value_field_id\":9"),
      ("\"presence_field_id\":3", "\"presence_field_id\":null"),
      ("\"presence_field_id\":3", "\"presence_field_id\":4"),
      ("\"presence_field_id\":3,", ""),
      ("\"nullable\":true", "\"nullable\":null"),
      ("\"iceberg_format_version\":2", "\"iceberg_format_version\":1"),
      ("\"schema_cid\":", "\"extra\":true,\"schema_cid\":"),
    ] {
    let bad = table_test_reseal(
      mapping.wire.replace(old=before, new=after),
      "mapping_cid",
    )
    assert_true(
      admit_table_storage_mapping(bad, 8192, 256, 8)
      is Err(SavedMapping(InvalidShape)),
    )
  }
  let bad_type = table_test_reseal(
    mapping.wire.replace(old="\"double\"", new="\"nested\""),
    "mapping_cid",
  )
  assert_true(
    admit_table_storage_mapping(bad_type, 8192, 256, 8)
    is Err(UnsupportedType("id")),
  )
  let collision = table_test_reseal(
    mapping.wire.replace(old="\"name\":\"p\"", new="\"name\":\"ID\""),
    "mapping_cid",
  )
  assert_true(
    admit_table_storage_mapping(collision, 8192, 256, 8)
    is Err(ColumnCollision("ID")),
  )
}

///|
test "Table mapping refuses unsupported declarations regardless of actual rows" {
  for typ in [@contract.DateType, @contract.TimestampType, @contract.JsonType] {
    let (schema, identity) = table_mapping_schema([
      (
        @schema.Unqualified("p"),
        @contract.primitive(typ, nullable=true),
        @schema.Conditional,
      ),
    ])
    assert_true(
      issue_table_storage_mapping_schema(schema, identity, 8192, 256, 8)
      is Err(UnsupportedType("p")),
    )
  }
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let nested = @contract.object_contract(
    [("n", number)],
    nullable=false,
    max_fields=1,
    max_name_bytes=16,
  ).unwrap()
  for typ in [nested, @contract.array_contract(number, nullable=false).unwrap()] {
    let (schema, identity) = table_mapping_schema([
      (@schema.Unqualified("p"), typ, @schema.Conditional),
    ])
    assert_true(
      issue_table_storage_mapping_schema(schema, identity, 8192, 256, 8)
      is Err(UnsupportedType("p")),
    )
  }
  let (schema, identity) = table_mapping_schema([])
  assert_true(
    issue_table_storage_mapping_schema(schema, identity, 8192, 256, 8)
    is Err(UnsupportedColumnCount),
  )
}

///|
test "Table mapping preserves nullable independently of absence and reserves companion names" {
  let (schema, identity) = table_mapping_schema([
    (
      @schema.Unqualified("flag"),
      @contract.primitive(@contract.BooleanType, nullable=false),
      @schema.Conditional,
    ),
  ])
  let mapping = issue_table_storage_mapping_schema(
    schema, identity, 8192, 256, 8,
  ).unwrap()
  assert_true(
    mapping.wire.contains(
      "\"nullable\":false,\"physical_type\":\"boolean\",\"presence\":\"conditional\",\"presence_field_id\":2,\"value_field_id\":1",
    ),
  )
  let (schema, identity) = table_mapping_schema([
    (
      @schema.Unqualified("__ACTQL_PRESENCE_2"),
      @contract.primitive(@contract.BooleanType, nullable=false),
      @schema.Required,
    ),
  ])
  assert_true(
    issue_table_storage_mapping_schema(schema, identity, 8192, 256, 8)
    is Err(ColumnCollision("__ACTQL_PRESENCE_2")),
  )
  let (schema, identity) = table_mapping_schema([
    (
      @schema.Unqualified("id"),
      @contract.primitive(@contract.NumberType, nullable=false),
      @schema.Required,
    ),
    (
      @schema.Unqualified("ID"),
      @contract.primitive(@contract.NumberType, nullable=false),
      @schema.Required,
    ),
  ])
  assert_true(
    issue_table_storage_mapping_schema(schema, identity, 8192, 256, 8)
    is Err(ColumnCollision("id")),
  )
}
