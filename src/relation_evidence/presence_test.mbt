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
}
