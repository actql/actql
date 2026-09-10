///|
test "ranking policies retain source order repeated occurrences and independent rank window" {
  let at = cursor(
    "{\"with\":[\"r\",\"r\"],\"by\":[\"q\",\"q\"],\"candidate\":\"id\",\"rank\":\"position\",\"k\":3,\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"rank_window\":100,\"weights\":[1,0,2]}}}",
  )
  let o = @vector_typing.read_ranking_options(at, limits()).unwrap()
  assert_eq(@vector_typing.ranking_policy(o), ReciprocalRank)
  assert_eq(@vector_typing.ranking_inputs(o), ["r", "r"])
  assert_eq(@vector_typing.ranking_by(o), [Unqualified("q"), Unqualified("q")])
  assert_eq(@vector_typing.ranking_rank_constant(o), Some(60))
  assert_eq(@vector_typing.ranking_rank_window(o), Some(100))
  assert_eq(@vector_typing.ranking_k(o), 3)
  assert_true(@vector_typing.ranking_score_contract(o) is None)
  let copy = @vector_typing.ranking_weights(o)
  copy[0] = 99
  assert_eq(@vector_typing.ranking_weights(o), [1, 0, 2])
  let u = @vector_typing.ranking_options_usage(o)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@vector_typing.read_ranking_options(at, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @vector_typing.read_ranking_options(at, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "score fusion accepts the fixed higher-is-better law without importing score evidence" {
  for policy in ["\"max\"", "{\"weighted_sum\":{\"left\":0.6,\"right\":0.4}}"] {
    let o = @vector_typing.read_ranking_options(
      cursor(
        "{\"with\":\"r\",\"by\":[],\"candidate\":\"id\",\"score\":\"relevance\",\"k\":1,\"tie_break\":[],\"score_policy\":" +
        policy +
        ",\"score_contract\":{\"domain\":\"normalized\",\"range\":[1,2],\"normalization\":\"identity\"}}",
      ),
      limits(),
    ).unwrap()
    assert_eq(@vector_typing.ranking_by(o), [])
    assert_eq(@vector_typing.ranking_tie_break(o), Some([]))
    assert_eq(@vector_typing.ranking_score(o), Some(Unqualified("relevance")))
    assert_eq(@vector_typing.ranking_score_contract(o).unwrap().minimum, 1)
    assert_eq(@vector_typing.ranking_score_contract(o).unwrap().maximum, 2)
  }
}

///|
test "ranking options reject cross-policy members malformed weights and nonpositive bounds" {
  let common = "\"with\":\"r\",\"by\":[],\"candidate\":\"id\",\"k\":1,"
  let contract = "\"score\":\"s\",\"score_contract\":{\"domain\":\"d\",\"range\":[0,1],\"normalization\":\"n\"},"
  for
    suffix in [
      "\"rank\":\"r\",\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"rank_window\":10,\"weights\":[1,1]}}",
      "\"rank\":\"r\",\"score_policy\":\"max\"", "\"score_policy\":{\"weighted_sum\":{\"left\":0.5,\"right\":0.5000000000000002}}",
      "\"score_policy\":{\"weighted_sum\":{\"left\":-1,\"right\":2}}", "\"score_policy\":{\"weighted_sum\":{\"left\":0.5}}",
      "\"score_policy\":\"sum\"",
    ] {
    assert_true(
      @vector_typing.read_ranking_options(
        cursor("{" + common + contract + suffix + "}"),
        limits(),
      )
      is Err(_),
    )
  }
  for
    rrf in [
      "{\"rank_constant\":0,\"rank_window\":10,\"weights\":[1,1]}", "{\"rank_constant\":60,\"rank_window\":1.5,\"weights\":[1,1]}",
      "{\"rank_constant\":60,\"rank_window\":10,\"weights\":[1]}", "{\"rank_constant\":60,\"rank_window\":10,\"weights\":[0,0]}",
    ] {
    assert_true(
      @vector_typing.read_ranking_options(
        cursor(
          "{" +
          common +
          "\"rank\":\"r\",\"score_policy\":{\"rrf\":" +
          rrf +
          "}}",
        ),
        limits(),
      )
      is Err(_),
    )
  }
  for name in ["score", "score_contract", "tie_break"] {
    assert_true(
      @vector_typing.read_ranking_options(
        cursor(
          "{" +
          common +
          "\"" +
          name +
          "\":null,\"rank\":\"r\",\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"rank_window\":10,\"weights\":[1,1]}}}",
        ),
        limits(),
      )
      is Err(_),
    )
  }
}
