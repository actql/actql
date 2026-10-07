///|
fn recorded_cleanup_graph_fixture() -> RecordedRunPublication {
  let template = admission_test_template()
  let plan = admission_test_plan(admission_test_cid("1"))
  let prepared = admission_test_prepared(template, plan, "allow")
  let authorization = admission_test_authorization(prepared, "allowed", false)
  let admission = admit_run_publication(template, prepared, authorization, plan).unwrap()
  let definition = issue_run_definition(
    admission,
    "original-scope",
    "original-run",
    empty_initial_input_artifact_set_cid(),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T02:00:00.000Z",
    16384,
    128,
    8,
  ).unwrap()
  prepare_recorded_run_publication(
    admission,
    definition,
    prepare_result_definition(admission_test_cid("1"), "answer").unwrap(),
  ).unwrap()
}

///|
test "recorded cleanup graph requires every original checked identity" {
  let recorded = recorded_cleanup_graph_fixture()
  let facts = ["1", "a", "4", "2", "3", "c"].map(admission_test_cid)
  let check = (values : Array[String]) => {
    recorded_run_publication_matches_cleanup_graph(
      recorded,
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
      values[5],
    )
  }
  assert_true(check(facts))
  for index in 0..<facts.length() {
    let changed = facts.copy()
    changed[index] = admission_test_cid("f")
    assert_false(check(changed))
    changed[index] = ""
    assert_false(check(changed))
  }
  // Cleanup matching is independent of execution expiry and cannot renew it.
  assert_false(
    recorded_run_publication_current(recorded, "2026-10-07T00:00:00.000Z"),
  )
  assert_true(check(facts))
}

///|
test "recorded cleanup context cannot change scope run or lifetime" {
  let recorded = recorded_cleanup_graph_fixture()
  let values = [
    "original-scope", "original-run", "2026-09-18T00:00:00.000Z", "2026-09-18T02:00:00.000Z",
  ]
  let check = (facts : Array[String]) => {
    recorded_run_publication_has_original_context(
      recorded,
      facts[0],
      facts[1],
      facts[2],
      facts[3],
    )
  }
  assert_true(check(values))
  for index in 0..<values.length() {
    let changed = values.copy()
    changed[index] = "another-original"
    assert_false(check(changed))
  }
}
