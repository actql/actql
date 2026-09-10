///|
test "ranking input retains producer-bound composite identity instead of accepting arbitrary objects" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.rows(
    [
      (Unqualified("a"), Some(number)),
      (Unqualified("b"), Some(@contract.primitive(StringType, nullable=false))),
      (
        Unqualified("v"),
        Some(@contract.vector_contract(2, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=3,
  ).unwrap()
  let vectors = @carrier.vectors(
    rows,
    ids=[Unqualified("b"), Unqualified("a")],
    components=Unqualified("v"),
    max_identity_fields=2,
  ).unwrap()
  let nearest = @vector_typing.check_nearest(
    cursor("{\"queries\":\"q\",\"metric\":\"dot\",\"k\":2}"),
    vectors,
    vectors,
    limits(),
  ).unwrap()
  let options = @vector_typing.read_ranking_options(
    cursor(
      "{\"with\":\"r\",\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":3,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"rank_window\":10,\"weights\":[1,1]}}}",
    ),
    limits(),
  ).unwrap()
  let input = @vector_typing.ranking_from_nearest(nearest)
  let c = @vector_typing.check_ranking_shape(options, input, limits()).unwrap()
  let usage = @vector_typing.ranking_shape_usage(c)
  let exact = {
    ..limits(),
    max_work: usage.work,
    max_text_bytes: usage.text_bytes,
    max_nodes: 0,
  }
  assert_true(
    @vector_typing.check_ranking_shape(options, input, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
    ] {
    assert_true(
      @vector_typing.check_ranking_shape(options, input, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  let plain = @vector_typing.ranking_relation(
    @vector_typing.nearest_output(nearest),
  )
  assert_true(
    @vector_typing.check_ranking_shape(options, plain, limits())
    is Err({ kind: InvalidRankingField(Unqualified("query_id")), .. }),
  )
}

///|
test "ranking shape rejects nullable candidates nonnumeric ranks and incomplete inputs" {
  let options = @vector_typing.read_ranking_options(
    cursor(
      "{\"with\":\"r\",\"by\":[],\"candidate\":\"id\",\"rank\":\"position\",\"k\":3,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"rank_window\":10,\"weights\":[1,1]}}}",
    ),
    limits(),
  ).unwrap()
  for nullable in [false, true] {
    for
      rank in [
        @contract.primitive(NumberType, nullable=false),
        @contract.primitive(StringType, nullable=false),
      ] {
      let rows = @carrier.rows(
        [
          (Unqualified("id"), Some(@contract.primitive(NumberType, nullable~))),
          (Unqualified("position"), Some(rank)),
        ],
        field_set=Closed,
        max_fields=2,
        max_name_bytes=20,
      ).unwrap()
      let result = @vector_typing.check_ranking_shape(
        options,
        @vector_typing.ranking_relation(@carrier.relation(rows)),
        limits(),
      )
      assert_eq(result is Ok(_), !nullable && rank.shape is Number)
    }
  }
  assert_true(
    @vector_typing.check_ranking_shape(
      options,
      @vector_typing.ranking_relation(
        @carrier.relation(@carrier.unknown_rows()),
      ),
      limits(),
    )
    is Err({ kind: IncompleteRankingInput, .. }),
  )
}
