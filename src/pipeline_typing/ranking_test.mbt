///|
test "nearest and repeated RRF stages retain typed identities ordered edges and shared budgets" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.rows(
    [
      (Unqualified("a"), Some(number)),
      (Unqualified("b"), Some(number)),
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
    ids=[Unqualified("a"), Unqualified("b")],
    components=Unqualified("v"),
    max_identity_fields=2,
  ).unwrap()
  let source = cursor(
    "[{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":10},\"as\":\"n\"},{\"merge_rankings\":{\"with\":[\"n\",\"n\"],\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":5,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,0,2],\"rank_window\":10}}}},{\"merge_rankings\":{\"with\":\"n\",\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,1],\"rank_window\":5}}}},{\"select\":[\"query_id\",\"candidate_id\",\"rank\"]}]",
  )
  let inputs = [("v", vectors)]
  let p = @pipeline_typing.check_carriers(source, inputs, None, None, limits()).unwrap()
  let first = @pipeline_typing.step_at(p, 1).unwrap()
  assert_true(first.operation is Ranking(_))
  let edges = @pipeline_typing.input_occurrences(first)
  assert_eq(edges.length(), 3)
  for i in 0..<edges.length() {
    assert_eq(edges[i].role, Sample(i))
    assert_eq(edges[i].target, Step(0))
  }
  assert_eq(
    @pipeline_typing.input_occurrences(@pipeline_typing.step_at(p, 2).unwrap())[0].target,
    Step(1),
  )
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 3)
  assert_true(
    @vector.ranking_input_fusion(
      @pipeline_typing.ranking_evidence(p, Step(2)).unwrap(),
    )
    is Some(_),
  )
  assert_true(@pipeline_typing.ranking_evidence(p, Step(99)) is None)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, cap) is Err(_),
    )
  }
}

///|
test "compound ranking identities survive all aliases and filtering before fusion" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.rows(
    [
      (Unqualified("a"), Some(number)),
      (Unqualified("b"), Some(number)),
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
    ids=[Unqualified("a"), Unqualified("b")],
    components=Unqualified("v"),
    max_identity_fields=2,
  ).unwrap()
  let source = cursor(
    "[{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":10}},{\"select\":[\"query_id\",{\"x\":\"candidate_id\"},{\"y\":\"candidate_id\"},\"rank\"]},{\"drop\":[\"x\"]},{\"filter\":\"rank > 0\",\"as\":\"prepared\"},{\"merge_rankings\":{\"with\":\"prepared\",\"by\":[\"query_id\"],\"candidate\":\"y\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,1],\"rank_window\":10}}}}]",
  )
  let inputs = [("v", vectors)]
  let p = @pipeline_typing.check_carriers(source, inputs, None, None, limits()).unwrap()
  assert_true(
    @vector.ranking_input_nearest(
      @pipeline_typing.ranking_evidence(p, Step(3)).unwrap(),
    )
    is Some(_),
  )
  guard @pipeline_typing.step_at(p, 4).unwrap().operation is Ranking(c) else {
    abort("ranking")
  }
  assert_true(
    @vector.merged_ranking_pending(c).contains(
      ValidatePositiveSafeContiguousRanks,
    ),
  )
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, cap) is Err(_),
    )
  }
}

///|
test "captured score aliases preserve their original declaration and overwrites invalidate them" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(number)), (Unqualified("score"), Some(number))],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=7,
    ).unwrap(),
  )
  let contract = "{\"domain\":\"relevance\",\"range\":[0,1],\"normalization\":\"identity\"}"
  let ranking = @vector.declare_ranking_score(
    cursor(contract),
    rows,
    Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let prefix = "{\"select\":[\"id\",{\"a\":\"score\"},{\"b\":\"score\"}]},{\"drop\":[\"a\"],\"as\":\"prepared\"}"
  let merge = "{\"merge_rankings\":{\"with\":\"prepared\",\"by\":[],\"candidate\":\"id\",\"score\":\"b\",\"k\":1,\"score_policy\":\"max\",\"score_contract\":" +
    contract +
    "}}"
  let inputs = [("rows", @pipeline_typing.RankingInput(ranking))]
  let p = @pipeline_typing.check_with_evidence(
    cursor("[" + prefix + "," + merge + "]"),
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  let retained = @pipeline_typing.ranking_evidence(p, Step(1)).unwrap()
  let declaration = @vector.ranking_score_at(retained, Unqualified("b")).unwrap()
  assert_eq(@vector.declared_score_field(declaration), Unqualified("score"))
  assert_true(@vector.ranking_score_at(retained, Unqualified("a")) is None)
  assert_true(
    @vector.ranking_score_at(ranking, Unqualified("score")) is Some(_),
  )
  let changed = @pipeline_typing.check_with_evidence(
    cursor("[" + prefix + ",{\"derive\":[{\"b\":\"1\"}]}," + merge + "]"),
    inputs,
    None,
    None,
    limits(),
  )
  assert_true(changed is Err({ kind: Vector(MissingScoreContract), .. }))
}

///|
test "scored fusion consumes captured score declarations rather than ordinary columns" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(number)), (Unqualified("score"), Some(number))],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=7,
    ).unwrap(),
  )
  let contract = "{\"domain\":\"relevance\",\"range\":[0,1],\"normalization\":\"identity\"}"
  let ranking = @vector.declare_ranking_score(
    cursor(contract),
    rows,
    Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let source = cursor(
    "[{\"merge_rankings\":{\"with\":\"r\",\"by\":[],\"candidate\":\"id\",\"score\":\"score\",\"k\":1,\"score_policy\":\"max\",\"score_contract\":" +
    contract +
    "},\"as\":\"merged\"}]",
  )
  let start = Some(cursor("\"l\""))
  let p = @pipeline_typing.check_with_evidence(
    source,
    [("l", RankingInput(ranking)), ("r", RankingInput(ranking))],
    None,
    start,
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.lookup(p, "merged"), Some(Step(0)))
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 3)
  guard @pipeline_typing.step_at(p, 0).unwrap().operation is Ranking(c) else {
    abort("ranking")
  }
  assert_true(
    @vector.merged_ranking_pending(c).contains(
      AuthenticateCapturedScoreDeclarations,
    ),
  )
  assert_true(
    @pipeline_typing.check_carriers(
      source,
      [("l", rows), ("r", rows)],
      None,
      start,
      limits(),
    )
    is Err({ kind: Vector(MissingScoreContract), .. }),
  )
}
