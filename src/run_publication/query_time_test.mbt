///|
fn query_time_test_original() -> (RunPublicationAdmission, PublicationContract) {
  let template = admission_test_template()
  let plan = admission_test_plan(admission_test_cid("1"))
  let prepared = admission_test_prepared(template, plan, "allow")
  let authorization = admission_test_authorization(prepared, "allowed", false)
  let admission = admit_run_publication(template, prepared, authorization, plan).unwrap()
  let definition = issue_run_definition(
    admission,
    "scope",
    "original-query",
    admission_test_cid("b"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T02:00:00.000Z",
    16384,
    128,
    8,
  ).unwrap()
  (admission, definition)
}

///|
test "query evaluation time retains the original admitted definition and exact value" {
  let (admission, definition) = query_time_test_original()
  let time = bind_query_evaluation_time(
    admission,
    definition,
    admission_test_cid("1"),
    admission_test_cid("a"),
    admission_test_cid("4"),
  ).unwrap()
  assert_true(query_evaluation_time_matches(time, admission, definition))
  assert_true(
    physical_equal(query_evaluation_time_definition(time), definition),
  )
  assert_true(
    query_evaluation_time_value(time).value
    is @admitted.Timestamp("2026-09-18T00:00:00.000Z"),
  )
  let copied_definition = admit_publication_contract(
    "run_definition",
    publication_contract_json(definition),
    16384,
    128,
    8,
  ).unwrap()
  assert_eq(
    publication_contract_identity(copied_definition),
    publication_contract_identity(definition),
  )
  assert_false(
    query_evaluation_time_matches(time, admission, copied_definition),
  )
  let (foreign_admission, foreign_definition) = query_time_test_original()
  assert_false(
    query_evaluation_time_matches(time, foreign_admission, definition),
  )
  assert_false(
    query_evaluation_time_matches(time, admission, foreign_definition),
  )
  assert_true(
    query_evaluation_time_value(time).value
    is @admitted.Timestamp("2026-09-18T00:00:00.000Z"),
  )
}

///|
test "query evaluation time refuses foreign checked Program and environment bindings" {
  let (admission, definition) = query_time_test_original()
  assert_true(
    bind_query_evaluation_time(
      admission,
      definition,
      admission_test_cid("2"),
      admission_test_cid("a"),
      admission_test_cid("4"),
    )
    is Err(RunProgramForeignPlan),
  )
  assert_true(
    bind_query_evaluation_time(
      admission,
      definition,
      admission_test_cid("1"),
      admission_test_cid("b"),
      admission_test_cid("4"),
    )
    is Err(RunProgramForeignPlan),
  )
  assert_true(
    bind_query_evaluation_time(
      admission,
      definition,
      admission_test_cid("1"),
      admission_test_cid("a"),
      admission_test_cid("5"),
    )
    is Err(RunProgramForeignTemplate),
  )
  let other = issue_run_definition(
    admission,
    "scope",
    "later-query",
    admission_test_cid("b"),
    "2026-09-18T00:00:01.000Z",
    "2026-09-18T02:00:00.000Z",
    16384,
    128,
    8,
  ).unwrap()
  let later = bind_query_evaluation_time(
    admission,
    other,
    admission_test_cid("1"),
    admission_test_cid("a"),
    admission_test_cid("4"),
  ).unwrap()
  assert_true(
    query_evaluation_time_value(later).value
    is @admitted.Timestamp("2026-09-18T00:00:01.000Z"),
  )
}
