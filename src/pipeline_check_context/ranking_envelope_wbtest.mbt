///|
test "ranking score envelopes include absent sides rounding and finite successful outputs" {
  for
    (policy, range, expected) in [
      ("\"max\"", "[1,2]", (1.0, 2.0)),
      ("\"max\"", "[-4,-2]", (-4.0, -2.0)),
      ("{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}", "[1,2]", (0.5, 2.0)),
      (
        "{\"weighted_sum\":{\"left\":0.25,\"right\":0.75}}",
        "[-4,-2]",
        (-4.0, -0.5),
      ),
      (
        "{\"weighted_sum\":{\"left\":0.25,\"right\":0.75}}",
        "[-4,2]",
        (-4.0, 2.0),
      ),
      ("{\"weighted_sum\":{\"left\":0,\"right\":1}}", "[1,2]", (0.0, 2.0)),
      (
        "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}",
        "[5e-324,5e-324]",
        (0.0, 0.0),
      ),
    ] {
    let options = @vector.read_ranking_options(
      asof_test_cursor(
        "{\"with\":\"r\",\"by\":[],\"candidate\":\"id\",\"score\":\"score\",\"k\":1,\"score_policy\":" +
        policy +
        ",\"score_contract\":{\"domain\":\"d\",\"range\":" +
        range +
        ",\"normalization\":\"n\"}}",
      ),
      {
        max_work: 10000,
        max_nodes: 1000,
        max_depth: 20,
        max_text_bytes: 10000,
      },
    ).unwrap()
    assert_eq(ranking_score_bounds(options, 1).unwrap(), (expected, 1))
    assert_true(ranking_score_bounds(options, 0) is Err(BudgetExceeded))
  }
  for
    (inputs, weights, constant, expected, cost) in [
      ("[\"r\",\"r\"]", "[1,0,2]", "1", 1.5, 4),
      ("[\"r\"]", "[5e-324,0]", "60", 0.0, 3),
      (
        "[\"r\",\"r\"]", "[1.7976931348623157e308,1.7976931348623157e308,1.7976931348623157e308]",
        "1", 1.7976931348623157e308, 4,
      ),
    ] {
    let options = @vector.read_ranking_options(
      asof_test_cursor(
        "{\"with\":" +
        inputs +
        ",\"by\":[],\"candidate\":\"id\",\"rank\":\"rank\",\"k\":1,\"score_policy\":{\"rrf\":{\"rank_constant\":" +
        constant +
        ",\"rank_window\":1,\"weights\":" +
        weights +
        "}}}",
      ),
      {
        max_work: 10000,
        max_nodes: 1000,
        max_depth: 20,
        max_text_bytes: 10000,
      },
    ).unwrap()
    assert_eq(
      ranking_score_bounds(options, cost).unwrap(),
      ((0.0, expected), cost),
    )
    assert_true(ranking_score_bounds(options, cost - 1) is Err(BudgetExceeded))
  }
}
