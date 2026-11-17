///|
test "selected SQL LIKE and NOT LIKE produce exact common Boolean Results" {
  for
    (sql, expected) in [
      ("SELECT 'abc' LIKE 'a%' AS matched", true),
      ("SELECT 'abc' NOT LIKE 'a%' AS matched", false),
    ] {
    let original = timestamp_sql_original(sql)
    let sequence = match
      @lower.prepare_sequence(
        @strategy.graph_task_owner(original.graph, 0).unwrap(),
        run_materials_limits().sequence,
      ) {
      Ok(value) => value
      Err(KernelFailure(_, ExpressionFailure(issue))) =>
        fail("original LIKE lowering: " + @debug.to_string(issue.kind))
      Err(_) => fail("original LIKE sequence preparation")
    }
    let completed = @execution.execute_generated_sequence(
      local_explicit_cast_generated(sequence),
      [],
      string_try_number_execution_limits(),
    ).unwrap()
    let output = @execution.completed_output(
      completed,
      @pipeline.Step(@lower.sequence_count(sequence) - 1),
    ).unwrap()
    assert_eq(@execution.completed_row_count(output), 1)
    assert_true(
      @execution.completed_cell(output, 0, 0) is Some(Boolean(value)) &&
      value == expected,
    )
  }
}

///|
test "LIKE retains exact Unicode scalar wildcard escape and NULL semantics" {
  for
    (value, pattern, expected) in [
      ("", "", true),
      ("", "%", true),
      ("", "_", false),
      ("abc", "", false),
      ("abc", "a_c", true),
      ("abc", "a_d", false),
      ("abbbbc", "a%b%c", true),
      ("abbbbc", "%b%d", false),
      ("😀", "_", true),
      ("😀", "__", false),
      ("😀x", "_%", true),
      ("é", "é", false),
      ("a%b", "a\\%b", true),
      ("a_b", "a\\_b", true),
      ("😀", "\\😀", true),
    ] {
    let sql = "SELECT '" + value + "' LIKE r'" + pattern + "' AS matched"
    let output = timestamp_sql_output(timestamp_sql_original(sql))
    assert_true(
      @execution.completed_cell(output, 0, 0) is Some(Boolean(observed)) &&
      observed == expected,
      msg=sql,
    )
  }
  let null = timestamp_sql_output(
    timestamp_sql_original("SELECT CAST(NULL AS STRING) LIKE 'a%' AS matched"),
  )
  assert_true(@execution.completed_cell(null, 0, 0) is Some(Null))
}

///|
test "LIKE uses the original supplied or Default Parameter and refuses a foreign closure" {
  let declarations = "{\"pattern\":{\"type\":\"string\",\"default\":\"a%\"},\"value\":{\"type\":\"string\",\"default\":\"abc\"}}"
  let sql = "SELECT @value LIKE @pattern AS matched"
  let defaulted = timestamp_sql_original(sql, declarations~)
  let supplied = timestamp_sql_original(
    sql,
    declarations~,
    supplied=Some("{\"pattern\":\"b%\",\"value\":\"abc\"}"),
  )
  assert_true(
    @execution.completed_cell(timestamp_sql_output(defaulted), 0, 0)
    is Some(Boolean(true)),
  )
  assert_true(
    @execution.completed_cell(timestamp_sql_output(supplied), 0, 0)
    is Some(Boolean(false)),
  )
  let closure = @checked.expression_closure(
    @strategy.graph_program(supplied.graph),
  ).unwrap()
  let owner = @lower.sequence_owner(
    @lower.prepare_sequence(
      @strategy.graph_task_owner(defaulted.graph, 0).unwrap(),
      run_materials_limits().sequence,
    ).unwrap(),
  )
  assert_true(
    @lower.bind_program_expression_closure(owner, closure, 0, 100000)
    is Err({ kind: BindingOwnerMismatch, .. }),
  )
}

///|
fn sql_like_expression(
  original : PreparedClientProgram,
) -> @lower.Expression raise {
  let sequence = @lower.prepare_sequence(
    @strategy.graph_task_owner(original.graph, 0).unwrap(),
    run_materials_limits().sequence,
  ).unwrap()
  for index in 0..<@lower.sequence_count(sequence) {
    if @lower.sequence_step(sequence, index) is Some(RowStep(kernel)) &&
      @lower.kernel_bindings(kernel) is Some(bindings) &&
      @lower.binding_at(bindings, 0) is Some((_, expression)) {
      return expression
    }
  }
  fail("expected original LIKE binding")
}

///|
test "LIKE repeated-prefix work remains observable bounded and cancellable" {
  let text = "a".repeat(128) + "c"
  let original = timestamp_sql_original(
    "SELECT '" + text + "' LIKE '%aaaaab' AS matched",
  )
  let expression = sql_like_expression(original)
  let execution = @execution.start_expression_execution(
    expression,
    Map([]),
    [],
    100000,
    100,
    100,
  ).unwrap()
  let mut finished = false
  let mut polls = 0
  while !finished && polls < 10000 {
    let before = @execution.expression_execution_remaining(execution)
    match @execution.advance_expression_execution(execution) {
      Ok(ExpressionContinue) => ()
      Ok(ExpressionComplete(value)) => {
        assert_true(value is Boolean(false))
        finished = true
      }
      Err(_) => fail("original LIKE bounded execution refused")
    }
    assert_true(
      before - @execution.expression_execution_remaining(execution) <= 64,
    )
    polls += 1
  }
  assert_true(finished)
  assert_true(polls > 128)
  let used = 100000 - @execution.expression_execution_remaining(execution)
  let short = @execution.start_expression_execution(
    expression,
    Map([]),
    [],
    used - 1,
    100,
    100,
  ).unwrap()
  let mut refused = false
  for _ in 0..<(polls + 1) {
    match @execution.advance_expression_execution(short) {
      Err({ kind: ControlLimit, .. }) => {
        refused = true
        break
      }
      Ok(ExpressionContinue) => ()
      _ => fail("one-short LIKE control must refuse")
    }
  }
  assert_true(refused)
  let cancelled = @execution.start_expression_execution(
    expression,
    Map([]),
    [],
    100000,
    100,
    100,
  ).unwrap()
  for _ in 0..<10 {
    assert_true(
      @execution.advance_expression_execution(cancelled)
      is Ok(ExpressionContinue),
    )
  }
  assert_true(@execution.cancel_expression_execution(cancelled))
  assert_true(@execution.cancel_expression_execution(cancelled))
  assert_true(
    @execution.advance_expression_execution(cancelled)
    is Err({ kind: InvalidControlLimits, .. }),
  )
}

///|
test "LIKE emits the existing independent node wire and cannot use the scalar fallback" {
  let expression = sql_like_expression(
    timestamp_sql_original("SELECT 'abc' LIKE 'a%' AS matched"),
  )
  assert_eq(@lower.expression_like_pattern_source(expression), Some("a%"))
  let writer = @encode.writer(4096, 100, 16)
  @lower.emit_expression(expression, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":[{\"body\":\"abc\",\"op\":\"literal\"},{\"body\":\"a%\",\"op\":\"literal\"}],\"op\":\"like\"}",
  )
  assert_true(
    @execution.binary(@lower.Like, Text("abc"), Text("a%"))
    is Err(InvalidOperand),
  )
  assert_true(
    @execution.binary(@lower.Like, Null, Text("a%")) is Err(InvalidOperand),
  )
}

///|
test "LIKE admits its three original aliases before cursor construction at exact workspace" {
  let expression = sql_like_expression(
    timestamp_sql_original("SELECT 'abc' LIKE 'a%' AS matched"),
  )
  for slots in [2, 3] {
    let execution = @execution.start_expression_execution(
      expression,
      Map([]),
      [],
      10000,
      100,
      slots,
    ).unwrap()
    let mut finished = false
    for _ in 0..<100 {
      match @execution.advance_expression_execution(execution) {
        Ok(ExpressionContinue) => ()
        Ok(ExpressionComplete(value)) => {
          assert_eq(slots, 3)
          assert_true(value is Boolean(true))
          finished = true
          break
        }
        Err({ kind: WorkspaceLimit, .. }) => {
          assert_eq(slots, 2)
          finished = true
          break
        }
        _ => fail("unexpected LIKE alias admission result")
      }
    }
    assert_true(finished)
    assert_true(@execution.cancel_expression_execution(execution))
  }
}
