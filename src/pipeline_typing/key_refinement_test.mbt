///|
test "exact field copies retain non-null key evidence beneath nullable schemas" {
  let number = @contract.primitive(NumberType, nullable=false)
  let left = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_fields(
        [(Unqualified("id"), number)],
        max_fields=1,
        max_name_bytes=2,
      ).unwrap(),
    ),
  )
  let right = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_fields(
        [(Unqualified("id"), @contract.with_nullability(number, true))],
        max_fields=1,
        max_name_bytes=2,
      ).unwrap(),
    ),
  )
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), left, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for
    copy in [
      "{\"select\":[{\"alias\":\"id\"}]}", "{\"rename\":{\"id\":\"alias\"}}", "{\"derive\":{\"alias\":{\"field\":\"id\"}}}",
    ] {
    let source = cursor(
      "[{\"except\":{\"with\":\"r\",\"duplicates\":\"all\"},\"from\":\"l\"}," +
      copy +
      ",{\"select\":[\"alias\"]},{\"sort\":[{\"alias\":\"desc\"}]}]",
    )
    let inputs = [
      ("l", @pipeline_typing.KeyedInput(key)),
      ("r", @pipeline_typing.CarrierInput(right)),
    ]
    let p = @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(
      @schema.lookup(
        @pipeline_typing.output_schema(p).unwrap(),
        Unqualified("alias"),
      ).unwrap().nullable,
    )
    let retained = @pipeline_typing.candidate_key(p, Step(2)).unwrap()
    assert_true(
      !@evidence.key_field_at(retained, 0).unwrap().contract.unwrap().nullable,
    )
    assert_eq(@evidence.key_pending(retained), @evidence.key_pending(key))
    assert_true(@pipeline_typing.logical_order(p, Step(3)) is Some(_))
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_text_bytes: u.text_bytes,
      max_nodes: u.nodes,
      max_tokens: u.tokens,
    }
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
      is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, {
        ..exact,
        max_work: u.work - 1,
      })
      is Err(_),
    )
  }
}
