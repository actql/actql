///|
fn schema_identity_limits() -> RelationSchemaIdentityLimits {
  { max_fields: 10, max_bytes: 1000, max_nodes: 100, max_depth: 10, }
}

///|
test "schema identity hashes the complete recursive field-contract map" {
  let text = @contract.string_contract(
    nullable=true,
    min_length=Some(1L),
    max_codepoints=Some(4L),
    max_utf8_bytes=Some(16L),
  ).unwrap()
  let decimals = @contract.array_contract(
    @contract.decimal_contract(9, 2, nullable=true).unwrap(),
    nullable=false,
    max_items=Some(3L),
  ).unwrap()
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("\ue000"), decimals),
      (@schema.Unqualified("😀"), text),
    ],
    max_fields=2,
    max_name_bytes=7,
  ).unwrap()
  let identity = identify_relation_schema(schema, schema_identity_limits()).unwrap()
  // Independent SHA-256 of the canonical UTF-8 field map. Its UTF-16 key
  // order places the surrogate pair for 😀 before U+E000.
  assert_eq(
    relation_schema_cid(identity),
    "sha256:e13e51f472cae3497095edf7f88922ebd7bf0b1c48f2bc31480b47406728c2e6",
  )
  assert_eq(relation_schema_usage(identity), (217, 16, 2))
}

///|
test "empty schema has an identity and every bound is enforced independently" {
  let empty = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let identity = identify_relation_schema(empty, schema_identity_limits()).unwrap()
  assert_eq(
    relation_schema_cid(identity),
    "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
  )
  assert_eq(relation_schema_usage(identity), (2, 1, 0))
  let source = export_fixture(capture_fixture())
  let owner = @lower.sequence_owner(source.completion.sequence)
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(owner),
    source.target,
  ).unwrap()
  assert_true(
    identify_relation_schema(schema, {
      ..schema_identity_limits(),
      max_fields: 1,
    })
    is Err(FieldLimit),
  )
  assert_true(
    identify_relation_schema(schema, {
      ..schema_identity_limits(),
      max_bytes: 78,
    })
    is Err(Encoding(_)),
  )
  for
    limits in [
      { ..schema_identity_limits(), max_fields: -1, },
      { ..schema_identity_limits(), max_bytes: -1, },
      { ..schema_identity_limits(), max_nodes: 0, },
      { ..schema_identity_limits(), max_depth: -1, },
    ] {
    assert_true(identify_relation_schema(schema, limits) is Err(InvalidLimits))
  }
}
