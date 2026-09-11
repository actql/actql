///|
test "fixed windows preserve input keys and sliding windows require membership identity" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_fields(
        [(Unqualified("id"), number), (Unqualified("at"), number)],
        max_fields=2,
        max_name_bytes=4,
      ).unwrap(),
    ),
  )
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for kind in ["fixed", "sliding"] {
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
        "[{\"row_window\":{\"kind\":\"" +
        kind +
        "\",\"time\":\"at\",\"size\":10,\"step\":3}},{\"select\":[\"id\",{\"a\":\"window_start\"},{\"b\":\"window_start\"}]},{\"drop\":[\"a\"]},{\"sort\":[{\"id\":\"desc\"}]},{\"drop\":[\"b\"]}]",
      )
      let p = @pipeline_typing.check_with_evidence(
        source,
        inputs,
        None,
        None,
        limits(),
      ).unwrap()
      assert_eq(@pipeline_typing.candidate_key(p, Step(0)) is Some(_), keyed)
      assert_eq(@pipeline_typing.logical_order(p, Step(3)) is Some(_), keyed)
      assert_eq(
        @pipeline_typing.candidate_key(p, Step(4)) is Some(_),
        keyed && kind == "fixed",
      )
      if keyed {
        let result = @pipeline_typing.candidate_key(p, Step(0)).unwrap()
        assert_eq(
          @evidence.key_field_count(result),
          if kind == "fixed" {
            1
          } else {
            2
          },
        )
        if kind == "sliding" {
          assert_eq(@evidence.key_origin(result), WindowMembershipResult)
          assert_true(@evidence.key_window_producer(result) is Some(_))
          let parent = @evidence.key_window_input(result).unwrap()
          assert_eq(@evidence.key_pending(parent), @evidence.key_pending(key))
          assert_eq(
            @evidence.key_field_at(parent, 0).unwrap().name,
            Unqualified("id"),
          )
          let c = @pipeline_typing.order_sort_completion(
            @pipeline_typing.logical_order(p, Step(3)).unwrap(),
          ).unwrap()
          assert_eq(
            @pipeline_typing.sort_completion_field(c, 0),
            Some(Unqualified("b")),
          )
        } else {
          assert_true(@evidence.key_window_input(result) is None)
          assert_eq(@evidence.key_pending(result), @evidence.key_pending(key))
        }
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
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, {
          ..exact,
          max_text_bytes: u.text_bytes - 1,
        })
        is Err(_),
      )
    }
  }
}
