///|
test "public expression accessors expose an owned tree and detached occurrences" {
  let limits : @expression_text.Limits = {
    max_input_bytes: 1000,
    max_tokens: 100,
    max_nodes: 100,
    max_depth: 20,
    tree: {
      max_nodes: 100,
      max_depth: 30,
      max_string_bytes: 100,
      max_total_string_bytes: 1000,
    },
  }
  let expression = @expression_text.parse("$x + $x", limits).unwrap()
  let references = @expression_text.parameter_references(expression)
  references.clear()
  assert_eq(@expression_text.parameter_references(expression).length(), 2)
  let cursor = @expression_text.tree(expression)
  let root = @decode.open_object(cursor).unwrap()
  let args = @decode.required(root, "add").unwrap()
  let detached = @decode.elements(args).unwrap()
  detached.clear()
  assert_eq(@decode.elements(args).unwrap().length(), 2)
  let names = @decode.object_field_names(cursor).unwrap()
  names[0] = "changed"
  assert_eq(@decode.object_field_names(cursor).unwrap(), ["add"])
}

///|
test "usage reports actual shared-budget work and excludes EOF" {
  let limits : @expression_text.Limits = {
    max_input_bytes: 1000,
    max_tokens: 100,
    max_nodes: 100,
    max_depth: 20,
    tree: {
      max_nodes: 100,
      max_depth: 30,
      max_string_bytes: 100,
      max_total_string_bytes: 1000,
    },
  }
  let parsed = @expression_text.parse("$a + 'é'", limits).unwrap()
  let usage = @expression_text.usage(parsed)
  assert_eq(usage.input_bytes, 9)
  assert_eq(usage.tokens, 3)
  assert_true(usage.nodes > 0)
  assert_true(
    @expression_text.parse("$a + 'é'", {
      ..limits,
      max_input_bytes: usage.input_bytes,
      max_nodes: usage.nodes,
      max_tokens: usage.tokens,
    })
    is Ok(_),
  )
  assert_true(
    @expression_text.parse("$a + 'é'", {
      ..limits,
      max_nodes: usage.nodes - 1,
    })
    is Err(_),
  )
  assert_true(
    @expression_text.parse("$a + 'é'", {
      ..limits,
      max_tokens: usage.tokens - 1,
    })
    is Err(_),
  )
}
