///|
fn array_profile_cursor(text : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(text, {
      max_input_bytes: 4096,
      max_nodes: 128,
      max_depth: 32,
    }).unwrap(),
    {
      max_nodes: 128,
      max_depth: 32,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  ).unwrap()
}

///|
fn array_profile_typed(
  text : String,
  fields? : String = "{}",
  parameters? : String? = None,
) -> @typing.TypedExpression {
  let expression = @expression.admit(array_profile_cursor(text), {
    max_nodes: 128,
    max_depth: 32,
    max_text_bytes: 4096,
    max_tokens: 128,
    tree: {
      max_nodes: 128,
      max_depth: 32,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  }).unwrap()
  let scope = @contract.read_author(
    array_profile_cursor(
      "{\"type\":\"object\",\"nullable\":false,\"fields\":" + fields + "}",
    ),
    { max_nodes: 128, max_depth: 32, max_text_bytes: 4096, },
  ).unwrap()
  let declarations = @parameters.read_declarations(
    parameters.map(array_profile_cursor),
    { max_parameters: 8, max_nodes: 128, max_depth: 32, max_text_bytes: 4096, },
  ).unwrap()
  @typing.check(
    expression,
    {
      fields: Some(scope),
      left: None,
      right: None,
      parameters: Some(declarations),
    },
    { max_nodes: 128, max_depth: 32, max_work: 4096, max_text_bytes: 4096, },
  ).unwrap()
}

///|
test "source array profile uses resolved item types for literals fields and parameters" {
  let number_array = "{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}}"
  let expressions = [
    array_profile_typed(
      (
        #|{"array":[{"array":[{"literal":1}]}]}
      ),
    ),
    array_profile_typed(
      (
        #|{"array":[{"field":"xs"}]}
      ),
      fields="{\"xs\":" + number_array + "}",
    ),
    array_profile_typed(
      (
        #|{"array":[{"$param":"xs"}]}
      ),
      parameters=Some("{\"xs\":" + number_array + "}"),
    ),
  ]
  for expression in expressions {
    // The ordinary checker above intentionally accepts recursive machine
    // arrays. Only the source profile rejects this direct nesting.
    guard array_nested_source(expression, 4096) is Ok((Some(source), _)) else {
      fail("resolved direct nested array must be detected")
    }
    assert_eq(@expression.location_path(source), [])
  }
}

///|
test "source array profile permits a closed object between arrays and preserves JSON" {
  for
    text in [
      (
        #|{"array":[{"object":{"xs":{"array":[{"literal":1},{"literal":2}]}}}]}
      ),
      (
        #|{"typed_literal":{"type":"json","value":"[[1],null]"}}
      ),
      (
        #|{"array":[{"literal":true},{"literal":null}]}
      ),
    ] {
    let expression = array_profile_typed(text)
    assert_true(array_nested_source(expression, 4096) is Ok((None, _)))
  }
}

///|
test "source array profile inspection is bounded before scanning typed nodes" {
  let expression = array_profile_typed(
    (
      #|{"array":[{"literal":1},{"literal":2}]}
    ),
  )
  assert_true(array_nested_source(expression, 2) is Err(BudgetExceeded))
  // Three expression nodes plus four visited type nodes consume seven units.
  assert_true(array_nested_source(expression, 6) is Err(BudgetExceeded))
  assert_true(array_nested_source(expression, 7) is Ok((None, 7)))
}

///|
test "source array profile detects nested types behind references and objects" {
  let nested = "{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
  for
    expression in [
      array_profile_typed(
        "{\"$param\":\"matrix\"}",
        parameters=Some("{\"matrix\":" + nested + "}"),
      ),
      array_profile_typed(
        "{\"field\":\"matrix\"}",
        fields="{\"matrix\":" + nested + "}",
      ),
      array_profile_typed(
        "{\"$param\":\"wrapped\"}",
        parameters=Some(
          "{\"wrapped\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"matrix\":" +
          nested +
          "}}}",
        ),
      ),
    ] {
    // Recursive machine contracts are admitted above. A query cannot bypass
    // its selected ARRAY profile by referring to a predeclared value.
    assert_true(array_nested_source(expression, 4096) is Ok((Some(_), _)))
  }
}

///|
fn array_profile_pipeline(text : String) -> @pipeline.CheckedPipeline {
  @pipeline.check(array_profile_cursor(text), [], None, None, {
    max_steps: 16,
    max_work: 65536,
    max_text_bytes: 65536,
    max_nodes: 4096,
    max_tokens: 4096,
    max_depth: 64,
  }).unwrap()
}

///|
test "source array profile detects aggregate output without an array expression" {
  let pipeline = array_profile_pipeline(
    (
      #|[{"as":"rows","values":{"schema":{"id":{"type":"number","nullable":false},"xs":{"type":"array","nullable":false,"max_items":2,"items":{"type":"number","nullable":false}}},"rows":[{"id":1,"xs":[1,2]}]}},{"group":{"by":[],"aggregates":{"items":{"fn":"array_agg","expr":{"field":"xs"},"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"max_items":2}}}}]
    ),
  )
  // The common checker retains its recursive machine-array contract. The
  // profile reads that output rather than guessing from the aggregate name.
  assert_true(
    array_pipeline_profile(pipeline, 4096)
    is Ok((Some((@pipeline.Step(1), "items")), _)),
  )
}

///|
test "source array profile contract traversal permits object separators and is bounded" {
  let contract = @contract.read_author(
    array_profile_cursor(
      (
        #|{"type":"array","nullable":false,"max_items":1,"items":{"type":"object","nullable":false,"fields":{"xs":{"type":"array","nullable":false,"max_items":2,"items":{"type":"number","nullable":false}}}}}
      ),
    ),
    { max_nodes: 128, max_depth: 32, max_text_bytes: 4096, },
  ).unwrap()
  assert_true(array_nested_contract(contract, 3) is Err(BudgetExceeded))
  assert_true(array_nested_contract(contract, 4) is Ok((false, 4)))
  let pipeline = array_profile_pipeline(
    (
      #|[{"as":"rows","values":{"schema":{"unit":{"type":"boolean","nullable":false}},"rows":[{"unit":true}]}}]
    ),
  )
  assert_true(array_pipeline_profile(pipeline, 2) is Err(BudgetExceeded))
  assert_true(array_pipeline_profile(pipeline, 3) is Ok((None, 3)))
}
