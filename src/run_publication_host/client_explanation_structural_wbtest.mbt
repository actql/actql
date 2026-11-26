///|
fn structural_explanation_prepared(
  filter : String,
  parameter? : Bool = false,
) -> PreparedClientProgram {
  let declarations = if parameter {
    ",\"params\":{\"threshold\":{\"type\":\"number\",\"default\":7}}"
  } else {
    ""
  }
  let stages =
    #|,"stages":[{"id":"main","inputs":{},"steps":[{"as":"original","values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"PRIVATE_ROW_A"},{"id":2,"label":"PRIVATE_ROW_B"}]}},{"from":"original","filter":
  let suffix =
    #|,"as":"filtered"},{"from":"filtered","select":["label","id"],"as":"selected"},{"from":"selected","join":{"with":"original","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":4,"select":{"id":"left.id","label":"right.label"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id","label"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  input_result_prepared(
    "{\"version\":\"actql/0.1\",\"id\":\"structural-explanation\"" +
    declarations +
    stages +
    filter +
    suffix,
  )
}

///|
fn structural_explanation_compiled(
  prepared : PreparedClientProgram,
) -> ClientTaskCompilation {
  issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    prepared_client_values_sequence_limits(prepared),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
}

///|
test "structural explanation emits original schema projection and JOIN facts without VALUES data" {
  let prepared = structural_explanation_prepared("\"id > 1\"")
  let compiled = structural_explanation_compiled(prepared)
  for occurrence in [0, 2, 3] {
    let fact = client_task_operation_explanation(
      prepared, compiled, 0, occurrence,
    ).unwrap()
    let wire = client_operation_explanation_structural_json(
      fact, prepared, 20000, 2000, 32,
    ).unwrap()
    assert_true(
      @publication.parse_interactive_run_control_shape(
        "explanation_meaning", wire, 20000, 2000, 32,
      )
      is Ok(_),
    )
    assert_false(wire.contains("PRIVATE_ROW"))
    assert_false(wire.contains("row_count"))
    let value = parse_plan_identity_value(wire, 20000, 2000, 32).unwrap()
    let kind = @canonical.object_field(value, "kind").unwrap()
    match occurrence {
      0 => {
        assert_true(kind is @canonical.String("values"))
        let schema = @canonical.object_field(value, "schema").unwrap()
        guard @canonical.object_field(schema, "fields")
          is Some(@canonical.Array(fields)) else {
          fail("schema fields")
        }
        assert_eq(@canonical.array_count(fields), 2)
        assert_true(
          @canonical.object_field(
            @canonical.array_at(fields, 0).unwrap(),
            "name",
          )
          is Some(@canonical.String("id")),
        )
      }
      2 => {
        assert_true(kind is @canonical.String("projection"))
        guard @canonical.object_field(value, "fields")
          is Some(@canonical.Array(fields)) else {
          fail("projection fields")
        }
        assert_true(
          @canonical.object_field(
            @canonical.array_at(fields, 0).unwrap(),
            "output",
          )
          is Some(@canonical.String("label")),
        )
        assert_true(
          @canonical.object_field(
            @canonical.array_at(fields, 1).unwrap(),
            "output",
          )
          is Some(@canonical.String("id")),
        )
      }
      _ => {
        assert_true(kind is @canonical.String("join"))
        assert_true(
          @canonical.object_field(value, "join_kind")
          is Some(@canonical.String("inner")),
        )
        guard @canonical.object_field(value, "keys")
          is Some(@canonical.Array(keys)) else {
          fail("JOIN keys")
        }
        assert_eq(@canonical.array_count(keys), 1)
        assert_true(
          @canonical.object_field(@canonical.array_at(keys, 0).unwrap(), "left")
          is Some(@canonical.String("id")),
        )
        assert_true(
          @canonical.object_field(
            @canonical.array_at(keys, 0).unwrap(),
            "right",
          )
          is Some(@canonical.String("id")),
        )
      }
    }
  }
}

///|
test "structural explanation redacts literal values and inferred UTF8 lengths at the original typed expression" {
  let mut previous : String? = None
  let mut previous_definition : String? = None
  for secret in ["PRIVATE_X", "PRIVATE_LONGER_😀_é"] {
    let prepared = structural_explanation_prepared(
      "{\"eq\":[{\"field\":\"label\"},{\"literal\":\"" + secret + "\"}]}",
    )
    let compiled = structural_explanation_compiled(prepared)
    let fact = client_task_operation_explanation(prepared, compiled, 0, 1).unwrap()
    let wire = client_operation_explanation_structural_json(
      fact, prepared, 20000, 2000, 32,
    ).unwrap()
    assert_false(wire.contains("PRIVATE"))
    assert_false(wire.contains("length"))
    assert_false(wire.contains("value_cid"))
    assert_true(wire.contains("literal_redacted"))
    assert_true(
      @publication.parse_interactive_run_control_shape(
        "explanation_meaning", wire, 20000, 2000, 32,
      )
      is Ok(_),
    )
    if previous is Some(before) {
      assert_eq(wire, before)
    }
    let definition = client_operation_explanation_occurrence(fact, prepared).unwrap().program_definition_cid
    if previous_definition is Some(before) {
      assert_false(definition == before)
    }
    previous = Some(wire)
    previous_definition = Some(definition)
  }
}

///|
test "structural explanation keeps parameter reference and type without its bound default" {
  let prepared = structural_explanation_prepared(
    "{\"gt\":[{\"field\":\"id\"},{\"$param\":\"threshold\"}]}",
    parameter=true,
  )
  let fact = client_task_operation_explanation(
    prepared,
    structural_explanation_compiled(prepared),
    0,
    1,
  ).unwrap()
  let wire = client_operation_explanation_structural_json(
    fact, prepared, 20000, 2000, 32,
  ).unwrap()
  assert_true(wire.contains("\"parameter\""), msg=wire)
  assert_true(wire.contains("\"threshold\""))
  assert_true(wire.contains("\"number\""))
  assert_false(wire.contains("\"value\""))
  assert_false(wire.contains("\"default\""))
  assert_true(
    @publication.parse_interactive_run_control_shape(
      "explanation_meaning", wire, 20000, 2000, 32,
    )
    is Ok(_),
    msg=wire,
  )
}

///|
test "structural explanation leaves an unprojected predicate honest instead of rendering a partial tree" {
  let prepared = structural_explanation_prepared("\"id + 1 > 1\"")
  let fact = client_task_operation_explanation(
    prepared,
    structural_explanation_compiled(prepared),
    0,
    1,
  ).unwrap()
  let wire = client_operation_explanation_structural_json(
    fact, prepared, 20000, 2000, 32,
  ).unwrap()
  assert_eq(
    wire, "{\"kind\":\"filter\",\"predicate\":{\"reason\":\"expression_form_not_projected\",\"state\":\"not_projected\"}}",
  )
}

///|
test "structural Narrative renders checked singleton AND and OR in both languages" {
  for operator in ["and", "or"] {
    let source = "{\"version\":\"actql/0.1\",\"id\":\"singleton-boolean\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"source\",\"values\":{\"rows\":[{\"flag\":true}],\"schema\":{\"flag\":{\"type\":\"boolean\",\"nullable\":false}}}},{\"from\":\"source\",\"filter\":{\"" +
      operator +
      "\":[{\"field\":\"flag\"}]},\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"flag\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
    let prepared = input_result_prepared(source)
    let compiled = structural_explanation_compiled(prepared)
    let fact = client_task_operation_explanation(prepared, compiled, 0, 1).unwrap()
    let wire = client_operation_explanation_structural_json(
      fact, prepared, 20000, 2000, 32,
    ).unwrap()
    let meaning = @publication.parse_interactive_run_control_shape(
      "explanation_meaning", wire, 20000, 2000, 32,
    ).unwrap()
    let predicate = @canonical.object_field(meaning, "predicate").unwrap()
    assert_true(
      @canonical.object_field(predicate, "state")
      is Some(@canonical.String("projected")),
    )
    guard @canonical.object_field(predicate, "nodes")
      is Some(@canonical.Array(nodes)) &&
      @canonical.array_at(nodes, 0) is Some(root) &&
      @canonical.object_field(root, "children")
      is Some(@canonical.Array(children)) else {
      fail("one original projected predicate root")
    }
    assert_eq(@canonical.array_count(children), 1)
    guard @canonical.object_field(root, "operator")
      is Some(@canonical.String(selected)) else {
      fail("original Boolean operator")
    }
    assert_eq(selected, operator)
    let (original, _) = capture_client_static_pure_explanation_original(
      prepared,
      Tasks(compiled),
      20000,
      2000,
      32,
    ).unwrap()
    let original_facts = seal_client_static_pure_explanation_facts(
      original, 20000, 2000, 32,
    ).unwrap()
    let facts = @publication.parse_interactive_run_control_shape(
      "explanation_facts",
      @publication.run_evidence_value_json(original_facts),
      20000,
      2000,
      32,
    ).unwrap()
    let en = render_client_explanation_narrative(facts, None, English, 65536)
    let ja = render_client_explanation_narrative(facts, None, Japanese, 65536)
    assert_eq(en.steps.length(), 2)
    assert_eq(ja.steps.length(), 2)
    assert_eq(en.steps[1], "Keep rows where: (fields.\"flag\":boolean)")
    assert_eq(
      ja.steps[1],
      "この条件を満たす行を残す: (fields.\"flag\":boolean)",
    )
  }
}

///|
test "structural explanation measurement matches output and refuses finite limits or foreign owners" {
  let prepared = structural_explanation_prepared("\"id > 1\"")
  let foreign = structural_explanation_prepared("\"id > 1\"")
  let fact = client_task_operation_explanation(
    prepared,
    structural_explanation_compiled(prepared),
    0,
    1,
  ).unwrap()
  let wire = client_operation_explanation_structural_json(
    fact, prepared, 20000, 2000, 32,
  ).unwrap()
  let measured = measure_client_operation_explanation_structural(
    fact, prepared, 20000, 2000, 32,
  ).unwrap()
  assert_eq(measured, interactive_geometry_actual(wire))
  assert_eq(
    client_operation_explanation_structural_json(
      fact,
      prepared,
      measured.0,
      measured.1,
      measured.2,
    ).unwrap(),
    wire,
  )
  assert_true(
    client_operation_explanation_structural_json(
      fact,
      prepared,
      measured.0 - 1,
      2000,
      32,
    )
    is Err(Encoding(@encode.OutputLimit)),
  )
  assert_true(
    client_operation_explanation_structural_json(
      fact,
      prepared,
      20000,
      measured.1 - 1,
      32,
    )
    is Err(Encoding(@encode.OutputLimit)),
  )
  assert_true(
    client_operation_explanation_structural_json(
      fact,
      prepared,
      20000,
      2000,
      measured.2 - 1,
    )
    is Err(Encoding(@encode.OutputLimit)),
  )
  assert_true(
    client_operation_explanation_structural_json(fact, prepared, 0, 2000, 32)
    is Err(InvalidReadLimits),
  )
  assert_true(
    client_operation_explanation_structural_json(fact, foreign, 20000, 2000, 32)
    is Err(Original(ForeignCompilation)),
  )
}
