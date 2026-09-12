///|
test "lexical selection retains environment and independent byte pin under exact work" {
  let pin = "sha256:" + "a".repeat(64)
  let (body, cid) = wire(
    "{\"text_rank\":{\"profile_bytes_cid\":\"" +
    pin +
    "\",\"version\":\"actql-text-rank-selection/0.1\"}}",
    "[]",
  )
  let environment = read(@utf8.encode(body), cid, caps()).unwrap()
  // Independent Node SHA-256 of the fixed canonical envelope preimage.
  assert_eq(
    cid, "sha256:f675acaace30f4eff8016f14a34a6e0efd0b708ebe72776cea44eeb12d516da1",
  )
  let selected = read_text_rank_selection(environment, 1000).unwrap()
  assert_true(
    physical_equal(text_rank_selection_environment(selected), environment),
  )
  assert_eq(text_rank_selection_cid(selected), pin)
  assert_true(pin != cid)
  let used = text_rank_selection_work(selected)
  assert_true(read_text_rank_selection(environment, used) is Ok(_))
  assert_true(
    read_text_rank_selection(environment, used - 1) is Err(BudgetExceeded),
  )
  assert_true(read_text_rank_selection(environment, -1) is Err(InvalidLimits))
  let (empty, id) = wire("{}", "[]")
  assert_true(
    read_text_rank_selection(
      read(@utf8.encode(empty), id, caps()).unwrap(),
      1000,
    )
    is Err(MissingSelection),
  )
}

///|
test "lexical selection rejects malformed supplied components even without consumers" {
  for
    value in [
      "null",
      "[]",
      "{}",
      "{\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"profile_bytes_cid\":null,\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"extra\":1,\"profile_bytes_cid\":\"sha256:" +
      "a".repeat(64) +
      "\",\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"profile_bytes_cid\":\"sha256:" +
      "A".repeat(64) +
      "\",\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"profile_bytes_cid\":\"sha256:" +
      "a".repeat(63) +
      "\",\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"profile_bytes_cid\":\"sha256:" +
      "a".repeat(64) +
      "\",\"version\":\"actql-text-rank-selection/1.0\"}",
    ] {
    let (body, id) = wire("{\"text_rank\":" + value + "}", "[]")
    let environment = read(@utf8.encode(body), id, caps()).unwrap()
    assert_true(
      read_text_rank_selection(environment, 1000) is Err(InvalidComponent),
    )
  }
}
