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
  assert_true(array_nested_source(expression, 3) is Ok((None, 3)))
}
