///|
test "SQL MOD context preserves the same CTE ordinary Number view for coexisting consumers" {
  for
    sql in [
      "WITH t AS (SELECT 5 AS v) SELECT MOD(v,2) AS m, v AS original, v+1 AS n FROM t",
      "WITH t AS (SELECT 5 AS v), ordinary AS (SELECT v+1 AS n FROM t) SELECT MOD(v,2) AS m, v AS original, v+1 AS n FROM t",
    ] {
    let original = timestamp_sql_original(sql)
    let output = sql_integer_output(original, expected_columns=[
      ("m", @contract.Signed64Type),
      ("n", @contract.NumberType),
      ("original", @contract.NumberType),
    ])
    assert_eq(@execution.completed_row_count(output), 1)
    assert_eq(@execution.completed_column_count(output), 3)
    for i in 0..<3 {
      match @execution.completed_column_name(output, i) {
        Some("m") =>
          assert_true(
            @execution.completed_cell(output, 0, i)
            is Some(Captured(@values.Signed64(1L))),
          )
        Some("original") =>
          assert_true(
            @execution.completed_cell(output, 0, i) is Some(Number(5.0)),
          )
        Some("n") =>
          assert_true(
            @execution.completed_cell(output, 0, i) is Some(Number(6.0)),
          )
        _ => fail("private exact companion must not enter the original result")
      }
    }
  }
  let second_consumer = sql_integer_output(
    timestamp_sql_original(
      "WITH t AS (SELECT 5 AS v), ordinary AS (SELECT v+1 AS n FROM t), exact AS (SELECT MOD(v,2) AS m FROM t) SELECT n FROM ordinary",
    ),
    expected_columns=[("n", @contract.NumberType)],
  )
  assert_eq(@execution.completed_row_count(second_consumer), 1)
  assert_true(
    @execution.completed_cell(second_consumer, 0, 0) is Some(Number(6.0)),
  )
}

///|
test "original SQL MOD and DIV retain exact integer provenance through the CTE and UNION" {
  let fixture = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) "
  for
    (call, expected) in [
      ("MOD(v, 7)", [2L, 3L, 6L]),
      ("DIV(v, 7)", [1L, 2L, 4L]),
    ] {
    let output = sql_integer_output(
      timestamp_sql_original(fixture + "SELECT " + call + " AS x FROM t"),
    )
    assert_eq(@execution.completed_row_count(output), 3)
    assert_eq(@execution.completed_column_count(output), 1)
    assert_eq(@execution.completed_column_name(output, 0), Some("x"))
    let actual : Array[Int64] = []
    for row in 0..<3 {
      match @execution.completed_cell(output, row, 0) {
        Some(Captured(@values.Signed64(value))) => actual.push(value)
        _ => fail("the exact integer result must not become a Number")
      }
    }
    actual.sort()
    assert_eq(actual, expected, msg=call)
  }
}

///|
test "SQL integer function context retains full signed lexemes nullability and ordinary Number columns" {
  for
    (source, expected) in [
      (
        "WITH t AS (SELECT 9007199254740993 AS v) SELECT MOD(v, 2) AS x FROM t",
        1L,
      ),
      (
        "WITH t AS (SELECT -9223372036854775808 AS v) SELECT DIV(v, 1) AS x FROM t",
        -9223372036854775807L - 1L,
      ),
      (
        "WITH t AS (SELECT 0x7fffffffffffffff AS v) SELECT MOD(v, 2) AS x FROM t",
        1L,
      ),
      (
        "WITH a AS (SELECT -10 AS original), b AS (SELECT original AS v FROM a) SELECT MOD(v,-7) AS x FROM b",
        -3L,
      ),
    ] {
    assert_true(
      @execution.completed_cell(
        sql_integer_output(timestamp_sql_original(source)),
        0,
        0,
      )
      is Some(Captured(@values.Signed64(value))) &&
      value == expected,
      msg=source,
    )
  }
  let nullable = sql_integer_output(
    timestamp_sql_original(
      "WITH t AS (SELECT NULL AS v UNION ALL SELECT 10 AS v) SELECT MOD(v,7) AS x FROM t",
    ),
  )
  assert_eq(@execution.completed_row_count(nullable), 2)
  let mut nulls = 0
  let mut integers = 0
  for i in 0..<2 {
    match @execution.completed_cell(nullable, i, 0) {
      Some(Null) => nulls += 1
      Some(Captured(@values.Signed64(3L))) => integers += 1
      _ => fail("original nullable int64 union must retain both values")
    }
  }
  assert_eq((nulls, integers), (1, 1))
  // No integer signature requests this source column. Its original NUMBER
  // contract and value are preserved, independently of the integer spelling.
  assert_true(
    @execution.completed_cell(
      sql_integer_output(
        timestamp_sql_original("WITH t AS (SELECT 5 AS v) SELECT v AS x FROM t"),
      ),
      0,
      0,
    )
    is Some(Number(5.0)),
  )
}

///|
test "SQL MOD and DIV preserve exact Decimal coefficients and original operand signs" {
  for
    (source, coefficient, scale) in [
      (
        "MOD(CAST('-12.50' AS DECIMAL(6,2)),CAST('3.0' AS DECIMAL(3,1)))", "-50",
        2,
      ),
      (
        "MOD(CAST('12.50' AS DECIMAL(6,2)),CAST('-3.0' AS DECIMAL(3,1)))", "50",
        2,
      ),
      (
        "DIV(CAST('-12.50' AS DECIMAL(6,2)),CAST('3.0' AS DECIMAL(3,1)))", "-4",
        0,
      ),
      ("DIV(9007199254740993,CAST('1' AS DECIMAL(1,0)))", "9007199254740993", 0),
      ("MOD(CAST('12.50' AS DECIMAL(6,2)),3)", "50", 2),
    ] {
    let output = sql_integer_output(
      timestamp_sql_original("SELECT " + source + " AS x"),
    )
    assert_true(
      @execution.completed_cell(output, 0, 0)
      is Some(Captured(@values.Decimal(value))) &&
      value.coefficient == coefficient &&
      value.precision == 38 &&
      value.scale == scale,
      msg=source,
    )
  }
}

///|
fn sql_integer_output(
  original : PreparedClientProgram,
  expected_columns? : Array[(String, @contract.Primitive)] = [],
) -> @execution.CompletedOutput raise {
  let sequence = match
    @lower.prepare_sequence(
      @strategy.graph_task_owner(original.graph, 0).unwrap(),
      client_standard_values_sequence_limits(),
    ) {
    Ok(value) => value
    Err(SequenceLimit) =>
      fail("original CTE exceeds scalar fixture sequence inventory")
    Err(KernelFailure(step, ExpressionFailure(issue))) => {
      debug_inspect(issue.kind, content="original integer binding must lower")
      fail("kernel \{step}")
    }
    Err(KernelFailure(step, _)) => fail("original integer kernel \{step}")
    Err(ValuesFailure(step, _)) => fail("original Values \{step}")
    Err(AppendFailure(step, _)) => fail("original Append \{step}")
    Err(SetFailure(step, _)) => fail("original Set \{step}")
    Err(_) => fail("original sequence lowering outside expected operations")
  }
  if !expected_columns.is_empty() {
    let owner = @lower.bound_preparation(@lower.sequence_owner(sequence))
    let node = @lower.node_at(owner, @lower.sequence_count(sequence) - 1).unwrap()
    let schema = @lower.node_output_schema(node)
    assert_eq(@schema.field_count(schema), expected_columns.length())
    for i in 0..<@schema.field_count(schema) {
      let field = @schema.field_at(schema, i).unwrap()
      let name = @schema.reference_name(field.name)
      let mut found = None
      for (expected_name, kind) in expected_columns {
        if expected_name == name {
          found = Some(kind)
        }
      }
      guard found is Some(kind) else {
        fail("the full schema contains a private or unexpected column")
      }
      assert_true(
        @contract.type_equal(
          @schema.field_contract(field),
          @contract.primitive(kind, nullable=false),
          32,
        ),
      )
    }
  }
  // Reuse the existing full-sequence driver: a CTE/UNION has multiple original
  // expression kernels, rather than the scalar fixture's single step1.
  let completed = match
    @execution.execute_generated_sequence(
      local_group_generated(sequence),
      [],
      string_try_number_execution_limits(),
    ) {
    Ok(value) => value
    Err(Rows(step, Evaluation(row, slot, issue))) => {
      debug_inspect(
        issue.kind,
        content="original integer expression must execute",
      )
      fail("step=\{step}, row=\{row}, slot=\{slot}")
    }
    Err(Rows(step, RowLimit)) =>
      fail("original sequence resource limit at step \{step}")
    Err(Rows(step, _)) => fail("original sequence row failure at step \{step}")
    Err(MissingFragmentContext(step)) =>
      fail("original context missing at step \{step}")
    Err(_) => fail("original sequence failed outside row evaluation")
  }
  @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
}

///|
test "SQL exact integer context refuses floating spellings and declared Number originals" {
  for
    sql in [
      "SELECT MOD(5.0,2) AS x", "SELECT DIV(5e0,2) AS x", "WITH t AS (SELECT 5.0 AS v) SELECT MOD(v,2) AS x FROM t",
      "WITH t AS (SELECT CAST(5 AS NUMBER) AS v) SELECT DIV(v,2) AS x FROM t",
    ] {
    sql_integer_type_refusal(sql)
  }
  sql_integer_type_refusal(
    "SELECT MOD(@v,2) AS x",
    declarations="{\"v\":{\"type\":\"number\",\"default\":5}}",
  )
}

///|
test "SQL exact companion remains private under star collision and original alias chains" {
  let star = sql_integer_output(
    timestamp_sql_original(
      "WITH t AS (SELECT 5 AS v) SELECT t.*, MOD(v,2) AS m FROM t",
    ),
    expected_columns=[
      ("v", @contract.NumberType),
      ("m", @contract.Signed64Type),
    ],
  )
  assert_eq(@execution.completed_column_count(star), 2)
  for i in 0..<2 {
    if @execution.completed_column_name(star, i) == Some("v") {
      assert_true(@execution.completed_cell(star, 0, i) is Some(Number(5.0)))
    } else {
      assert_true(
        @execution.completed_cell(star, 0, i)
        is Some(Captured(@values.Signed64(1L))),
      )
    }
  }
  let collision = sql_integer_output(
    timestamp_sql_original(
      "WITH t AS (SELECT 5 AS v,99 AS aql_integer_1_0_0) SELECT MOD(v,2) AS m,aql_integer_1_0_0 AS original FROM t",
    ),
    expected_columns=[
      ("m", @contract.Signed64Type),
      ("original", @contract.NumberType),
    ],
  )
  for i in 0..<2 {
    if @execution.completed_column_name(collision, i) == Some("original") {
      assert_true(
        @execution.completed_cell(collision, 0, i) is Some(Number(99.0)),
      )
    }
  }
  let chain = sql_integer_output(
    timestamp_sql_original(
      "WITH a AS (SELECT 9007199254740993 AS v),b AS (SELECT v AS original FROM a) SELECT MOD(original,2) AS m FROM b",
    ),
    expected_columns=[("m", @contract.Signed64Type)],
  )
  assert_true(
    @execution.completed_cell(chain, 0, 0)
    is Some(Captured(@values.Signed64(1L))),
  )
  let environment = string_try_number_test_environment()
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  assert_true(
    @source_frontend.lower(
      "WITH t AS (SELECT 5 AS v) SELECT MOD(v,2) AS m,aql_integer_1_0_0 AS stolen FROM t",
      Sql,
      Some(context),
    )
    is Err(QueryLowering(Expression({ issue: UnknownReference, .. }))),
  )
}

///|
test "SQL exact companion cannot fabricate an unavailable ordinary Number view" {
  let environment = string_try_number_test_environment()
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  for
    suffix in [
      "SELECT MOD(v,2) AS m,v AS original FROM t", "SELECT t.*,MOD(v,2) AS m FROM t",
      "SELECT t AS original,MOD(v,2) AS m FROM t",
    ] {
    assert_true(
      @source_frontend.lower(
        "WITH t AS (SELECT 9007199254740993 AS v) " + suffix,
        Sql,
        Some(context),
      )
      is Err(QueryLowering(Expression({ issue: InvalidNumber, .. }))),
      msg=suffix,
    )
  }
}

///|
fn sql_integer_type_refusal(
  sql : String,
  declarations? : String = "{}",
) -> Unit raise {
  let environment = string_try_number_test_environment()
  let declared = @parameter.read_declarations(
    if declarations == "{}" {
      None
    } else {
      Some(scalar_profile_cursor(declarations))
    },
    {
      max_parameters: 100,
      max_nodes: 1000,
      max_depth: 32,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    parameter_declarations=if declarations == "{}" {
      None
    } else {
      Some(declared)
    },
  ).unwrap()
  let lowered = match @source_frontend.lower(sql, Sql, Some(context)) {
    Ok(value) => value
    Err(
      QueryLowering(
        BindingPreparation(
          LocalProgram(
            Pipeline(
              _,
              {
                kind: Operation(Expression(TypeMismatch("int64 or decimal"))),
                ..
              }
            )
          )
        )
      )
    ) => return
    Err(_) =>
      fail("an unrelated frontend refusal is not exact operand checking")
  }
  match
    prepare_parsed_effect_free_client_program(
      lowered.program.unwrap(),
      environment,
      None,
      client_standard_program_preparation_limits(),
    ) {
    Err(Check(issue)) =>
      match @checked.diagnostic_cause(issue) {
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(
            Program(
              Program(
                Pipeline(
                  _,
                  {
                    kind: Operation(
                      Expression(TypeMismatch("int64 or decimal"))
                    ),
                    ..
                  }
                )
              )
            )
          )
        ) => ()
        _ =>
          fail("an unrelated preparation failure is not exact operand checking")
      }
    _ => fail("a Number original must not be silently promoted to int64")
  }
}
