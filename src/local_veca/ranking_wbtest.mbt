///|
test "ranking workspace checks every derived width" {
  assert_eq(ranking_workspace(0, 2147483647, 0, 0), None)
  assert_eq(ranking_workspace(0, 2147483632, 0, 0), None)
  assert_eq(ranking_workspace(1, 2147483631, 0, 0), None)
}

///|
test "ranking workspace retains exact and one-short boundaries" {
  let required = ranking_workspace(4, 1, 2, 3).unwrap()
  assert_eq(required, 106)
  assert_true(required - 1 < required)
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
