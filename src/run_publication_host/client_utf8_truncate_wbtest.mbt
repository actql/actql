///|
fn utf8_truncate_test_sequence(document : String) -> @lower.PreparedSequence {
  let limits = run_materials_limits()
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    string_try_number_test_environment(max_input_bytes=64),
    None,
    limits.preparation,
  ).unwrap()
  @lower.prepare_sequence(
    @strategy.graph_task_owner(prepared.graph, 0).unwrap(),
    limits.sequence,
  ).unwrap()
}

///|
fn utf8_truncate_test_document(rows : String, expression : String) -> String {
  let prefix =
    #|{"version":"actql/0.1","id":"utf8-prefix","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":true},"bytes":{"type":"number","nullable":true}},"rows":
  let middle =
    #|},"as":"input"},{"derive":{"prefix":
  let suffix =
    #|},"as":"shortened"}],"results":{"r":{"from":"shortened","fields":["prefix"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  prefix + rows + middle + expression + suffix
}

///|
test "original UTF8_TRUNCATE Program executes dynamic exact byte limits and nullable operands" {
  // The existing fixture budget permits ten cells. Keep every original case
  // in groups of at most five two-column rows instead of increasing its cap.
  let groups : Array[(String, Array[String?])] = [
    (
      (
        #|[{"text":"é😀éx","bytes":6},{"text":"é😀éx","bytes":8},{"text":"é😀éx","bytes":9},{"text":"é😀éx","bytes":0}]
      ),
      [Some("é😀"), Some("é😀e"), Some("é😀é"), Some("")],
    ),
    (
      (
        #|[{"text":null,"bytes":2},{"text":"x","bytes":null}]
      ),
      [None, None],
    ),
    (
      (
        #|[{"text":"x","bytes":9007199254740991}]
      ),
      [Some("x")],
    ),
  ]
  for (rows, expected) in groups {
    let document = utf8_truncate_test_document(
      rows, "\"utf8_truncate(text, bytes)\"",
    )
    // The existing fragment/registry caller retains this original sequence;
    // no detached expression or fabricated evaluation envelope is supplied.
    let generated = string_try_number_generated(
      utf8_truncate_test_sequence(document),
    )
    let result = @execution.execute_generated_sequence(
      generated,
      [],
      string_try_number_execution_limits(),
    ).unwrap()
    let output = @execution.completed_output(result, @pipeline.Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), expected.length())
    for index, expected in expected {
      let actual = @execution.completed_cell(output, index, 2)
      match expected {
        Some(expected) =>
          assert_true(actual is Some(Text(text)) && text == expected)
        None => assert_true(actual is Some(Null))
      }
    }
  }
}

///|
test "original UTF8_TRUNCATE Program refuses invalid demanded byte counts without rounding" {
  for count in ["-1", "0.5", "9007199254740992"] {
    let document = utf8_truncate_test_document(
      "[{\"text\":\"\",\"bytes\":" + count + "}]",
      "\"utf8_truncate(text, bytes)\"",
    )
    assert_true(
      @execution.execute_generated_sequence(
        string_try_number_generated(utf8_truncate_test_sequence(document)),
        [],
        string_try_number_execution_limits(),
      )
      is Err(Rows(1, Evaluation(0, 0, { kind: Scalar(InvalidOperand), .. }))),
      msg=count,
    )
  }
}

///|
test "original UTF8_TRUNCATE Program retains child failures and lazy input preflight" {
  let rows = "[{\"text\":\"" + "x".repeat(65) + "\",\"bytes\":0}]"
  let safe = utf8_truncate_test_document(
    rows, "\"if(TRUE, 'safe', utf8_truncate(text, bytes))\"",
  )
  let result = @execution.execute_generated_sequence(
    string_try_number_generated(utf8_truncate_test_sequence(safe)),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  assert_true(
    @execution.completed_cell(
      @execution.completed_output(result, @pipeline.Step(1)).unwrap(),
      0,
      2,
    )
    is Some(Text("safe")),
  )
  let demanded = utf8_truncate_test_document(
    rows, "\"utf8_truncate(text, bytes)\"",
  )
  assert_true(
    @execution.execute_generated_sequence(
      string_try_number_generated(utf8_truncate_test_sequence(demanded)),
      [],
      string_try_number_execution_limits(),
    )
    is Err(Rows(1, Evaluation(0, 0, { kind: TextBounds(InputCeiling), .. }))),
  )
  let failing_child = utf8_truncate_test_document(
    "[{\"text\":null,\"bytes\":0}]", "\"utf8_truncate(text, 1 / 0)\"",
  )
  assert_true(
    @execution.execute_generated_sequence(
      string_try_number_generated(utf8_truncate_test_sequence(failing_child)),
      [],
      string_try_number_execution_limits(),
    )
    is Err(Rows(1, Evaluation(0, 0, { kind: Scalar(ArithmeticFailure), .. }))),
  )
}
