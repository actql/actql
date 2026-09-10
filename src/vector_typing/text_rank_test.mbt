///|
fn lexical_rows(nullable : Bool) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("id"), Some(@contract.primitive(StringType, nullable~))),
        (
          Unqualified("text"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
        (Unqualified("other"), None),
      ],
      field_set=Open,
      max_fields=3,
      max_name_bytes=11,
    ).unwrap(),
  )
}

///|
fn lexical_source(
  tokenizer : String,
  k1 : String,
  b : String,
  k : String,
) -> @decode.Cursor {
  cursor(
    "{\"queries\":\"q\",\"candidate_id\":\"id\",\"candidate_text\":\"text\",\"query_id\":\"id\",\"query_text\":\"text\",\"tokenizer\":\"" +
    tokenizer +
    "\",\"scoring\":{\"bm25\":{\"k1\":" +
    k1 +
    ",\"b\":" +
    b +
    "}},\"k\":" +
    k +
    "}",
  )
}

///|
test "lexical ranking retains typed string identities partial payload and explicit execution obligations" {
  let rows = lexical_rows(false)
  for tokenizer in ["unicode_words", "char_bigram"] {
    let source = lexical_source(tokenizer, "1.2", "0.75", "20")
    let c = @vector_typing.check_text_rank(source, rows, rows, limits()).unwrap()
    let output = @carrier.relation_rows(@vector_typing.text_rank_output(c)).unwrap()
    assert_eq(@carrier.field_set(output), Closed)
    assert_eq(@carrier.field_count(output), 4)
    assert_true(
      @carrier.lookup(output, Unqualified("candidate_id"))
      is Present({ contract: Some({ nullable: false, shape: Text(_), }), .. }),
    )
    assert_true(
      @carrier.lookup(output, Unqualified("rank"))
      is Present({ contract: Some({ nullable: false, shape: Number, }), .. }),
    )
    assert_true(@carrier.lookup(output, Unqualified("other")) is Absent)
    assert_eq(
      @vector_typing.text_rank_k(@vector_typing.text_rank_options(c)),
      20,
    )
    assert_eq(
      @vector_typing.text_rank_bm25(@vector_typing.text_rank_options(c)),
      (1.2, 0.75),
    )
    let pending = @vector_typing.text_rank_pending(c)
    assert_true(
      pending.contains(EvaluatePinnedBm25AndCorrectlyRoundedLogarithm),
    )
    assert_true(pending.contains(ComputeStatisticsFromAdmittedCorpusOnly))
    assert_true(pending.contains(ValidateGlobalStringIdentities(Corpus)))
    assert_true(pending.contains(ValidateGlobalStringIdentities(Queries)))
    let input = @vector_typing.ranking_from_text(c)
    assert_true(@vector_typing.ranking_input_text(input) is Some(_))
    assert_true(@vector_typing.ranking_score_declaration(input) is None)
    let rrf = cursor(
      "{\"with\":\"r\",\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"weights\":[1,1],\"rank_window\":20}}}",
    )
    assert_true(
      @vector_typing.check_merge_rankings(rrf, [input, input], limits())
      is Ok(_),
    )
    let u = @vector_typing.text_rank_usage(c)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @vector_typing.check_text_rank(source, rows, rows, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @vector_typing.check_text_rank(source, rows, rows, cap)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
  }
}

///|
test "lexical options admit exact numeric endpoints without implicit defaults" {
  for k1 in ["5e-324", "1.7976931348623157e308"] {
    for b in ["0", "1"] {
      assert_true(
        @vector_typing.read_text_rank_options(
          lexical_source("char_bigram", k1, b, "9007199254740991"),
          limits(),
        )
        is Ok(_),
      )
    }
  }
  for
    (tokenizer, k1, b, k) in [
      ("words", "1", "0.5", "1"),
      ("unicode_words", "0", "0.5", "1"),
      ("unicode_words", "1", "-0.1", "1"),
      ("unicode_words", "1", "1.0000000000000002", "1"),
      ("unicode_words", "1", "0.5", "0"),
      ("unicode_words", "1", "0.5", "1.5"),
      ("unicode_words", "1", "0.5", "{\"$param\":\"k\"}"),
    ] {
    assert_true(
      @vector_typing.read_text_rank_options(
        lexical_source(tokenizer, k1, b, k),
        limits(),
      )
      is Err(_),
    )
  }
  for
    scoring in [
      "{}", "{\"bm25\":{\"k1\":1}}", "{\"bm25\":{\"k1\":1,\"b\":0.5,\"delta\":1}}",
      "{\"tf_idf\":{}}",
    ] {
    assert_true(
      @vector_typing.read_text_rank_options(
        cursor(
          "{\"queries\":\"q\",\"candidate_id\":\"id\",\"candidate_text\":\"text\",\"query_id\":\"id\",\"query_text\":\"text\",\"tokenizer\":\"unicode_words\",\"scoring\":" +
          scoring +
          ",\"k\":1}",
        ),
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "lexical role errors retain their source slot and never invent missing types" {
  let source = lexical_source("unicode_words", "1", "0.5", "1")
  let issue = @vector_typing.check_text_rank(
    source,
    lexical_rows(true),
    lexical_rows(false),
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, InvalidRankingField(Unqualified("id")))
  assert_eq(issue.path, [@source.Key("candidate_id")])
  let unknown = @carrier.relation(@carrier.unknown_rows())
  assert_true(
    @vector_typing.check_text_rank(
      source,
      lexical_rows(false),
      unknown,
      limits(),
    )
    is Err({ kind: InvalidRankingField(Unqualified("id")), .. }),
  )
  assert_true(
    @vector_typing.check_text_rank(
      source,
      @carrier.unknown_carrier(VectorsKind),
      lexical_rows(false),
      limits(),
    )
    is Err({ kind: WrongCarrier(VectorsKind), .. }),
  )
}
