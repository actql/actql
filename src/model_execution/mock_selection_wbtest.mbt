///|
fn mock_selection_text(value : String) -> @admitted.CheckedValue {
  @admitted.checked_text_value(
    value,
    @contract.primitive(@contract.StringType, nullable=false),
  ).unwrap()
}

///|
fn mock_selection_enabled(value : @admitted.CheckedValue) -> Bool {
  value.value is @admitted.Object(fields) &&
  @admitted.element_at(fields, 0) is Some(("enabled", @admitted.Boolean(true)))
}

///|
test "mock exact single Text overrides never convert numeric or composite keys" {
  let task = mock_answer_task()
  let answers = read_model_mock_answer_document(
    task,
    mock_answer_wire(
      "{\"default\":{\"enabled\":false},\"by_key\":{\"1\":{\"enabled\":true},\"a|b\":{\"enabled\":true}}}",
    ),
    "json",
    mock_answer_limits(),
  ).unwrap()
  assert_true(
    mock_selection_enabled(
      select_mock_answer(answers, task, [mock_selection_text("1")]).unwrap(),
    ),
  )
  let number = @admitted.recheck_runtime_value(
    @admitted.number_value(1).unwrap(),
    @contract.primitive(@contract.NumberType, nullable=false),
    mock_answer_limits().values,
  ).unwrap()
  let integer = @admitted.recheck_runtime_value(
    @admitted.signed64_value(1L),
    @contract.primitive(@contract.Signed64Type, nullable=false),
    mock_answer_limits().values,
  ).unwrap()
  assert_false(
    mock_selection_enabled(select_mock_answer(answers, task, [number]).unwrap()),
  )
  assert_false(
    mock_selection_enabled(
      select_mock_answer(answers, task, [integer]).unwrap(),
    ),
  )
  assert_false(
    mock_selection_enabled(
      select_mock_answer(answers, task, [
        mock_selection_text("a"),
        mock_selection_text("b"),
      ]).unwrap(),
    ),
  )
  assert_true(
    mock_selection_enabled(
      select_mock_answer(answers, task, [mock_selection_text("a|b")]).unwrap(),
    ),
  )
}

///|
test "mock Unicode and JSON-looking Text labels remain literal and distinct" {
  let task = mock_answer_task()
  let answers = read_model_mock_answer_document(
    task,
    mock_answer_wire(
      "{\"default\":{\"enabled\":false},\"by_key\":{\"é\":{\"enabled\":true},\"[1,2]\":{\"enabled\":true}}}",
    ),
    "json",
    mock_answer_limits(),
  ).unwrap()
  assert_true(
    mock_selection_enabled(
      select_mock_answer(answers, task, [mock_selection_text("é")]).unwrap(),
    ),
  )
  assert_false(
    mock_selection_enabled(
      select_mock_answer(answers, task, [mock_selection_text("e\u{0301}")]).unwrap(),
    ),
  )
  assert_false(
    mock_selection_enabled(
      select_mock_answer(answers, task, [mock_selection_text(" é")]).unwrap(),
    ),
  )
  assert_true(
    mock_selection_enabled(
      select_mock_answer(answers, task, [mock_selection_text("[1,2]")]).unwrap(),
    ),
  )
}

///|
test "mock explicit default supports valid tuples without an override grammar" {
  let task = mock_answer_task()
  let answers = read_model_mock_answer_document(
    task,
    mock_answer_wire("{\"default\":{\"enabled\":true}}"),
    "json",
    mock_answer_limits(),
  ).unwrap()
  let number = @admitted.recheck_runtime_value(
    @admitted.number_value(1).unwrap(),
    @contract.primitive(@contract.NumberType, nullable=false),
    mock_answer_limits().values,
  ).unwrap()
  assert_true(
    mock_selection_enabled(select_mock_answer(answers, task, [number]).unwrap()),
  )
  assert_true(
    mock_selection_enabled(
      select_mock_answer(answers, task, [mock_selection_text("a"), number]).unwrap(),
    ),
  )
}

///|
test "mock missing answer and foreign copied or retired originals do not gain default" {
  let task = mock_answer_task()
  let empty = read_model_mock_answer_document(
    task,
    mock_answer_wire("{}"),
    "json",
    mock_answer_limits(),
  ).unwrap()
  assert_true(
    select_mock_answer(empty, task, [mock_selection_text("missing")])
    is Err(MissingAnswer),
  )
  let answers = read_model_mock_answer_document(
    task,
    mock_answer_wire("{\"default\":{\"enabled\":true}}"),
    "json",
    mock_answer_limits(),
  ).unwrap()
  assert_true(
    select_mock_answer(answers, mock_answer_task(), [mock_selection_text("x")])
    is Err(Answers(ForeignOriginal)),
  )
  let copied = { ..answers, }
  assert_true(
    select_mock_answer(copied, task, [mock_selection_text("x")])
    is Err(Answers(ForeignOriginal)),
  )
  retire_model_mock_answers(answers, task).unwrap()
  assert_true(
    select_mock_answer(answers, task, [mock_selection_text("x")])
    is Err(Answers(Retired)),
  )
}

///|
fn mock_installation_test_original() -> ModelMockInstallation {
  let task = mock_answer_task()
  let limits : @environment.ModelTaskLimits = {
    bodies: mock_answer_limits().document,
    contracts: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
    max_work: 1000000,
  }
  let profile = @environment.install_model_mock_profile(limits).unwrap()
  let normalized = @environment.normalize_public_mock_model_task(
    task, profile, limits,
  ).unwrap()
  let answers = read_model_mock_answer_document(
    task,
    mock_answer_wire("{\"default\":{\"enabled\":true}}"),
    "json",
    mock_answer_limits(),
  ).unwrap()
  install_original_model_mock(profile, task, normalized, answers, () => {
    "2026-10-19T00:00:00.000Z"
  }).unwrap()
}

///|
test "mock installation refuses copied and foreign originals and retires its clock alias" {
  let original = mock_installation_test_original()
  let copied = { ..original, }
  assert_true(original_model_mock_provider(copied) is Err(ForeignOriginal))
  assert_true(retire_original_model_mock(copied) is Err(ForeignOriginal))
  let other = mock_installation_test_original()
  assert_true(
    install_original_model_mock(
      original.profile.unwrap(),
      original.declaration.unwrap(),
      original.normalized.unwrap(),
      other.answers.unwrap(),
      () => "unused",
    )
    is Err(Answers(ForeignOriginal)),
  )
  assert_eq(retire_original_model_mock(original), Ok(true))
  assert_true(original.now is None)
  assert_true(original_model_mock_provider(original) is Err(Retired))
  assert_eq(retire_original_model_mock(other), Ok(true))
}

///|
test "mock retired child DATA cannot prevent the original installation cleanup" {
  let original = mock_installation_test_original()
  retire_model_mock_answers(
    original.answers.unwrap(),
    original.declaration.unwrap(),
  ).unwrap()
  assert_true(original_model_mock_provider(original) is Err(Answers(Retired)))
  assert_eq(retire_original_model_mock(original), Ok(true))
  assert_true(original.now is None)
}
