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
  let selected = @text_rank_profile.admit(
    @utf8.encode(text_profile_fixture()),
    text_profile_fixture_cid(),
    text_profile_blobs(),
    {
      max_profile_bytes: 10000,
      max_dependency_bytes: 1000,
      max_nodes: 1000,
      max_depth: 20,
    },
  ).unwrap()
  let bound = @pipeline_typing.check_carriers(
    source,
    inputs,
    None,
    from,
    limits(),
    text_rank_profile=Some(selected),
  ).unwrap()
  let bound_rank = @vector.ranking_input_text(
    @pipeline_typing.ranking_evidence(bound, Step(0)).unwrap(),
  ).unwrap()
  let lexical_key = @pipeline_typing.candidate_key(bound, Step(0)).unwrap()
  assert_eq(@evidence.key_origin(lexical_key), TextRankResult)
  assert_eq(@evidence.key_field_count(lexical_key), 2)
  assert_true(
    physical_equal(
      @evidence.key_text_rank_producer(lexical_key).unwrap(),
      bound_rank,
    ),
  )
  let lexical_transfer = @evidence.text_rank_keys(bound_rank, {
    max_work: 3,
    max_name_bytes: 20,
  }).unwrap()
  assert_eq(lexical_transfer.work, 3)
  assert_eq(lexical_transfer.name_bytes, 20)
  assert_true(
    @evidence.text_rank_keys(bound_rank, { max_work: 2, max_name_bytes: 20, })
    is Err(_),
  )
  assert_true(
    @evidence.text_rank_keys(bound_rank, { max_work: 3, max_name_bytes: 19, })
    is Err(_),
  )
  let unbound_rank = @vector.ranking_input_text(
    @pipeline_typing.ranking_evidence(p, Step(0)).unwrap(),
  ).unwrap()
  assert_true(@vector.text_rank_profile(unbound_rank) is None)
  assert_eq(
    @text_rank_profile.cid(@vector.text_rank_profile(bound_rank).unwrap()),
    text_profile_fixture_cid(),
  )
  assert_true(
    @vector.text_rank_pending(unbound_rank).contains(ResolveTextRankProfile),
  )
  let pending = @vector.text_rank_pending(bound_rank)
  assert_false(pending.contains(ResolveTextRankProfile))
  assert_true(pending.contains(NormalizeAndTokenizeWithPinnedUnicode))
  assert_true(pending.contains(EvaluatePinnedBm25AndCorrectlyRoundedLogarithm))
  assert_true(pending.contains(ResolveStatisticsScoringAndOutputResources))
  assert_eq(
    pending.length() + 1,
    @vector.text_rank_pending(unbound_rank).length(),
  )
  // The options-only and direct checker paths bind the same admitted profile.
  let direct = @vector.check_text_rank(
    cursor(body),
    rows,
    rows,
    {
      max_work: 10000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
    profile=Some(selected),
  ).unwrap()
  assert_eq(
    @text_rank_profile.cid(@vector.text_rank_profile(direct).unwrap()),
    text_profile_fixture_cid(),
  )
  let u = @pipeline_typing.usage(p)
  let bound_usage = @pipeline_typing.usage(bound)
  assert_eq(bound_usage.work, u.work)
  assert_eq(bound_usage.nodes, u.nodes)
  assert_eq(bound_usage.text_bytes, u.text_bytes)
  let evidence_path = @pipeline_typing.check_with_evidence(
    source,
    inputs.map(pair => (pair.0, @pipeline_typing.CarrierInput(pair.1))),
    None,
    from,
    limits(),
    text_rank_profile=Some(selected),
  ).unwrap()
  let producer = @vector.ranking_input_text(
    @pipeline_typing.ranking_evidence(evidence_path, Step(0)).unwrap(),
  ).unwrap()
  assert_eq(
    @text_rank_profile.cid(@vector.text_rank_profile(producer).unwrap()),
    text_profile_fixture_cid(),
  )
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
