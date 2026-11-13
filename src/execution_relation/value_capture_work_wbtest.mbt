///|
test "capture text keeps one exact debit and distinguishes only the strictly smaller work refusal" {
  let limits = {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 15,
  }
  let work = value_budget(limits).unwrap()
  assert_eq(charge_text_issue(work, "x".repeat(16)), Some(CaptureWorkLimit(15)))
  assert_eq(
    (work.nodes, work.text, work.work, work.external_work),
    (0, 0, 0, 0),
  )
  let boolean = value_budget(limits).unwrap()
  assert_false(charge_text(boolean, "x".repeat(16)))
  assert_eq(
    (boolean.nodes, boolean.text, boolean.work, boolean.external_work),
    (0, 0, 0, 0),
  )
  for (text, work) in [(15, 15), (14, 15)] {
    let tied = value_budget({ ..limits, max_text_bytes: text, max_work: work, }).unwrap()
    assert_eq(charge_text_issue(tied, "x".repeat(16)), Some(CaptureLimit))
  }
  let malformed = value_budget(limits).unwrap()
  assert_eq(
    charge_text_issue(
      malformed,
      String::from_array([(0xd800).unsafe_to_char()]),
    ),
    Some(CaptureLimit),
  )
  assert_eq((malformed.text, malformed.work), (0, 0))
  let success = value_budget(limits).unwrap()
  assert_eq(charge_text_issue(success, "日本語😀"), None)
  assert_eq((success.text, success.work), (13, 13))
  let prior = value_budget(limits).unwrap()
  assert_true(charge_text(prior, "x".repeat(10)))
  assert_eq(charge_text_issue(prior, "x".repeat(6)), Some(CaptureWorkLimit(15)))
  assert_eq((prior.text, prior.work), (10, 10))
}
