///|
fn lag_body(suffix : String) -> String {
  "{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"field\":\"amount\",\"output\":\"previous\"" +
  suffix +
  "}"
}

///|
test "lag offset defaults and nullable result retain type and pending order evidence" {
  for suffix in ["", ",\"offset\":1"] {
    let checked = row_checked(Lag, lag_body(suffix))
    assert_true(field(output_row(checked), "previous").nullable)
    assert_true(
      @contract.type_equal(
        field(output_row(checked), "previous"),
        @contract.with_nullability(field(input(), "amount"), true),
        100,
      ),
    )
    match @relation_typing.row_operation(checked).unwrap() {
      Lag(partition~, order~, field~, output~, offset~) => {
        assert_eq(partition.length(), 0)
        assert_eq(order.length(), 1)
        assert_eq(@schema.reference_name(field.field), "amount")
        assert_eq(output, "previous")
        assert_eq(offset, Literal(1L))
        order.clear()
      }
      _ => fail("expected lag")
    }
    assert_true(
      indexed_obligation_copy(
        @relation_typing.pending_validations(checked),
        @relation_typing.pending_validation_count(checked),
        i => @relation_typing.pending_validation_at(checked, i),
        (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
      ).any(v => v.kind == LagCandidateKeyOrder),
    )
    match @relation_typing.row_operation(checked).unwrap() {
      Lag(order~, ..) => assert_eq(order.length(), 1)
      _ => fail("expected lag")
    }
  }
}

///|
test "lag rejects invalid offsets order fields and output collisions" {
  for
    suffix in [
      ",\"offset\":0", ",\"offset\":-1", ",\"offset\":1.5", ",\"offset\":9007199254740992",
      ",\"offset\":\"1\"", ",\"extra\":true",
    ] {
    assert_true(
      check_row(Lag, cursor(lag_body(suffix)), input(), None, limits())
      is Err(_),
    )
  }
  for
    text in [
      "{\"partition_by\":[],\"order_by\":[],\"field\":\"amount\",\"output\":\"x\"}",
      "{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"field\":\"missing\",\"output\":\"x\"}",
      "{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"field\":\"amount\",\"output\":\"amount\"}",
    ] {
    assert_true(check_row(Lag, cursor(text), input(), None, limits()) is Err(_))
  }
}
