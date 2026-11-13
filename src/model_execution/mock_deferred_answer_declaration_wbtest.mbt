///|
fn deferred_mock_declaration_fixture() -> (
  ModelMockInstallation,
  ModelMockInstallation,
) {
  let bound = mock_installation_test_original()
  let declared = prepare_original_model_mock(
    bound.profile.unwrap(),
    bound.declaration.unwrap(),
    bound.normalized.unwrap(),
    () => "2026-11-12T00:00:00.000Z",
  ).unwrap()
  (declared, bound)
}

///|
test "Mock declaration metadata needs no answer DATA and grants no ready invocation" {
  let (declared, bound) = deferred_mock_declaration_fixture()
  assert_true(declared.answers is None)
  assert_true(
    physical_equal(
      original_model_mock_declaration(declared).unwrap(),
      bound.normalized.unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      original_model_mock_provider(declared).unwrap(),
      declared.provider.unwrap(),
    ),
  )
  assert_true(declared.require_original() is Err(MissingAnswer))
  assert_eq(declared.users, 0)
  retire_original_model_mock(declared).unwrap() |> ignore
  assert_true(original_model_mock_declaration(declared) is Err(Retired))
  assert_true(original_model_mock_provider(declared) is Err(Retired))
}

///|
test "Mock deferred answer binding requires the same original Task and never replaces an answer" {
  let (declared, bound) = deferred_mock_declaration_fixture()
  let foreign = mock_installation_test_original()
  assert_true(
    bind_original_model_mock_answers(declared, foreign.answers.unwrap())
    is Err(Answers(ForeignOriginal)),
  )
  assert_true(declared.answers is None)
  bind_original_model_mock_answers(declared, bound.answers.unwrap()).unwrap()
  assert_true(declared.require_original() is Ok(_))
  bind_original_model_mock_answers(declared, bound.answers.unwrap()).unwrap()
  assert_true(
    bind_original_model_mock_answers(declared, foreign.answers.unwrap())
    is Err(ForeignOriginal),
  )
  retire_model_mock_answers(bound.answers.unwrap(), bound.declaration.unwrap()).unwrap()
  assert_true(original_model_mock_provider(declared) is Err(Answers(Retired)))
}

///|
test "Mock deferred declaration preserves copied foreign profile and retirement refusals" {
  let (declared, bound) = deferred_mock_declaration_fixture()
  assert_true(
    original_model_mock_declaration({ ..declared, }) is Err(ForeignOriginal),
  )
  let foreign = mock_installation_test_original()
  assert_true(
    prepare_original_model_mock(
      foreign.profile.unwrap(),
      bound.declaration.unwrap(),
      bound.normalized.unwrap(),
      () => "unused",
    )
    is Err(ForeignOriginal),
  )
  retire_original_model_mock(declared).unwrap() |> ignore
  assert_true(
    bind_original_model_mock_answers(declared, bound.answers.unwrap())
    is Err(Retired),
  )
  assert_true(@environment.retire_model_mock_profile(bound.profile.unwrap()))
  assert_true(original_model_mock_provider(bound) is Err(ForeignOriginal))
}
