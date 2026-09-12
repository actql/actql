///|
fn ranking_rows(candidate : @contract.Contract) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("q"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
        (Unqualified("id"), Some(candidate)),
        (
          Unqualified("s"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("position"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("business"),
          Some(@contract.primitive(StringType, nullable=true)),
        ),
      ],
      field_set=Closed,
      max_fields=5,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
test "RRF preserves input occurrences joins domains and emits only fresh ranking columns" {
  let input = @vector_typing.ranking_relation(
    ranking_rows(@contract.primitive(NumberType, nullable=false)),
  )
  let source = cursor(
    "{\"with\":[\"r\",\"r\"],\"by\":[\"q\",\"q\"],\"candidate\":\"id\",\"rank\":\"position\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"rank_window\":10,\"weights\":[1,0,2]}}}",
  )
  let c = @vector_typing.check_merge_rankings(
    source,
    [input, input, input],
    limits(),
  ).unwrap()
  assert_eq(@vector_typing.merged_ranking_input_count(c), 3)
  let keys = @evidence.merged_ranking_keys(c, {
    max_work: 4,
    max_name_bytes: 4,
  }).unwrap()
  let key = @evidence.key_witness_at(keys.keys, 0).unwrap()
  assert_eq(@evidence.key_field_count(key), 2)
  assert_eq(keys.work, 4)
  assert_eq(keys.name_bytes, 4)
  assert_true(physical_equal(@evidence.key_ranking_producer(key).unwrap(), c))
  assert_eq(
    indexed_obligation_copy(
      @evidence.key_pending(key),
      @evidence.key_pending_count(key),
      i => @evidence.key_pending_at(key, i),
      (a, b) => a == b,
    ),
    [ValidateKeyProducer],
  )
  assert_true(
    @evidence.merged_ranking_keys(c, { max_work: 3, max_name_bytes: 4, })
    is Err(_),
  )
  assert_true(
    @evidence.merged_ranking_keys(c, { max_work: 4, max_name_bytes: 3, })
    is Err(_),
  )
  let rows = @carrier.relation_rows(@vector_typing.merged_ranking_output(c)).unwrap()
  assert_eq(@carrier.field_count(rows), 4)
  assert_true(@carrier.lookup(rows, Unqualified("business")) is Absent)
  assert_true(@carrier.lookup(rows, Unqualified("position")) is Absent)
  assert_true(
    @carrier.lookup(rows, Unqualified("rank"))
    is Present({ contract: Some({ nullable: false, shape: Number, }), .. }),
  )
  assert_true(
    indexed_obligation_copy(
      @vector_typing.merged_ranking_pending(c),
      @vector_typing.merged_ranking_pending_count(c),
      i => @vector_typing.merged_ranking_pending_at(c, i),
      (a, b) => a == b,
    ).contains(ValidatePositiveSafeContiguousRanks),
  )
  assert_true(
    indexed_obligation_copy(
      @vector_typing.merged_ranking_pending(c),
      @vector_typing.merged_ranking_pending_count(c),
      i => @vector_typing.merged_ranking_pending_at(c, i),
      (a, b) => a == b,
    ).contains(ApplyRankWindowAfterAdmission),
  )
  let u = @vector_typing.merged_ranking_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @vector_typing.check_merge_rankings(source, [input, input, input], exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @vector_typing.check_merge_rankings(source, [input, input, input], cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  let wrong = @vector_typing.ranking_relation(
    ranking_rows(@contract.primitive(StringType, nullable=false)),
  )
  assert_true(
    @vector_typing.check_merge_rankings(source, [input, wrong, input], limits())
    is Err({ kind: RankingDomainMismatch(Unqualified("id")), .. }),
  )
}

///|
test "weighted score fusion requires matching input declarations without inventing output bounds" {
  let rows = ranking_rows(@contract.primitive(NumberType, nullable=false))
  let declaration = cursor(
    "{\"domain\":\"relevance\",\"range\":[1,2],\"normalization\":\"normalized\"}",
  )
  let input = @vector_typing.declare_ranking_score(
    declaration,
    rows,
    Unqualified("s"),
    limits(),
  ).unwrap()
  let source = cursor(
    "{\"with\":\"r\",\"by\":[],\"candidate\":\"id\",\"score\":\"s\",\"k\":1,\"tie_break\":[\"business\"],\"score_contract\":{\"domain\":\"relevance\",\"range\":[1,2],\"normalization\":\"normalized\"},\"score_policy\":{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}}",
  )
  assert_true(
    @vector_typing.check_merge_rankings(
      source,
      [input, @vector_typing.ranking_relation(rows)],
      limits(),
    )
    is Err({ kind: MissingScoreContract, .. }),
  )
  let c = @vector_typing.check_merge_rankings(source, [input, input], limits()).unwrap()
  let key = @evidence.key_witness_at(
    @evidence.merged_ranking_keys(c, { max_work: 2, max_name_bytes: 2, }).unwrap().keys,
    0,
  ).unwrap()
  assert_eq(@evidence.key_field_count(key), 1)
  assert_eq(@evidence.key_field_at(key, 0).unwrap().name, Unqualified("id"))
  assert_true(physical_equal(@evidence.key_ranking_producer(key).unwrap(), c))
  let pending = indexed_obligation_copy(
    @vector_typing.merged_ranking_pending(c),
    @vector_typing.merged_ranking_pending_count(c),
    i => @vector_typing.merged_ranking_pending_at(c, i),
    (a, b) => a == b,
  )
  assert_true(pending.contains(AuthenticateCapturedScoreDeclarations))
  assert_true(pending.contains(ValidateBusinessTieAgreement))
  assert_true(pending.contains(DeriveOutputScoreEnvelope))
  assert_true(
    @vector_typing.ranking_score_declaration(
      @vector_typing.ranking_from_fusion(c),
    )
    is None,
  )
  let wrong = @vector_typing.declare_ranking_score(
    cursor(
      "{\"domain\":\"relevance\",\"range\":[1,2],\"normalization\":\"other\"}",
    ),
    rows,
    Unqualified("s"),
    limits(),
  ).unwrap()
  assert_true(
    @vector_typing.check_merge_rankings(source, [input, wrong], limits())
    is Err({ kind: ScoreContractMismatch, .. }),
  )
  let emitted = @carrier.relation_rows(@vector_typing.merged_ranking_output(c)).unwrap()
  assert_eq(@carrier.field_count(emitted), 3)
  assert_true(@carrier.lookup(emitted, Unqualified("business")) is Absent)
}

///|
test "producer tuple identities survive repeated RRF fusion" {
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
  let nearest = @vector_typing.check_nearest(
    cursor("{\"queries\":\"q\",\"metric\":\"dot\",\"k\":3}"),
    vectors,
    vectors,
    limits(),
  ).unwrap()
  let source = cursor(
    "{\"with\":\"r\",\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"rank_window\":10,\"weights\":[1,1]}}}",
  )
  let input = @vector_typing.ranking_from_nearest(nearest)
  let first = @vector_typing.check_merge_rankings(
    source,
    [input, input],
    limits(),
  ).unwrap()
  let next = @vector_typing.ranking_from_fusion(first)
  assert_true(@vector_typing.ranking_input_fusion(next) is Some(_))
  assert_true(
    @vector_typing.check_merge_rankings(source, [next, input], limits())
    is Ok(_),
  )
}
