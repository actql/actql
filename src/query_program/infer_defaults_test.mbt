///|
fn compile_infer_defaults(
  text : String,
  context : Context,
  script : Bool,
  source_path? : String = "defaults.sql",
) -> Result[@program.Program, Issue] {
  if script {
    compile_query_script(
      @query.parse_query_script(text, syntax_limits(), source_path~).unwrap(),
      context,
      construction_limits(),
    )
  } else {
    compile(
      @query.parse_query(text, syntax_limits(), source_path~).unwrap(),
      context,
      construction_limits(),
    )
  }
}

///|
// Independently authored closed-object Values control for member rewriting.
// This uses the admitted object schema; no unsupported STRUCT parser surface
// or observed product output is used to create the fixture's expectation.
fn infer_defaults_object_context(
  environment : @check.CheckEnvironment,
) -> Context {
  let source = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true},"secret":{"type":"string","nullable":false},"note_object":{"type":"object","nullable":false,"additional_properties":false,"fields":{"notes":{"type":"string","nullable":true}}}},"rows":[{"id":"a","text":"urgent","secret":"private-a","note_object":{"notes":"urgent"}},{"id":"b","text":null,"secret":"private-b","note_object":{"notes":null}}]},"as":"tickets"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..infer_member_context(environment),
    program_id: "fixture.infer_keep",
    inputs: [
      {
        relation: [{ value: "tickets", quoted: false, }],
        name: "tickets",
        source: GeneratedValues(source),
        visible_fields: ["id", "text", "secret", "note_object"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn infer_defaults_prefix_refusal(
  result : Result[@program.Program, Issue],
) -> @pipeline.IssueKind raise {
  match result {
    Err(BindingPreparation(LocalProgram(Pipeline(_, issue)))) => issue.kind
    Err(issue) =>
      fail(
        "expected the original Common pipeline refusal in BindingPreparation: " +
        @debug.to_string(issue),
      )
    Ok(_) => fail("unproved omitted ITEM KEY must not compile")
  }
}

///|
fn infer_defaults_final_refusal(
  program : @program.Program,
  environment : @check.CheckEnvironment,
) -> @pipeline.IssueKind raise {
  guard @check.check_parsed(program, environment, None, check_limits())
    is Rejected(error) else {
    fail("expected the final Common pipeline refusal")
  }
  assert_eq(@check.diagnostic_category(error), @check.InvalidInput)
  match @check.diagnostic_cause(error) {
    Source(SourceView(Program(Program(Pipeline(_, issue))))) => issue.kind
    other => raise other
  }
}

///|
test "INFER defaults normalize to explicit sole and composite proven tuples" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  for
    (prefix, key) in [
      ("FROM tickets |> ASSERT UNIQUE BY (id)", "id"),
      ("FROM tickets |> ASSERT UNIQUE BY (id) |> RENAME id AS ticket", "ticket"),
      ("FROM tickets |> ASSERT UNIQUE BY (secret, id)", "secret, id"),
      ("FROM tickets |> ASSERT UNIQUE BY (id) |> ASSERT UNIQUE BY (id)", "id"),
      ("FROM tickets |> SELECT DISTINCT id |> EXTEND 'urgent' AS text", "id"),
      (
        "FROM tickets AS old |> ASSERT UNIQUE BY (id) |> SET id = secret", "old.id",
      ),
      (
        "FROM tickets |> SET id = secret |> ASSERT UNIQUE BY (id) |> AS snapshot |> SET id = 'same'",
        "snapshot.id",
      ),
    ] {
    for script in [false, true] {
      let explicit = prefix +
        " |> INFER `model-task:risk-score.v1` ITEM KEY (" +
        key +
        ") INPUT (text = text) KEEP (*) AS assessment"
      let expected = compile_infer_defaults(explicit, context, script).unwrap()
      let checked = check_shorthand_identity_program(expected, environment)
      for
        actual in [
          explicit.replace(old=" KEEP (*)", new=""),
          explicit.replace(old=" ITEM KEY (" + key + ")", new=""),
          explicit
          .replace(old=" ITEM KEY (" + key + ")", new="")
          .replace(old=" KEEP (*)", new=""),
        ] {
        let program = compile_infer_defaults(actual, context, script).unwrap()
        assert_eq(semantic(program), semantic(expected), msg=actual)
        assert_shorthand_checked_identity(
          check_shorthand_identity_program(program, environment),
          checked,
        )
      }
    }
  }
}

///|
test "sequential INFER defaults retain the original key through join-back and RESULT" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  for checkpoint in ["", " |> RESULT first_pass"] {
    let expanded = "FROM tickets |> ASSERT UNIQUE BY (id) " +
      "|> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text) KEEP (*) AS first_assessment" +
      checkpoint +
      " |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text) KEEP (*) AS second_assessment"
    for script in [false, true] {
      let expected = match compile_infer_defaults(expanded, context, script) {
        Ok(program) => program
        Err(issue) =>
          fail("explicit member control: " + @debug.to_string(issue))
      }
      let actual = compile_infer_defaults(
        expanded
        .replace(old=" ITEM KEY (id)", new="")
        .replace(old=" KEEP (*)", new=""),
        context,
        script,
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected), msg=checkpoint)
      let checked = check_shorthand_identity_program(actual, environment)
      assert_shorthand_checked_identity(
        checked,
        check_shorthand_identity_program(expected, environment),
      )
      assert_true(
        semantic(actual).contains(
          "\"fields\":[\"id\",\"text\",\"secret\",\"first_assessment\",\"second_assessment\"]",
        ),
      )
      let mut count = 0
      for unit in 0..<@check.unit_count(checked) {
        let pipeline = @check.unit_pipeline(checked, unit).unwrap()
        for step in 0..<@pipeline.step_count(pipeline) {
          if @pipeline.step_at(pipeline, step).unwrap().operation
            is @pipeline.Infer(infer) {
            count += 1
            assert_eq(@evidence.infer_key_count(infer), 1)
            assert_eq(
              @schema.reference_name(
                @evidence.infer_key_at(infer, 0).unwrap().field,
              ),
              "id",
            )
            assert_eq(@evidence.infer_input_binding_count(infer), 1)
            assert_eq(
              @evidence.infer_input_binding_at(infer, 0).unwrap().role,
              "text",
            )
          }
        }
      }
      assert_eq(count, 2)
    }
  }
}

///|
test "computed two-input JOIN projections retain Common key inference" {
  let environment = infer_member_environment()
  let context = {
    ..infer_member_context(environment),
    inputs: join_order_context().inputs,
  }
  for
    prefix in [
      "SELECT t.x AS id, t.y + r.k AS amount FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 2",
      "FROM t |> JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 2 |> SELECT t.x AS id, t.y + r.k AS amount",
    ] {
    // The original JOIN is retained and checked before this authored assertion.
    // The frontend does not infer uniqueness from the selected expression.
    let expanded = prefix +
      " |> ASSERT UNIQUE BY (id) |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text = 'urgent') KEEP (*) AS assessment"
    for script in [false, true] {
      let expected = match compile_infer_defaults(expanded, context, script) {
        Ok(program) => program
        Err(issue) =>
          fail("explicit member control: " + @debug.to_string(issue))
      }
      let actual = compile_infer_defaults(
        expanded
        .replace(old=" ITEM KEY (id)", new="")
        .replace(old=" KEEP (*)", new=""),
        context,
        script,
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected), msg=prefix)
      assert_true(semantic(actual).contains("\"add\":"))
      assert_true(
        semantic(actual).contains(
          "\"fields\":[\"id\",\"amount\",\"assessment\"]",
        ),
      )
      assert_shorthand_checked_identity(
        check_shorthand_identity_program(actual, environment),
        check_shorthand_identity_program(expected, environment),
      )
    }
  }
}

///|
test "unnameable proven ITEM KEY currently fails closed at the representation gap" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  let text = "FROM tickets |> SET id = secret |> ASSERT UNIQUE BY (id) |> SET id = 'same' |> AS `current` |> INFER `model-task:risk-score.v1` INPUT (text) AS assessment"
  // Temporary implementation gap: Common retains a valid proven physical key,
  // but AS after SET removes its last authored name for input_key emission.
  // This refusal is not a language restriction or completion evidence for #1840.
  // The current UnsupportedInfer variant carries no diagnostic source span.
  for script in [false, true] {
    assert_true(
      compile_infer_defaults(
        text,
        context,
        script,
        source_path="unnameable-key.sql",
      )
      is Err(UnsupportedInfer),
    )
  }
}

///|
test "inferred ITEM KEY retains case-insensitive VALUE and OUTCOME surface refusals" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  for name in ["VALUE", "OUTCOME", "VaLuE", "OuTcOmE"] {
    let quoted = "`" + name + "`"
    let prefix = "FROM tickets |> RENAME id AS " +
      quoted +
      " |> ASSERT UNIQUE BY (" +
      quoted +
      ") |> INFER `model-task:risk-score.v1`"
    for key in ["", " ITEM KEY (" + quoted + ")"] {
      for script in [false, true] {
        assert_true(
          compile_infer_defaults(
            prefix + key + " INPUT (text) AS assessment",
            context,
            script,
          )
          is Err(UnsupportedInfer),
          msg=name + key,
        )
      }
    }
  }
}

///|
test "default KEEP retains order types and exactly the declared ModelTask inputs" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  let prefix = "FROM tickets |> ASSERT UNIQUE BY (id) |> INFER `model-task:risk-score.v1` INPUT (text)"
  for script in [false, true] {
    for
      (keep, expected_fields) in [
        ("", "[\"id\",\"text\",\"secret\",\"assessment\"]"),
        (" KEEP (*)", "[\"id\",\"text\",\"secret\",\"assessment\"]"),
        (
          " KEEP (secret, text, id)", "[\"secret\",\"text\",\"id\",\"assessment\"]",
        ),
        (" KEEP (text, id)", "[\"text\",\"id\",\"assessment\"]"),
      ] {
      let program = compile_infer_defaults(
        prefix + keep + " AS assessment",
        context,
        script,
      ).unwrap()
      let checked = check_shorthand_identity_program(program, environment)
      assert_true(semantic(program).contains("\"fields\":" + expected_fields))
      assert_true(
        semantic(program).contains("\"input\":{\"text\":{\"field\":\"text\"}}"),
      )
      let pipeline = @check.unit_pipeline(
        checked,
        @check.unit_count(checked) - 1,
      ).unwrap()
      let schema = @pipeline.output_schema(pipeline).unwrap()
      assert_false(
        @schema.lookup_reference(schema, "id").unwrap().contract.nullable,
      )
      assert_true(
        @schema.lookup_reference(schema, "text").unwrap().contract.nullable,
      )
      assert_true(
        @schema.lookup_reference(schema, "id").unwrap().contract.shape
        is @contract.Text(_),
      )
      assert_true(
        @schema.lookup_reference(schema, "text").unwrap().contract.shape
        is @contract.Text(_),
      )
      assert_eq(
        @schema.lookup_reference(schema, "secret") is Some(_),
        keep != " KEEP (text, id)",
      )
      assert_true(
        @schema.lookup_reference(schema, "assessment").unwrap().contract.shape
        is @contract.Object(_),
      )
      let mut inference_count = 0
      for unit in 0..<@check.unit_count(checked) {
        let pipeline = @check.unit_pipeline(checked, unit).unwrap()
        for step in 0..<@pipeline.step_count(pipeline) {
          if @pipeline.step_at(pipeline, step).unwrap().operation
            is @pipeline.Infer(infer) {
            inference_count += 1
            assert_eq(@evidence.infer_key_count(infer), 1)
            assert_eq(
              @schema.reference_name(
                @evidence.infer_key_at(infer, 0).unwrap().field,
              ),
              "id",
            )
            assert_eq(@evidence.infer_input_binding_count(infer), 1)
            assert_eq(
              @evidence.infer_input_binding_at(infer, 0).unwrap().role,
              "text",
            )
          }
        }
      }
      assert_eq(inference_count, 1)
    }
  }
}

///|
test "INFER default KEEP detects result collisions and still resets old ranges" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  for script in [false, true] {
    for keep in ["", " KEEP (*)"] {
      assert_true(
        compile_infer_defaults(
          "FROM tickets |> ASSERT UNIQUE BY (id) |> INFER `model-task:risk-score.v1` INPUT (text)" +
          keep +
          " AS `TEXT`",
          context,
          script,
        )
        is Err(DuplicateOutput),
      )
    }
    let renamed = compile_infer_defaults(
      "FROM tickets |> ASSERT UNIQUE BY (id) |> INFER `model-task:risk-score.v1` INPUT (text) KEEP (id) AS text",
      context, script,
    ).unwrap()
    ignore(check_shorthand_identity_program(renamed, environment))
    assert_true(
      compile_infer_defaults(
        "FROM tickets AS old |> ASSERT UNIQUE BY (id) |> INFER `model-task:risk-score.v1` INPUT (text) AS assessment |> SELECT old.id",
        context, script,
      )
      is Err(_),
    )
  }
}

///|
test "omitted keys retain exact Common no-key ambiguous and nullable refusals" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  for script in [false, true] {
    for
      (prefix, expected) in [
        ("FROM tickets", @evidence.CandidateKeyRequired),
        (
          "FROM tickets |> ASSERT UNIQUE BY (id) |> ASSERT UNIQUE BY (secret)",
          @evidence.AmbiguousCandidateKey,
        ),
        (
          "FROM tickets |> ASSERT UNIQUE BY (text)",
          @evidence.CandidateKeyRequired,
        ),
      ] {
      assert_eq(
        infer_defaults_prefix_refusal(
          compile_infer_defaults(
            prefix +
            " |> INFER `model-task:risk-score.v1` INPUT (text) AS assessment",
            context,
            script,
          ),
        ),
        @pipeline.Infer(expected),
        msg=prefix,
      )
    }
    for
      (prefix, key, expected) in [
        ("FROM tickets", "id", @evidence.CandidateKeyRequired),
        (
          "FROM tickets |> ASSERT UNIQUE BY (id)",
          "secret",
          @evidence.CandidateKeyRequired,
        ),
        (
          "FROM tickets |> ASSERT UNIQUE BY (id)",
          "id, secret",
          @evidence.CandidateKeyRequired,
        ),
        (
          "FROM tickets |> ASSERT UNIQUE BY (id, secret)",
          "id",
          @evidence.CandidateKeyRequired,
        ),
        (
          "FROM tickets |> ASSERT UNIQUE BY (text)",
          "text",
          @evidence.InvalidKeyType("text"),
        ),
      ] {
      let program = compile_infer_defaults(
        prefix +
        " |> INFER `model-task:risk-score.v1` ITEM KEY (" +
        key +
        ") INPUT (text) AS assessment",
        context,
        script,
      ).unwrap()
      assert_eq(
        infer_defaults_final_refusal(program, environment),
        @pipeline.Infer(expected),
        msg=prefix,
      )
    }
    // Authored selection still disambiguates existing proofs; it is not ignored.
    let explicit = compile_infer_defaults(
      "FROM tickets |> ASSERT UNIQUE BY (id) |> ASSERT UNIQUE BY (secret) |> INFER `model-task:risk-score.v1` ITEM KEY (secret) INPUT (text) AS assessment",
      context, script,
    ).unwrap()
    ignore(check_shorthand_identity_program(explicit, environment))
  }
}

///|
test "deferred INFER input members preserve Common missing and ambiguous key refusals" {
  let environment = infer_member_environment()
  let context = infer_defaults_object_context(environment)
  for
    (prefix, expected) in [
      ("FROM tickets", @evidence.CandidateKeyRequired),
      (
        "FROM tickets |> ASSERT UNIQUE BY (id) |> ASSERT UNIQUE BY (secret)",
        @evidence.AmbiguousCandidateKey,
      ),
    ] {
    // Uppercase NOTES requires member rewriting and its finish accounting.
    // A refused terminal type-only probe must not mask Common's key diagnostic
    // by reserving all remaining work before the actual checked-prefix call.
    let text = prefix +
      " |> EXTEND note_object AS payload |> INFER `model-task:risk-score.v1` INPUT (text = payload.NOTES) AS assessment"
    for script in [false, true] {
      assert_eq(
        infer_defaults_prefix_refusal(
          compile_infer_defaults(text, context, script),
        ),
        @pipeline.Infer(expected),
        msg=text,
      )
    }
  }
}

///|
test "deferred INFER input members normalize with the sole original key proof" {
  let environment = infer_member_environment()
  let context = infer_defaults_object_context(environment)
  let expanded = "FROM tickets |> ASSERT UNIQUE BY (id) |> EXTEND note_object AS payload |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text = payload.NOTES) KEEP (*) AS assessment"
  for script in [false, true] {
    let expected = match compile_infer_defaults(expanded, context, script) {
      Ok(program) => program
      Err(issue) => fail("explicit member control: " + @debug.to_string(issue))
    }
    let actual = compile_infer_defaults(
      expanded
      .replace(old=" ITEM KEY (id)", new="")
      .replace(old=" KEEP (*)", new=""),
      context,
      script,
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    assert_true(semantic(actual).contains("\"name\":\"notes\""))
    assert_false(semantic(actual).contains("\"name\":\"NOTES\""))
    assert_shorthand_checked_identity(
      check_shorthand_identity_program(actual, environment),
      check_shorthand_identity_program(expected, environment),
    )
  }
}

///|
test "a proven non-scalar resource identity is not an inferred scalar ITEM KEY" {
  let environment = infer_member_environment()
  // The existing local-input declaration API admits ResourceRef key evidence.
  // INFER still requires scalar keys; no fabricated reference value is needed.
  let source = @wire.admit(
    @source.parse_json(
      (
        #|{"carrier":"relation","schema":{"resource":{"type":"resource_ref","resource_kind":"file","nullable":false},"text":{"type":"string","nullable":true}},"primary_key":["resource"]}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let base = infer_input_field_context(environment)
  let context = {
    ..base,
    inputs: [
      {
        ..base.inputs[0],
        source: Captured(source),
        visible_fields: ["resource", "text"],
      },
    ],
  }
  let prefix = "FROM tickets |> ASSERT UNIQUE BY (resource) |> INFER `model-task:risk-score.v1`"
  for script in [false, true] {
    assert_eq(
      infer_defaults_prefix_refusal(
        compile_infer_defaults(
          prefix + " INPUT (text) AS assessment",
          context,
          script,
        ),
      ),
      @pipeline.Infer(@evidence.CandidateKeyRequired),
    )
    assert_eq(
      infer_defaults_final_refusal(
        compile_infer_defaults(
          prefix + " ITEM KEY (resource) INPUT (text) AS assessment",
          context,
          script,
        ).unwrap(),
        environment,
      ),
      @pipeline.Infer(@evidence.InvalidKeyType("resource")),
    )
  }
}

///|
test "omitted keys preserve original UTF-8 input diagnostics before final checking" {
  let environment = infer_shorthand_environment()
  let explicit = "/*😀é*/\r\n" +
    infer_shorthand_source("text, n, `SELECT`").replace(
      old="|> INFER",
      new="|> SET n = text |> INFER",
    )
  let omitted = explicit.replace(old=" ITEM KEY (id)", new="")
  for script in [false, true] {
    guard compile_infer_defaults(
        omitted,
        infer_shorthand_context(environment),
        script,
        source_path="original.sql",
      )
      is Err(BindingPreparation(LocalProgram(Pipeline(_, issue)))) else {
      fail("expected original Common input mismatch during key inference")
    }
    assert_eq(
      issue.kind,
      @pipeline.Infer(@evidence.Expression(@typing.TypeMismatch("number"))),
    )
    assert_eq(issue.span.source_path, "original.sql")
    assert_eq(issue.span.start_byte, 116)
    assert_eq(issue.span.end_byte, 117)
    let program = compile_infer_defaults(
      explicit,
      infer_shorthand_context(environment),
      script,
      source_path="original.sql",
    ).unwrap()
    guard @check.check_parsed(program, environment, None, check_limits())
      is Rejected(error) else {
      fail("expected explicit final input mismatch")
    }
    match @check.diagnostic_cause(error) {
      Source(SourceView(Program(Program(Pipeline(_, issue))))) => {
        assert_eq(
          issue.kind,
          @pipeline.Infer(@evidence.Expression(@typing.TypeMismatch("number"))),
        )
        assert_eq(issue.span.source_path, "original.sql")
        assert_eq(issue.span.start_byte, 130)
        assert_eq(issue.span.end_byte, 131)
      }
      other => raise other
    }
  }
}

///|
test "INFER defaults normalize through WITH and source-free Script producers" {
  let environment = infer_member_environment()
  for
    prefix in [
      "SELECT DISTINCT 'a' AS id |> EXTEND 'urgent' AS text", "WITH seed AS (SELECT DISTINCT 'a' AS id |> EXTEND 'urgent' AS text) FROM seed",
    ] {
    let expanded = prefix +
      " |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text = text) KEEP (*) AS assessment"
    for script in [false, true] {
      let expected = compile_infer_defaults(
        expanded,
        infer_member_context(environment),
        script,
      ).unwrap()
      let actual = compile_infer_defaults(
        expanded
        .replace(old=" ITEM KEY (id)", new="")
        .replace(old=" KEEP (*)", new=""),
        infer_member_context(environment),
        script,
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      assert_shorthand_checked_identity(
        check_shorthand_identity_program(actual, environment),
        check_shorthand_identity_program(expected, environment),
      )
    }
  }
}

///|
test "default ITEM KEY uses the admitted Source owner and preserves its Common refusal" {
  let environment = source_infer_member_environment()
  let context = source_infer_member_context(environment)
  for script in [false, true] {
    let expanded = "FROM objects |> SELECT DISTINCT id |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text = 'urgent') KEEP (*) AS assessment"
    let expected = match compile_infer_defaults(expanded, context, script) {
      Ok(program) => program
      Err(issue) => fail("explicit member control: " + @debug.to_string(issue))
    }
    let actual = compile_infer_defaults(
      expanded
      .replace(old=" ITEM KEY (id)", new="")
      .replace(old=" KEEP (*)", new=""),
      context,
      script,
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    assert_shorthand_checked_identity(
      check_shorthand_identity_program(actual, environment),
      check_shorthand_identity_program(expected, environment),
    )
    guard compile_infer_defaults(
        "FROM objects |> INFER `model-task:risk-score.v1` INPUT (text = 'urgent') AS assessment",
        context, script,
      )
      is Err(BindingPreparation(SourceProgram(Program(Pipeline(_, issue))))) else {
      fail("expected admitted Source's Common candidate-key refusal")
    }
    assert_eq(issue.kind, @pipeline.Infer(@evidence.CandidateKeyRequired))
  }
}

///|
test "default KEEP preserves positional right-set alignment without exposing private names" {
  let environment = infer_member_environment()
  let context = infer_input_field_context(environment)
  for
    right in [
      "FROM tickets |> SELECT id AS repeated, text AS `REPEATED`, secret", "FROM tickets |> SELECT id, COALESCE(text, 'empty'), secret",
    ] {
    // INFER remains in Statement position after the set. The right operand
    // remains Pure and its duplicate or unnamed positions align before KEEP.
    let prefix = "SELECT 'z' AS id, 'left' AS text, 'private' AS secret WHERE FALSE |> UNION ALL (" +
      right +
      ") |> ASSERT UNIQUE BY (id) |> INFER `model-task:risk-score.v1`"
    for script in [false, true] {
      let expected = compile_infer_defaults(
        prefix + " ITEM KEY (id) INPUT (text) KEEP (*) AS assessment",
        context,
        script,
      ).unwrap()
      let actual = compile_infer_defaults(
        prefix + " INPUT (text) AS assessment",
        context,
        script,
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      assert_true(
        semantic(actual).contains(
          "\"fields\":[\"id\",\"text\",\"secret\",\"assessment\"]",
        ),
      )
      assert_shorthand_checked_identity(
        check_shorthand_identity_program(actual, environment),
        check_shorthand_identity_program(expected, environment),
      )
      for name in ["repeated", "aql_set_anonymous_4"] {
        assert_true(
          compile_infer_defaults(
            prefix + " INPUT (text) AS assessment |> SELECT " + name,
            context,
            script,
          )
          is Err(_),
          msg=name,
        )
      }
    }
  }
}
