///|
fn profile_project() -> ClientProjectConfiguration {
  admit_client_project_configuration(
    "{\"version\":\"actql-config/0.1\",\"profile\":\"mock\",\"mock\":{\"catalog\":\"./catalog-é.json\",\"data\":\"./data.json\",\"answers\":{\"task:é\":\"./answer.yaml\"}}}",
  ).unwrap()
}

///|
test "project profile retains the same original default and mock locators" {
  let configuration = profile_project()
  let selected = select_client_project_profile(Some(configuration), None, 0).unwrap()
  assert_true(
    client_project_profile_matches(selected, Some(configuration), None),
  )
  assert_eq(selected.selected_profile(), Ok(Some("mock")))
  assert_eq(selected.mock_catalog_file(), Ok(Some("./catalog-é.json")))
  assert_eq(selected.mock_data_file(), Ok(Some("./data.json")))
  assert_eq(selected.mock_answer_count(), Ok(1))
  assert_eq(selected.mock_answer_at(0), Ok(Some(("task:é", "./answer.yaml"))))
  assert_eq(selected.mock_answer_at(-1), Ok(None))
  assert_eq(selected.mock_answer_at(1), Ok(None))
}

///|
test "project profile override keeps exact text without acquiring mock originals" {
  let configuration = profile_project()
  let selected = select_client_project_profile(
    Some(configuration),
    Some("profile:é"),
    128,
  ).unwrap()
  assert_eq(selected.selected_profile(), Ok(Some("profile:é")))
  assert_true(
    client_project_profile_matches(
      selected,
      Some(configuration),
      Some("profile:é"),
    ),
  )
  assert_false(
    client_project_profile_matches(
      selected,
      Some(configuration),
      Some("profile:é"),
    ),
  )
  assert_eq(selected.mock_catalog_file(), Ok(None))
  assert_eq(selected.mock_data_file(), Ok(None))
  assert_eq(selected.mock_answer_count(), Ok(0))
  assert_eq(selected.mock_answer_at(0), Ok(None))
}

///|
test "project profile refuses copied selection foreign equal project and changed choice" {
  let configuration = profile_project()
  let foreign = profile_project()
  let selected = select_client_project_profile(Some(configuration), None, 0).unwrap()
  assert_false(
    client_project_profile_matches({ ..selected, }, Some(configuration), None),
  )
  assert_eq({ ..selected, }.selected_profile(), Err(ForeignOriginal))
  assert_eq({ ..selected, }.mock_catalog_file(), Err(ForeignOriginal))
  assert_false(client_project_profile_matches(selected, Some(foreign), None))
  assert_false(client_project_profile_matches(selected, None, None))
  assert_false(
    client_project_profile_matches(selected, Some(configuration), Some("mock")),
  )
}

///|
test "project profile original absence and explicit mock never synthesize material" {
  let absent = select_client_project_profile(None, None, 0).unwrap()
  assert_true(client_project_profile_matches(absent, None, None))
  assert_eq(absent.selected_profile(), Ok(None))
  assert_eq(absent.mock_catalog_file(), Ok(None))
  assert_eq(absent.mock_answer_count(), Ok(0))
  let mock = select_client_project_profile(None, Some("mock"), 4).unwrap()
  assert_true(client_project_profile_matches(mock, None, Some("mock")))
  assert_eq(mock.selected_profile(), Ok(Some("mock")))
  assert_eq(mock.mock_catalog_file(), Ok(None))
  assert_eq(mock.mock_data_file(), Ok(None))
  assert_eq(mock.mock_answer_count(), Ok(0))
}

///|
test "project profile rejects invalid or unbounded choice before retaining it" {
  assert_true(
    select_client_project_profile(None, Some("mock"), -1) is Err(InvalidLimits),
  )
  assert_true(
    select_client_project_profile(None, Some("mock"), 3) is Err(WorkLimit),
  )
  assert_true(
    select_client_project_profile(None, Some(""), 4) is Err(InvalidProfile),
  )
  assert_true(
    select_client_project_profile(None, Some("m\u{0000}k"), 4)
    is Err(InvalidProfile),
  )
}

///|
test "project profile retirement severs originals without acknowledging physical duties" {
  let configuration = profile_project()
  let selected = select_client_project_profile(Some(configuration), None, 0).unwrap()
  assert_eq(
    retire_client_project_profile({ ..selected, }),
    Err(ForeignOriginal),
  )
  assert_eq(selected.selected_profile(), Ok(Some("mock")))
  retire_client_project_profile(selected).unwrap()
  assert_true(selected.configuration is None)
  assert_eq(selected.requested, None)
  assert_eq(selected.selected, None)
  assert_true(selected.original is None)
  assert_false(
    client_project_profile_matches(selected, Some(configuration), None),
  )
  assert_eq(selected.selected_profile(), Err(Retired))
  assert_eq(selected.mock_catalog_file(), Err(Retired))
  assert_eq(selected.mock_data_file(), Err(Retired))
  assert_eq(selected.mock_answer_count(), Err(Retired))
  assert_eq(selected.mock_answer_at(0), Err(Retired))
  assert_eq(retire_client_project_profile(selected), Err(Retired))
}
