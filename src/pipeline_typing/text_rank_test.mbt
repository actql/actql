///|
test "text ranking resolves query occurrences and composes with reciprocal rank fusion" {
  let text = @contract.primitive(StringType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(text)), (Unqualified("text"), Some(text))],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=6,
    ).unwrap(),
  )
  let body = "{\"queries\":\"q\",\"candidate_id\":\"id\",\"candidate_text\":\"text\",\"query_id\":\"id\",\"query_text\":\"text\",\"tokenizer\":\"unicode_words\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":10}"
  let source = cursor(
    "[{\"text_rank\":" +
    body +
    ",\"as\":\"lexical\"},{\"merge_rankings\":{\"with\":\"lexical\",\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,1],\"rank_window\":10}}}}]",
  )
  let inputs = [("corpus", rows), ("q", rows)]
  let from = Some(cursor("\"corpus\""))
  let p = @pipeline_typing.check_carriers(source, inputs, None, from, limits()).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(step.operation is TextRank(queries=Input(1), ..))
  let edges = @pipeline_typing.input_occurrences(step)
  assert_eq(edges[0].target, Input(0))
  assert_eq(edges[1].target, Input(1))
  assert_true(
    @vector.ranking_input_text(
      @pipeline_typing.ranking_evidence(p, Step(0)).unwrap(),
    )
    is Some(_),
  )
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 4)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, from, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, from, cap) is Err(_),
    )
  }
  let issue = @pipeline_typing.check_carriers(
    source,
    [("corpus", rows)],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, UnknownName("q"))
  assert_eq(issue.path, [
    @source.Index(0),
    @source.Key("text_rank"),
    @source.Key("queries"),
  ])
}
