///|
fn lexical_operand(
  n : Int64,
) -> (@pipeline.CheckedPipeline, @capacity_program_step.StepBound) {
  if n == 0L {
    let p = pipeline(
      "[{\"take\":1},{\"unnest\":{\"column\":\"id\",\"as\":\"value\"}},{\"select\":[{\"id\":\"value\"}]}]",
      field_type=@contract.array_contract(
        @contract.primitive(StringType, nullable=false),
        nullable=false,
        max_items=Some(0),
      ).unwrap(),
    )
    let seed = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 1, "{\"maximum\":1,\"op\":\"clamp\"}"),
    ).unwrap()
    let id = bound_id(seed)
    let bound = @capacity_program_step.check_with_inputs(
      p,
      1,
      proof(
        "actql.bound.unnest-array-items",
        0,
        "{\"factor\":0,\"input\":\"" + id + "\",\"op\":\"multiply\"}",
        reference="checked-step:1",
        inputs=[id],
      ),
      [seed],
    ).unwrap()
    return (p, bound)
  }
  let p = pipeline(
    "[{\"take\":1},{\"take\":1},{\"take\":" + n.to_string() + "}]",
    field_type=@contract.primitive(StringType, nullable=false),
  )
  let bound = @capacity_program_step.check(
    p,
    2,
    proof(
      "actql.bound.take",
      n,
      "{\"maximum\":" + n.to_string() + ",\"op\":\"clamp\"}",
      reference="checked-step:2",
    ),
  ).unwrap()
  (p, bound)
}

///|
fn lexical_pipeline(
  c : @pipeline.CheckedPipeline,
  q : @pipeline.CheckedPipeline,
  k : Int64,
  tokenizer : String,
) -> @pipeline.CheckedPipeline {
  @pipeline.check_with_evidence(
    cursor(
      "[{\"from\":\"c\",\"text_rank\":{\"queries\":\"q\",\"candidate_id\":\"id\",\"candidate_text\":\"id\",\"query_id\":\"id\",\"query_text\":\"id\",\"tokenizer\":\"" +
      tokenizer +
      "\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":" +
      k.to_string() +
      "}}]",
    ),
    [
      (
        "c",
        @pipeline.ProducedInput(@pipeline.produced_input(c, Step(2)).unwrap()),
      ),
      (
        "q",
        @pipeline.ProducedInput(@pipeline.produced_input(q, Step(2)).unwrap()),
      ),
    ],
    None,
    None,
    {
      max_steps: 1,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "lexical output bounds retain corpus and query owners without discharging scoring" {
  for tokenizer in ["unicode_words", "char_bigram"] {
    for corpus in [0L, 1L, 3L, 7L] {
      for queries in [0L, 1L, 5L] {
        for k in [1L, 3L, 8L] {
          let (cp, c) = lexical_operand(corpus)
          let (qp, q) = lexical_operand(queries)
          let p = lexical_pipeline(cp, qp, k, tokenizer)
          let cid = bound_id(c)
          let qid = bound_id(q)
          let expected = queries * (if corpus < k { corpus } else { k })
          let tight = proof(
            "actql.bound.text-rank",
            expected,
            "{\"op\":\"source\"}",
            inputs=[cid, qid],
          )
          let work = 2 +
            (if corpus == 0L { 1 } else { 0 }) +
            (if queries == 0L { 1 } else { 0 })
          let app = @capacity_program_step.check_with_inputs(
            p,
            0,
            tight,
            [c, q],
            max_input_work=work,
          ).unwrap()
          assert_eq(@capacity_program_step.input_work(app), work)
          assert_true(
            physical_equal(@capacity_program_step.input_at(app, 0).unwrap(), c),
          )
          assert_true(
            physical_equal(@capacity_program_step.input_at(app, 1).unwrap(), q),
          )
          guard @pipeline.step_at(
              @capacity_program_step.checked_pipeline(app),
              0,
            ).unwrap().operation
            is TextRank(checked~, ..) else {
            fail("lexical producer expected")
          }
          assert_true(
            @vector.text_rank_pending(checked).contains(ResolveTextRankProfile),
          )
          assert_true(@vector.text_rank_profile(checked) is None)
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              tight,
              [c, q],
              max_input_work=work - 1,
            )
            is Err(InputWorkLimit),
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              tight,
              [q, c],
              max_input_work=10,
            )
            is Err(_),
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              proof("actql.bound.nearest", expected, "{\"op\":\"source\"}", inputs=[
                cid, qid,
              ]),
              [c, q],
              max_input_work=work,
            )
            is Err(LawMismatch),
          )
          let loose = proof(
            "actql.bound.text-rank",
            queries * k,
            "{\"factor\":" +
            k.to_string() +
            ",\"input\":\"" +
            qid +
            "\",\"op\":\"multiply\"}",
            inputs=[qid],
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              loose,
              [q],
              max_input_work=2,
            )
            is Ok(_),
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              0,
              loose,
              [c],
              max_input_work=10,
            )
            is Err(_),
          )
          if corpus < k {
            let hidden = proof(
              "actql.bound.text-rank",
              expected,
              "{\"factor\":" +
              corpus.to_string() +
              ",\"input\":\"" +
              qid +
              "\",\"op\":\"multiply\"}",
              inputs=[qid],
            )
            assert_true(
              @capacity_program_step.check_with_inputs(
                p,
                0,
                hidden,
                [q],
                max_input_work=2,
              )
              is Err(_),
            )
          }
        }
      }
    }
  }
}

///|
test "lexical bounds share checked arithmetic and preserve repeated input occurrences" {
  let maximum = 9007199254740991L
  for
    (corpus, queries, k, expected) in [
      (1L, maximum, 2L, Some(maximum)),
      (2L, maximum, 2L, None),
      (maximum, 0L, maximum, Some(0L)),
      (0L, maximum, maximum, Some(0L)),
    ] {
    let (cp, c) = lexical_operand(corpus)
    let (qp, q) = lexical_operand(queries)
    let p = lexical_pipeline(cp, qp, k, "unicode_words")
    let claim = proof(
      "actql.bound.text-rank",
      expected.unwrap_or(1L),
      "{\"op\":\"source\"}",
      inputs=[bound_id(c), bound_id(q)],
    )
    let result = @capacity_program_step.check_with_inputs(
      p,
      0,
      claim,
      [c, q],
      max_input_work=4,
    )
    if expected is Some(_) {
      assert_true(result is Ok(_))
    } else {
      assert_true(result is Err(BoundOverflow))
    }
  }
  let (producer, bound) = lexical_operand(3)
  let p = lexical_pipeline(producer, producer, 2, "char_bigram")
  let id = bound_id(bound)
  let claim = proof("actql.bound.text-rank", 6, "{\"op\":\"source\"}", inputs=[
    id, id,
  ])
  let app = @capacity_program_step.check_with_inputs(
    p,
    0,
    claim,
    [bound, bound],
    max_input_work=2,
  ).unwrap()
  assert_eq(@capacity_program_step.input_count(app), 2)
  assert_true(
    @capacity_program_step.check_applications(
      program_claims([@capacity_program_step.checked_proof(bound), claim]),
      [bound, app],
      max_work=8,
    )
    is Ok(_),
  )
}
