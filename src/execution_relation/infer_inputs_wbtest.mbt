///|
fn infer_fixture_tasks() -> @model_environment.ModelTasks {
  // Fixed task and schema CIDs are independent Node crypto vectors.
  let body =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    body +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let wire = @model_environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
  ).unwrap()
  @model_environment.check_model_tasks(wire, {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 10,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 100000,
  }).unwrap()
}

///|
fn infer_fixture_input() -> @carrier.Carrier {
  let nested = @contract.object_contract(
    [("text", @contract.primitive(StringType, nullable=true))],
    nullable=false,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  let schema = @schema.from_object(
    @contract.object_contract(
      [
        ("id", @contract.primitive(StringType, nullable=false)),
        ("text", @contract.primitive(StringType, nullable=true)),
        ("payload", nested),
      ],
      nullable=false,
      max_fields=3,
      max_name_bytes=13,
    ).unwrap(),
  ).unwrap()
  @carrier.relation(@carrier.typed_rows(schema))
}

///|
fn infer_fixture_checked(
  mapping : String,
  parameters? : @parameter.Declarations? = None,
  extra? : String = "",
) -> @infer.CheckedInfer {
  let input = infer_fixture_input()
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), input, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  @infer.check(
    input_cursor(
      "{\"contract\":\"model-task:risk-score.v1\",\"key\":\"id\",\"input\":{\"text\":" +
      mapping +
      "}" +
      extra +
      "}",
    ),
    input,
    Some(@evidence.singleton_key(key)),
    infer_fixture_tasks(),
    parameters,
    {
      max_work: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
      max_tokens: 1000,
      max_key_fields: 1,
      max_input_roles: 1,
    },
  ).unwrap()
}

///|
fn infer_fixture_expression_limits() -> @lower.ExpressionLimits {
  {
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }
}

///|
fn infer_fixture_wire(expression : @lower.Expression) -> String raise {
  let writer = @encode.writer(10000, 1000, 100)
  @lower.emit_expression(expression, writer)
  @encode.finish(writer)
}

///|
fn infer_fixture_advance(
  expression : @lower.Expression,
  input : Map[String, Value],
) -> Value {
  let state = start_expression_execution(
    expression,
    input,
    [],
    10000,
    100,
    1000,
  ).unwrap()
  for _ in 0..<1000 {
    match advance_expression_execution(state).unwrap() {
      ExpressionContinue => ()
      ExpressionComplete(value) => return value
    }
  }
  abort("finite mapped input did not complete")
}

///|
test "checked infer inputs reach shared expression lowering and resumable evaluation" {
  let checked = infer_fixture_checked("{\"field\":\"text\"}")
  let prepared = @lower.prepare_infer_inputs(
    checked,
    None,
    infer_fixture_expression_limits(),
  ).unwrap()
  assert_true(physical_equal(@lower.infer_inputs_owner(prepared), checked))
  assert_true(@lower.infer_inputs_parameters(prepared) is None)
  assert_eq(@lower.infer_input_count(prepared), 1)
  assert_true(@lower.infer_input_expression_at(prepared, 1) is None)
  let expression = @lower.infer_input_expression_at(prepared, 0).unwrap()
  assert_eq(
    infer_fixture_wire(expression),
    "{\"body\":\"text\",\"op\":\"field\"}",
  )
  assert_true(
    @lower.expression_body(expression)
    is Field("text", @relation.InputField(@schema.Unqualified("text"))),
  )
  assert_true(
    @contract.type_equal(
      @lower.expression_contract(expression),
      @contract.primitive(StringType, nullable=true),
      1,
    ),
  )
  assert_eq(
    object_result_wire(
      infer_fixture_advance(expression, Map([("text", Text("urgent"))])),
    ),
    "\"urgent\"",
  )
  assert_eq(
    object_result_wire(infer_fixture_advance(expression, Map([("text", Null)]))),
    "null",
  )
  // Annotation, field mapping and the two leaf visits cost four units; the
  // input entry and receiving-field resolution add two preparation units.
  assert_eq(@lower.infer_inputs_usage(prepared), (6, 1, 0, 0))
  let exact : @lower.ExpressionLimits = {
    max_nodes: 1,
    max_work: 6,
    max_depth: 0,
    max_literal_nodes: 0,
    max_literal_text_bytes: 0,
  }
  assert_true(@lower.prepare_infer_inputs(checked, None, exact) is Ok(_))
  assert_true(
    @lower.prepare_infer_inputs(checked, None, { ..exact, max_work: 5, })
    is Err({ kind: Expression(ExpressionBudgetExceeded), .. }),
  )
  assert_true(
    @lower.prepare_infer_inputs(checked, None, { ..exact, max_nodes: 0, })
    is Err({ kind: BudgetExceeded, .. }),
  )
}

///|
test "infer object property mapping preserves closed typed fields and nullable members" {
  let checked = infer_fixture_checked(
    "{\"property\":{\"value\":{\"property\":{\"value\":{\"object\":{\"payload\":{\"field\":\"payload\"}}},\"name\":\"payload\"}},\"name\":\"text\"}}",
  )
  let prepared = @lower.prepare_infer_inputs(
    checked,
    None,
    infer_fixture_expression_limits(),
  ).unwrap()
  let expression = @lower.infer_input_expression_at(prepared, 0).unwrap()
  assert_eq(
    infer_fixture_wire(expression),
    "{\"body\":{\"name\":\"text\",\"value\":{\"body\":{\"name\":\"payload\",\"value\":{\"body\":{\"payload\":{\"body\":\"payload\",\"op\":\"field\"}},\"op\":\"object\"}},\"op\":\"property\"}},\"op\":\"property\"}",
  )
  for
    (value, expected) in [
      (@admitted.text_value("urgent", 6).unwrap(), "\"urgent\""),
      (@admitted.null_value(), "null"),
    ] {
    let payload = capture(@admitted.object_value([("text", value)]).unwrap())
    assert_eq(
      object_result_wire(
        infer_fixture_advance(expression, Map([("payload", payload)])),
      ),
      expected,
    )
    let state = start_expression_execution(
      expression,
      Map([("payload", payload)]),
      [],
      10000,
      100,
      1000,
    ).unwrap()
    for _ in 0..<3 {
      assert_true(
        advance_expression_execution(state).unwrap() is ExpressionContinue,
      )
    }
    assert_true(state.frame.workspace.live > 0)
    assert_true(cancel_expression_execution(state))
    assert_eq(state.frame.workspace.live, 0)
    assert_true(
      advance_expression_execution(state)
      is Err({ kind: InvalidControlLimits, .. }),
    )
    // The enclosing inference owner still owns its borrowed input row.
    assert_eq(
      object_result_wire(
        infer_fixture_advance(expression, Map([("payload", payload)])),
      ),
      expected,
    )
  }
}

///|
test "infer lowering binds positive item guards under the exact declaration owner" {
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"limit\":{\"type\":\"number\",\"nullable\":true}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = infer_fixture_checked(
    "{\"field\":\"text\"}",
    parameters=Some(declarations),
    extra=",\"max_items\":{\"$param\":\"limit\"}",
  )
  for
    (body, expected) in [
      ("{\"limit\":1}", Some(1L)),
      ("{\"limit\":9007199254740991}", Some(9007199254740991L)),
      ("{\"limit\":0}", None),
      ("{\"limit\":1.5}", None),
      ("{\"limit\":null}", None),
    ] {
    guard @parameter.bind(declarations, Some(input_cursor(body)), {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap()
      is Ready(bound) else {
      abort("complete guard binding")
    }
    let result = @lower.prepare_infer_inputs(
      checked,
      Some(bound),
      infer_fixture_expression_limits(),
    )
    if expected is Some(value) {
      assert_eq(@lower.infer_input_item_guard(result.unwrap()), Some(value))
    } else {
      assert_true(result is Err({ kind: InvalidItemGuard("limit"), .. }))
    }
  }
  let literal = infer_fixture_checked(
    "{\"field\":\"text\"}",
    extra=",\"max_items\":2",
  )
  assert_eq(
    @lower.infer_input_item_guard(
      @lower.prepare_infer_inputs(
        literal,
        None,
        infer_fixture_expression_limits(),
      ).unwrap(),
    ),
    Some(2L),
  )
}

///|
test "infer lowering retains exact bound parameter declarations and current values" {
  let declarations = () => {
    @parameter.read_declarations(
      Some(
        input_cursor(
          "{\"request_text\":{\"type\":\"string\",\"nullable\":true}}",
        ),
      ),
      {
        max_parameters: 1,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      },
    ).unwrap()
  }
  let declaration = declarations()
  let checked = infer_fixture_checked(
    "{\"$param\":\"request_text\"}",
    parameters=Some(declaration),
  )
  let bind = (owner : @parameter.Declarations, values : String) => {
    guard @parameter.bind(owner, Some(input_cursor(values)), {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap()
      is Ready(bound) else {
      abort("complete bindings")
    }
    bound
  }
  for
    (values, expected) in [
      ("{\"request_text\":\"urgent\"}", "\"urgent\""),
      ("{\"request_text\":null}", "null"),
    ] {
    let bound = bind(declaration, values)
    let prepared = @lower.prepare_infer_inputs(
      checked,
      Some(bound),
      infer_fixture_expression_limits(),
    ).unwrap()
    assert_true(
      physical_equal(@lower.infer_inputs_parameters(prepared).unwrap(), bound),
    )
    assert_eq(
      object_result_wire(
        infer_fixture_advance(
          @lower.infer_input_expression_at(prepared, 0).unwrap(),
          Map([]),
        ),
      ),
      expected,
    )
  }
  assert_true(
    @lower.prepare_infer_inputs(
      checked,
      None,
      infer_fixture_expression_limits(),
    )
    is Err({ kind: Binding(MissingBindings), .. }),
  )
  let foreign = bind(declarations(), "{\"request_text\":\"urgent\"}")
  assert_true(
    @lower.prepare_infer_inputs(
      checked,
      Some(foreign),
      infer_fixture_expression_limits(),
    )
    is Err({ kind: Binding(BindingOwnerMismatch), .. }),
  )
}
