///|
fn ranking_limits() -> @pipeline.Limits {
  {
    max_steps: 20,
    max_work: 100000,
    max_nodes: 100000,
    max_text_bytes: 100000,
    max_tokens: 10000,
    max_depth: 100,
  }
}

///|
test "nearest order reaches Results after projection hides query and candidate identities" {
  let vectors = @carrier.vectors(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("v"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=10,
    ).unwrap(),
    ids=[Unqualified("id")],
    components=Unqualified("v"),
    max_identity_fields=1,
  ).unwrap()
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"nearest\":{\"queries\":\"v\",\"metric\":\"l2\",\"k\":2}},{\"select\":[\"score\"]},{\"take\":1,\"as\":\"top\"}]",
    ),
    [("v", vectors)],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  assert_eq(
    @pipeline.order_origin(@pipeline.take_order(p, 2).unwrap()),
    Step(0),
  )
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"top\",\"fields\":[\"score\"]}}"),
    limits(),
  ).unwrap()
  let publication = resolve(results)
  assert_eq(@relation_results.publication_strategy(publication), Inherited)
  let origin = @pipeline.order_producer(
    @relation_results.publication_inherited_order(publication).unwrap(),
  )
  guard origin.operation is Nearest(checked~, ..) else { abort("nearest") }
  assert_false(@vector.nearest_pending(checked).is_empty())
  assert_eq(@relation_results.publication_term_count(publication), 0)
}

///|
test "lexical and fused ranking orders retain independent profile and scoring obligations" {
  let text = @contract.primitive(StringType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(text)), (Unqualified("text"), Some(text))],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=10,
    ).unwrap(),
  )
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"text_rank\":{\"queries\":\"rows\",\"candidate_id\":\"id\",\"candidate_text\":\"text\",\"query_id\":\"id\",\"query_text\":\"text\",\"tokenizer\":\"unicode_words\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":10},\"as\":\"lexical\"},{\"merge_rankings\":{\"with\":\"lexical\",\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,1],\"rank_window\":10}}},\"as\":\"fused\"}]",
    ),
    [("rows", rows)],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor(
      "{\"lexical\":{\"from\":\"lexical\",\"fields\":[\"score\"]},\"fused\":{\"from\":\"fused\",\"fields\":[\"rank\"]}}",
    ),
    limits(),
  ).unwrap()
  let all = @relation_results.resolve_publication_orders(
    results,
    max_results=2,
    max_work=100,
    max_text_bytes=100,
  ).unwrap()
  for i = 0; i < 2; i = i + 1 {
    let publication = @relation_results.publication_order_at(all, i).unwrap()
    assert_eq(@relation_results.publication_strategy(publication), Inherited)
    let order = @relation_results.publication_inherited_order(publication).unwrap()
    assert_eq(@pipeline.order_origin(order), Step(i))
    match @pipeline.order_producer(order).operation {
      TextRank(checked~, ..) =>
        assert_true(
          @vector.text_rank_pending(checked).contains(ResolveTextRankProfile),
        )
      Ranking(checked) =>
        assert_false(@vector.merged_ranking_pending(checked).is_empty())
      _ => abort("ranking producer")
    }
  }
}
