///|
test "analytics and typed object projection retain input keys but never create them" {
  let number = @contract.primitive(NumberType, nullable=false)
  let payload = @contract.object_contract(
    [("x", number)],
    nullable=false,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let rows = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_fields(
        [(Unqualified("id"), number), (Unqualified("payload"), payload)],
        max_fields=2,
        max_name_bytes=9,
      ).unwrap(),
    ),
  )
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for
    op in [
      "{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"desc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
      "{\"json_pick\":{\"column\":\"payload\",\"path\":[\"x\"],\"output\":\"x\"}}",
    ] {
    for keyed in [false, true] {
      let inputs = [
        (
          "rows",
          if keyed {
            @pipeline_typing.KeyedInput(key)
          } else {
            @pipeline_typing.CarrierInput(rows)
          },
        ),
      ]
      let source = cursor(
        "[" +
        op +
        ",{\"select\":[{\"alias\":\"id\"}]},{\"sort\":[{\"alias\":\"desc\"}]}]",
      )
      let p = @pipeline_typing.check_with_evidence(
        source,
        inputs,
        None,
        None,
        limits(),
      ).unwrap()
      assert_eq(@pipeline_typing.candidate_key(p, Step(0)) is Some(_), keyed)
      assert_eq(@pipeline_typing.logical_order(p, Step(2)) is Some(_), keyed)
      // Neither calculation order nor the new field establishes output order.
      assert_true(@pipeline_typing.logical_order(p, Step(0)) is None)
      if keyed {
        let kept = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
        assert_eq(@evidence.key_pending(kept), @evidence.key_pending(key))
        assert_eq(
          @evidence.declared_key_field_at(kept, 0).unwrap().name,
          Unqualified("id"),
        )
        assert_eq(
          @evidence.key_field_at(kept, 0).unwrap().name,
          Unqualified("alias"),
        )
      }
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
}
