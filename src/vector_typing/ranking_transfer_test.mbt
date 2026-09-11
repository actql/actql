///|
test "score evidence lookup distinguishes qualification and transfers require the bound schema" {
  let number = @contract.primitive(NumberType, nullable=false)
  let make_rows = fn() {
    @carrier.relation(
      @carrier.rows(
        [
          (Qualified(Left, "score"), Some(number)),
          (Unqualified("id"), Some(number)),
          (
            Unqualified("payload"),
            Some(
              @contract.object_contract(
                [("leaf", number)],
                nullable=false,
                max_fields=1,
                max_name_bytes=4,
              ).unwrap(),
            ),
          ),
        ],
        field_set=Closed,
        max_fields=3,
        max_name_bytes=40,
      ).unwrap(),
    )
  }
  let source = cursor(
    "{\"domain\":\"d\",\"range\":[0,1],\"normalization\":\"n\"}",
  )
  let rows = make_rows()
  let input = @vector_typing.declare_ranking_score(
    source,
    rows,
    Qualified(Left, "score"),
    limits(),
  ).unwrap()
  assert_true(
    @vector_typing.ranking_score_at(input, Qualified(Left, "score")) is Some(_),
  )
  assert_true(
    @vector_typing.ranking_score_at(input, Unqualified("left.score")) is None,
  )
  assert_true(
    @vector_typing.ranking_score_at(input, Qualified(Right, "score")) is None,
  )
  let forms : Array[(@relation.Operation, String)] = [
    (Select, "[\"id\",{\"s\":\"left.score\"}]"),
    (Derive, "{\"s\":\"left.score\"}"),
    (
      Analytic,
      "{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"n\":{\"fn\":\"row_number\"}}}",
    ),
    (JsonPick, "{\"column\":\"payload\",\"path\":[\"leaf\"],\"output\":\"n\"}"),
  ]
  for (operation, body) in forms {
    let op = @relation.check(
      operation,
      cursor(body),
      @carrier.complete_schema(@carrier.relation_rows(rows).unwrap()).unwrap(),
      None,
      {
        max_work: 1000,
        max_nodes: 1000,
        max_text_bytes: 1000,
        max_tokens: 1000,
        max_depth: 10,
      },
    ).unwrap()
    let c = @vector_typing.transfer_ranking_unary(input, op, limits()).unwrap()
    let field = if operation == @relation.Analytic ||
      operation == @relation.JsonPick {
      @row.Qualified(Left, "score")
    } else {
      @row.Unqualified("s")
    }
    let declaration = @vector_typing.ranking_score_at(c.input, field).unwrap()
    assert_true(
      physical_equal(
        declaration,
        @vector_typing.ranking_score_at(input, Qualified(Left, "score")).unwrap(),
      ),
    )
    assert_eq(
      @vector_typing.declared_score_field(declaration),
      Qualified(Left, "score"),
    )
    assert_true(
      @carrier.lookup(
        @vector_typing.declared_score_records(declaration),
        Qualified(Left, "score"),
      )
      is Present(_),
    )
    assert_true(
      @carrier.lookup(
        @vector_typing.declared_score_records(declaration),
        Unqualified("s"),
      )
      is Absent,
    )
    assert_true(
      @vector_typing.ranking_score_at(input, Unqualified("s")) is None,
    )
    let exact = {
      ..limits(),
      max_work: c.usage.work,
      max_text_bytes: c.usage.text_bytes,
      max_nodes: 0,
    }
    assert_true(
      @vector_typing.transfer_ranking_unary(input, op, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: c.usage.work - 1, },
        { ..exact, max_text_bytes: c.usage.text_bytes - 1, },
      ] {
      if cap.max_text_bytes < 0 {
        continue
      }
      assert_true(
        @vector_typing.transfer_ranking_unary(input, op, cap)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
    let other = @vector_typing.declare_ranking_score(
      source,
      make_rows(),
      Qualified(Left, "score"),
      limits(),
    ).unwrap()
    assert_true(
      @vector_typing.transfer_ranking_unary(other, op, limits())
      is Err({ kind: RankingInputMismatch, .. }),
    )
  }
}
