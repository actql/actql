///|
test "ranking workspace checks every derived width" {
  assert_eq(ranking_workspace(0, 2147483647, 0, 0, 0), None)
  assert_eq(ranking_workspace(0, 2147483632, 0, 0, 0), None)
  assert_eq(ranking_workspace(1, 2147483631, 0, 0, 0), None)
  assert_eq(ranking_workspace(0, 0, 0, 0, 1073741824), None)
}

///|
test "ranking workspace retains exact and one-short boundaries" {
  let required = ranking_workspace(4, 1, 2, 3, 3).unwrap()
  assert_eq(required, 124)
  assert_eq(ranking_workspace(4, 1, 2, 3, 2), Some(122))
  assert_eq(ranking_workspace(0, 1, 2, 3, 2), Some(38))
  assert_true(required - 1 < required)
}

///|
fn ranking_comparison_result(
  goal : RankingComparison,
) -> Result[Int, RankingIssue] {
  let cursor = start_ranking_comparison(goal)
  for _ in 0..<10000 {
    match advance_ranking_comparison(cursor) {
      Ok(Some(order)) => return Ok(order)
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  }
  Err(InvalidRankingKernel)
}

///|
fn ranking_values_compare(
  left : Array[@value.CheckedValue],
  right : Array[@value.CheckedValue],
) -> Result[Int, RankingIssue] {
  ranking_comparison_result(GroupComparison(left, right))
}

///|
fn ranking_tie_values_compare(
  left : Array[@value.CheckedValue],
  right : Array[@value.CheckedValue],
) -> Result[Int, RankingIssue] {
  ranking_comparison_result(TieComparison(left, right))
}

///|
test "ranking comparison yields within group candidate and tie prefixes" {
  let contract = @contract.primitive(@contract.StringType, nullable=false)
  let prefix = String::make(512, 'x')
  let a = @value.checked_text_value(prefix + "a", contract).unwrap()
  let b = @value.checked_text_value(prefix + "b", contract).unwrap()
  let left : RankingRecord = {
    input: 0,
    group: [a, a],
    candidate: a,
    tie: [a, a],
    score: Some(0.5),
    rank: Some(1.0),
  }
  let right : RankingRecord = { ..left, candidate: b, }
  let fused_left : FusedRanking = {
    group: [a, a],
    candidate: a,
    tie: [a, a],
    score: 0.5,
  }
  let fused_right = { ..fused_left, tie: [a, b], }
  // Two equal group components and one candidate consume 3*513 units.
  // Output ties visit two additional components before the differing tie.
  for
    (goal, expected_work) in [
      (RecordComparison(left, right, CandidateInputOrder), 1539),
      (CandidateComparison(left, right), 1539),
      (OutputComparison(fused_left, fused_right), 2052),
    ] {
    let cursor = start_ranking_comparison(goal)
    for index in 0..<expected_work {
      let result = advance_ranking_comparison(cursor).unwrap()
      if index == expected_work - 1 {
        assert_eq(result, Some(-1))
      } else {
        assert_eq(result, None)
      }
    }
    assert_true(cursor.scalar is None)
  }
}

///|
test "ranking business ties preserve nullable author order" {
  let contract = @contract.primitive(@contract.StringType, nullable=true)
  let text = @value.admit(contract, cursor("\"x\""), {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 1,
  }).unwrap()
  let null = @value.admit(contract, cursor("null"), {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 0,
  }).unwrap()
  assert_eq(ranking_tie_values_compare([text], [text]), Ok(0))
  assert_eq(ranking_tie_values_compare([null], [null]), Ok(0))
  assert_eq(ranking_tie_values_compare([text], [null]), Ok(-1))
  assert_eq(ranking_tie_values_compare([null], [text]), Ok(1))
}

///|
test "ranking groups nullable keys in canonical null-first order" {
  let contract = @contract.primitive(@contract.StringType, nullable=true)
  let text = @value.admit(contract, cursor("\"x\""), {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 1,
  }).unwrap()
  let null = @value.admit(contract, cursor("null"), {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 0,
  }).unwrap()
  assert_eq(ranking_values_compare([text], [text]), Ok(0))
  assert_eq(ranking_values_compare([null], [null]), Ok(0))
  assert_eq(ranking_values_compare([text], [null]), Ok(1))
  assert_eq(ranking_values_compare([null], [text]), Ok(-1))
  assert_eq(ranking_values_compare([null, text], [null, null]), Ok(1))
}
