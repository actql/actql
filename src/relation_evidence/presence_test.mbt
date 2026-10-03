///|
test "conditional presence is not key evidence even for nonnullable values" {
  let schema = @row.from_presence_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        Required,
      ),
      (
        Unqualified("p"),
        @contract.primitive(NumberType, nullable=false),
        Conditional,
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let rows = @carrier.relation(@carrier.typed_rows(schema))
  assert_true(
    @relation_evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
      max_fields: 1,
      max_name_bytes: 2,
    })
    is Ok(_),
  )
  assert_true(
    @relation_evidence.declare_primary_key(cursor("[\"p\"]"), rows, {
      max_fields: 1,
      max_name_bytes: 1,
    })
    is Err({ kind: InvalidKeyType("p"), .. }),
  )
  let sparse = @row.from_conditional_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        @row.FieldPresence::Required,
      ),
      (
        Unqualified("p"),
        @contract.primitive(NumberType, nullable=false),
        @row.FieldPresence::Conditional,
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let sparse_rows = @carrier.relation(@carrier.conditional_rows(sparse))
  assert_true(
    @relation_evidence.declare_primary_key(cursor("[\"id\"]"), sparse_rows, {
      max_fields: 1,
      max_name_bytes: 2,
    })
    is Ok(_),
  )
  assert_true(
    @relation_evidence.declare_primary_key(cursor("[\"p\"]"), sparse_rows, {
      max_fields: 1,
      max_name_bytes: 1,
    })
    is Err({ kind: InvalidKeyType("p"), .. }),
  )
}
