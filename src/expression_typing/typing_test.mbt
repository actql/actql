///|
fn test_limits() -> @expression_typing.Limits {
  {
    max_nodes: 100000,
    max_depth: 30000,
    max_work: 10000000,
    max_text_bytes: 10000000,
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000000, max_nodes: 1000000, max_depth: 40000, },
      source_path="expression.aql",
    ).unwrap(),
    {
      max_nodes: 1000000,
      max_depth: 40000,
      max_string_bytes: 10000000,
      max_total_string_bytes: 10000000,
    },
  ).unwrap()
}

///|
fn syntax(text : String) -> @syntax.Expression {
  @syntax.admit(cursor(text), {
    max_nodes: 2000000,
    max_depth: 40000,
    max_text_bytes: 20000000,
    max_tokens: 1000000,
    tree: {
      max_nodes: 1000000,
      max_depth: 40000,
      max_string_bytes: 10000000,
      max_total_string_bytes: 20000000,
    },
  }).unwrap()
}

///|
fn env(
  fields? : String = "{}",
  parameters? : String = "null",
) -> @expression_typing.Environment {
  let scope = @contract.read_author(
    cursor("{\"type\":\"object\",\"nullable\":false,\"fields\":" + fields + "}"),
    { max_nodes: 100000, max_depth: 30000, max_text_bytes: 10000000, },
  ).unwrap()
  let declarations = @parameter.read_declarations(
    if parameters == "null" {
      None
    } else {
      Some(cursor(parameters))
    },
    {
      max_parameters: 100000,
      max_nodes: 100000,
      max_depth: 30000,
      max_text_bytes: 10000000,
    },
  ).unwrap()
  {
    fields: Some(scope),
    left: None,
    right: None,
    parameters: Some(declarations),
  }
}

///|
fn assert_type(
  source : String,
  fields : String,
  parameters : String,
  expected : String,
) -> Unit raise {
  let result = @expression_typing.check(
    syntax(source),
    env(fields~, parameters~),
    test_limits(),
  )
  match result {
    Err(issue) =>
      fail(
        "unexpected type rejection: " +
        source +
        " / " +
        @debug.to_string(issue.kind),
      )
    Ok(value) => {
      let expected = @contract.read_checked(cursor(expected), {
        max_nodes: 100000,
        max_depth: 30000,
        max_text_bytes: 10000000,
      }).unwrap()
      assert_true(
        @contract.type_equal(
          @expression_typing.result_type(value),
          expected,
          100000,
        ),
        msg=source,
      )
      assert_eq(
        @contract.stringify_checked(
          @expression_typing.result_type(value),
          1000000,
          100000,
          30000,
        ),
        @contract.stringify_checked(expected, 1000000, 100000, 30000),
      )
    }
  }
}

///|
fn assert_rejected(
  source : String,
  fields : String,
  parameters : String,
  expected : String,
) -> Unit raise {
  let result = @expression_typing.check(
    syntax(source),
    env(fields~, parameters~),
    test_limits(),
  )
  match result {
    Err(issue) => {
      let name = match issue.kind {
        NullTypeUnresolved => "NullTypeUnresolved"
        TypeMismatch(_) => "TypeMismatch"
        UnknownField(_) => "UnknownField"
        UnknownParameter(_) => "UnknownParameter"
        MissingJoinScope(_) => "MissingJoinScope"
        InvalidStaticOption(_) => "InvalidStaticOption"
        ForbiddenConstructorValue => "ForbiddenConstructorValue"
        _ => "other"
      }
      assert_eq(name, expected, msg=source)
    }
    Ok(_) => fail("unexpected type acceptance: " + source)
  }
}

///|
test "peer evidence resolves nested null without changing the empty array root" {
  assert_type(
    "\"if(TRUE, [NULL], [1])\"", "{}", "null", "{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"number\",\"nullable\":true}}",
  )
  assert_type(
    "\"if(TRUE, [], [1])\"", "{}", "null", "{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  assert_rejected(
    "\"len(coalesce(NULL, NULL))\"", "{}", "null", "NullTypeUnresolved",
  )
  assert_rejected("\"TRUE + 1\"", "{}", "null", "TypeMismatch")
}

///|
test "annotations retain empty-array and literal-null types separately from joins" {
  let environment = env(
    fields="{\"a\":{\"type\":\"array\",\"nullable\":true,\"max_items\":5,\"items\":{\"type\":\"number\",\"nullable\":false}}}",
  )
  let value = @expression_typing.check(
    syntax("\"if(TRUE, [], a)\""),
    environment,
    test_limits(),
  ).unwrap()
  let empty = @expression_typing.node_at(value, 2).unwrap().contract
  assert_true(!empty.nullable)
  match empty.shape {
    Array(item, max_items~) => {
      assert_eq(max_items, Some(0L))
      assert_true(!item.nullable)
    }
    _ => fail("expected empty array annotation")
  }
  assert_true(@expression_typing.result_type(value).nullable)
  let cast = @expression_typing.check(
    syntax("\"CAST(NULL AS number)\""),
    env(),
    test_limits(),
  ).unwrap()
  assert_eq(@expression_typing.node_count(cast), 2)
  assert_true(@expression_typing.node_at(cast, 1).unwrap().contract.nullable)
  assert_true(@expression_typing.node_at(cast, -1) is None)
  assert_true(@expression_typing.node_at(cast, 2) is None)
  let case_value = @expression_typing.check(
    syntax("\"CASE WHEN TRUE THEN 1 END\""),
    env(),
    test_limits(),
  ).unwrap()
  assert_eq(@expression_typing.node_count(case_value), 4)
  assert_true(
    @expression_typing.node_at(case_value, 3).unwrap().contract.nullable,
  )
}

///|
test "profile and pattern obligations include undemanded branches and stay detached" {
  let source = syntax("\"if(TRUE, TRUE, regex_match('a', $p))\"")
  let environment = env(
    parameters="{\"p\":{\"type\":\"string\",\"default\":\"(\"}}",
  )
  let typed = @expression_typing.check(source, environment, test_limits()).unwrap()
  assert_eq(@expression_typing.required_profiles(typed), ["actql-text-time/0.1"])
  let obligations = @expression_typing.pending_validations(typed)
  assert_eq(obligations.length(), 3)
  assert_true(obligations.any(o => o.kind is HostEnvelope))
  assert_true(obligations.any(o => o.kind is PatternValidation("regex_match")))
  assert_true(obligations.all(o => o.node_index == 3))
  obligations.clear()
  let profiles = @expression_typing.required_profiles(typed)
  profiles.clear()
  assert_eq(@expression_typing.pending_validations(typed).length(), 3)
  assert_eq(@expression_typing.required_profiles(typed).length(), 1)
  // A declaration default is not treated as the invocation's bound pattern.
  assert_eq(
    @parameter.declaration_count(
      @expression_typing.environment(typed).parameters.unwrap(),
    ),
    1,
  )
  assert_true(
    @parameter.declaration_at(environment.parameters.unwrap(), -1) is None,
  )
  assert_true(
    @parameter.declaration_at(environment.parameters.unwrap(), 1) is None,
  )
  let kept = @syntax.tree(@expression_typing.expression(typed))
  assert_eq(
    @decode.cursor_span(kept),
    @decode.cursor_span(@syntax.tree(source)),
  )
  let bad_literal = @expression_typing.check(
    syntax("\"regex_match('a', '(')\""),
    env(),
    test_limits(),
  ).unwrap()
  assert_true(
    @expression_typing.pending_validations(bad_literal).any(o => {
      o.kind is PatternValidation("regex_match")
    }),
  )
  assert_rejected(
    "\"if(TRUE, TRUE, regex_match('a', 'a', 'i'))\"", "{}", "null", "InvalidStaticOption",
  )
}

///|
test "regex static arguments retain bound validation without evaluating defaults" {
  let environment = env(
    parameters="{\"capture\":{\"type\":\"number\",\"nullable\":true,\"default\":-1},\"replacement\":{\"type\":\"string\",\"nullable\":true,\"default\":\"$99\"}}",
  )
  for
    (source, tag) in [
      ("\"regex_extract('a', '(a)', $capture)\"", "regex_extract"),
      ("\"regex_replace('a', '(a)', $replacement)\"", "regex_replace"),
      ("\"regex_extract('a', '(a)', 99)\"", "regex_extract"),
      ("\"regex_replace('a', '(a)', '$99')\"", "regex_replace"),
    ] {
    let typed = @expression_typing.check(
      syntax(source),
      environment,
      test_limits(),
    ).unwrap()
    assert_true(
      @expression_typing.pending_validations(typed).any(o => {
        o.kind is PatternValidation(name) && name == tag
      }),
    )
  }
  assert_rejected(
    "\"if(TRUE, 'ok', regex_replace('a', '(a)', concat('x', 'y')))\"", "{}", "null",
    "InvalidStaticOption",
  )
}

///|
test "qualified template fields require their own scalar scope" {
  let normal = env(fields="{\"n\":{\"type\":\"number\",\"nullable\":false}}")
  for side in ["left", "right"] {
    let expression = syntax("{\"template\":\"{" + side + ".n}\"}")
    assert_true(
      @expression_typing.check(expression, normal, test_limits())
      is Err({ kind: MissingJoinScope(_), .. }),
    )
    let scalar = env(fields="{\"n\":{\"type\":\"string\",\"nullable\":true}}")
    let environment : @expression_typing.Environment = {
      ..normal,
      left: scalar.fields,
      right: scalar.fields,
    }
    let result = @expression_typing.check(
      expression,
      environment,
      test_limits(),
    ).unwrap()
    assert_true(@expression_typing.result_type(result).nullable)
    let absent = syntax("{\"template\":\"{" + side + ".missing}\"}")
    assert_true(
      @expression_typing.check(absent, environment, test_limits())
      is Err({ kind: UnknownField(_), .. }),
    )
    let nonscalar = env(fields="{\"n\":{\"type\":\"json\",\"nullable\":false}}")
    let environment : @expression_typing.Environment = {
      ..normal,
      left: nonscalar.fields,
      right: nonscalar.fields,
    }
    assert_true(
      @expression_typing.check(expression, environment, test_limits())
      is Err({ kind: TypeMismatch("printable template field"), .. }),
    )
  }
}

///|
test "join scopes never fall back to ordinary fields and parameters remain declared" {
  let normal = env(fields="{\"n\":{\"type\":\"string\",\"nullable\":false}}")
  let left = env(fields="{\"n\":{\"type\":\"number\",\"nullable\":true}}").fields
  let environment : @expression_typing.Environment = { ..normal, left, }
  let value = @expression_typing.check(
    syntax("\"left.n\""),
    environment,
    test_limits(),
  ).unwrap()
  assert_true(@expression_typing.result_type(value).shape is Number)
  assert_true(@expression_typing.result_type(value).nullable)
  let missing = @expression_typing.check(
    syntax("\"right.n\""),
    environment,
    test_limits(),
  )
  assert_true(missing is Err({ kind: MissingJoinScope("right"), .. }))
  let absent = @expression_typing.check(
    syntax("\"left.absent\""),
    environment,
    test_limits(),
  )
  assert_true(absent is Err({ kind: UnknownField("absent"), .. }))
  let parameters = env(
    parameters="{\"x\":{\"type\":\"number\",\"nullable\":true,\"default\":1}}",
  )
  let value = @expression_typing.check(
    syntax("\"$x\""),
    parameters,
    test_limits(),
  ).unwrap()
  assert_true(@expression_typing.result_type(value).nullable)
  assert_true(
    @syntax.parameter_references(@expression_typing.expression(value))[0].name ==
    "x",
  )
}

///|
test "fixed signatures and independently typed operands determine only local NULLs" {
  for source in ["\"NULL / NULL\"", "\"NULL % NULL\"", "\"NULL / 1\""] {
    assert_type(source, "{}", "null", "{\"type\":\"number\",\"nullable\":true}")
  }
  assert_type(
    "\"date_diff(NULL, ts, 's')\"", "{\"ts\":{\"type\":\"timestamp\",\"nullable\":false}}",
    "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  assert_type(
    "\"vector_score(NULL,v,'dot')\"", "{\"v\":{\"type\":\"vector\",\"nullable\":false,\"dimensions\":3}}",
    "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  assert_rejected("\"NULL + NULL\"", "{}", "null", "NullTypeUnresolved")
  assert_rejected("\"negate(NULL)\"", "{}", "null", "NullTypeUnresolved")
}

///|
test "type checking does not evaluate invalid literal data" {
  for source in ["\"sqrt(-1)\"", "\"to_number('invalid')\"", "\"1 / 0\""] {
    assert_type(
      source, "{}", "null", "{\"type\":\"number\",\"nullable\":false}",
    )
  }
  assert_type(
    "\"substring('abc',1,-1)\"", "{}", "null", "{\"type\":\"string\",\"nullable\":false}",
  )
}

///|
test "constructor capability checks recurse through arrays and objects" {
  assert_rejected(
    "\"[v]\"", "{\"v\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"r\":{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"X\"}}}}",
    "null", "ForbiddenConstructorValue",
  )
  assert_rejected(
    "{\"empty_array\":{\"items\":{\"type\":\"artifact_ref\",\"nullable\":false}}}",
    "{}", "null", "ForbiddenConstructorValue",
  )
  assert_type(
    "{\"literal\":{\"$decimal\":{\"precision\":1,\"scale\":0,\"coefficient\":\"1\"}}}",
    "{}", "null", "{\"type\":\"json\",\"nullable\":false}",
  )
}

///|
test "vector dimension sums are exact without adding a safe-integer ceiling" {
  let fields = "{\"a\":{\"type\":\"vector\",\"nullable\":false,\"dimensions\":9007199254740992},\"b\":{\"type\":\"vector\",\"nullable\":false,\"dimensions\":2},\"c\":{\"type\":\"vector\",\"nullable\":false,\"dimensions\":1}}"
  assert_type(
    "\"vector_concat(a,b)\"", fields, "null", "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":9007199254740994,\"element_type\":\"f32\"}",
  )
  assert_rejected("\"vector_concat(a,c)\"", fields, "null", "TypeMismatch")
  assert_rejected("\"vector_concat(c,a)\"", fields, "null", "TypeMismatch")
  for
    expression in [
      "vector_concat(a,c,c)", "vector_concat(c,a,c)", "vector_concat(c,c,a)",
    ] {
    assert_type(
      "\"" + expression + "\"",
      fields,
      "null",
      "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":9007199254740994,\"element_type\":\"f32\"}",
    )
  }
}

///|
test "vector dimension totals retain high exponent bits and reject overflow" {
  let fields = "{\"a\":{\"type\":\"vector\",\"nullable\":false,\"dimensions\":8.98846567431158e307},\"b\":{\"type\":\"vector\",\"nullable\":false,\"dimensions\":8.988465674311578e307},\"c\":{\"type\":\"vector\",\"nullable\":false,\"dimensions\":1}}"
  for expression in ["vector_concat(a,b)", "vector_concat(b,a)"] {
    assert_type(
      "\"" + expression + "\"",
      fields,
      "null",
      "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":1.7976931348623157e308,\"element_type\":\"f32\"}",
    )
  }
  for
    expression in [
      "vector_concat(a,a)", "vector_concat(a,b,c)", "vector_concat(c,b,a)",
    ] {
    assert_rejected("\"" + expression + "\"", fields, "null", "TypeMismatch")
  }
}

///|
test "deep checking and deep result types are iterative" {
  let depth = 10000
  let source = "{\"not\":".repeat(depth) +
    "{\"literal\":true}" +
    "}".repeat(depth)
  let result = @expression_typing.check(syntax(source), env(), test_limits()).unwrap()
  assert_eq(@expression_typing.node_count(result), depth + 1)
  assert_true(@expression_typing.result_type(result).shape is Boolean)
  let arrays = "{\"array\":[".repeat(depth) +
    "{\"literal\":1}" +
    "]}".repeat(depth)
  let result = @expression_typing.check(syntax(arrays), env(), test_limits()).unwrap()
  assert_eq(@expression_typing.node_count(result), depth + 1)
  let mut current = @expression_typing.result_type(result)
  for _ in 0..<depth {
    match current.shape {
      Array(child, max_items=Some(1L)) => current = child
      _ => fail("nested array type")
    }
  }
  assert_true(current.shape is Number)
}

///|
test "budgets are cumulative, monotone, and include supplied context" {
  let input = syntax("\"[1,2,3]\"")
  let environment = env()
  let base = test_limits()
  assert_true(
    @expression_typing.check(input, environment, {
      ..base,
      max_nodes: 4,
      max_depth: 1,
    })
    is Ok(_),
  )
  for
    limits in [
      { ..base, max_nodes: 3, },
      { ..base, max_depth: 0, },
      { ..base, max_work: 0, },
      { ..base, max_text_bytes: 0, },
    ] {
    assert_true(
      @expression_typing.check(input, environment, limits)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  assert_true(
    @expression_typing.check(input, environment, { ..base, max_nodes: -1, })
    is Err({ kind: InvalidLimits, .. }),
  )
  for by_text in [false, true] {
    let mut low = 0
    let mut high = 2000
    while low < high {
      let mid = low + (high - low) / 2
      let limits = if by_text {
        { ..base, max_text_bytes: mid, }
      } else {
        { ..base, max_work: mid, }
      }
      if @expression_typing.check(input, environment, limits) is Ok(_) {
        high = mid
      } else {
        low = mid + 1
      }
    }
    let exact = if by_text {
      { ..base, max_text_bytes: low, }
    } else {
      { ..base, max_work: low, }
    }
    let less = if by_text {
      { ..base, max_text_bytes: low - 1, }
    } else {
      { ..base, max_work: low - 1, }
    }
    assert_true(@expression_typing.check(input, environment, exact) is Ok(_))
    assert_true(
      @expression_typing.check(input, environment, less)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  let deep = env(
    fields="{\"a\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}}",
  )
  assert_true(
    @expression_typing.check(syntax("\"1\""), deep, { ..base, max_depth: 1, })
    is Err({ kind: BudgetExceeded, .. }),
  )
}

///|
test "wide field access reuses the prepared scope" {
  let count = 8000
  let entries : Array[(String, @contract.Contract)] = []
  let children : Array[String] = []
  for i in 0..<count {
    let name = "f" + i.to_string()
    entries.push((name, @contract.primitive(NumberType, nullable=false)))
    children.push("{\"field\":\"" + name + "\"}")
  }
  let fields = @contract.object_contract(
    entries,
    nullable=false,
    max_fields=count,
    max_name_bytes=100000,
  ).unwrap()
  let input = syntax("{\"array\":[" + children.join(",") + "]}")
  let environment : @expression_typing.Environment = {
    fields: Some(fields),
    left: None,
    right: None,
    parameters: None,
  }
  let result = @expression_typing.check(input, environment, {
    ..test_limits(),
    max_work: 500000,
  }).unwrap()
  assert_eq(@expression_typing.node_count(result), count + 1)
}

///|
test "nested unresolved peers retain nullability through compressed evidence chains" {
  let depth = 5000
  let body = "{\"coalesce\":[{\"literal\":null},".repeat(depth) +
    "{\"literal\":null}" +
    "]}".repeat(depth)
  let source = "{\"if\":[{\"literal\":true}," + body + ",{\"literal\":1}]}"
  let result = @expression_typing.check(syntax(source), env(), {
    ..test_limits(),
    max_work: 1000000,
  }).unwrap()
  assert_true(@expression_typing.result_type(result).nullable)
  for i in 2..<(@expression_typing.node_count(result) - 1) {
    let c = @expression_typing.node_at(result, i).unwrap().contract
    assert_true(c.nullable)
    assert_true(c.shape is Number)
  }
}

///|
test "diagnostics and synthetic roles point into the retained syntax" {
  let input = syntax("{\"add\":[{\"literal\":1},{\"field\":\"missing\"}]}")
  let root = @syntax.tree(input)
  let expected = @decode.elements(
      @decode.lookup(@decode.open_object(root).unwrap(), "add").unwrap(),
    ).unwrap()[1]
  match @expression_typing.check(input, env(), test_limits()) {
    Err(issue) => {
      assert_true(issue.kind is UnknownField("missing"))
      assert_eq(
        @decode.cursor_path(issue.source),
        @decode.cursor_path(expected),
      )
      assert_eq(
        @decode.cursor_span(issue.source),
        @decode.cursor_span(expected),
      )
    }
    _ => fail("expected missing field")
  }
  let value = @expression_typing.check(
    syntax("\"1 IN (1,NULL)\""),
    env(),
    test_limits(),
  ).unwrap()
  assert_eq(@expression_typing.node_at(value, 0).unwrap().role, ExpressionNode)
  assert_eq(@expression_typing.node_at(value, 2).unwrap().role, MembershipList)
  assert_eq(
    @expression_typing.node_at(value, 3).unwrap().role,
    MembershipElement,
  )
  assert_eq(
    @expression_typing.node_at(value, 4).unwrap().role,
    MembershipElement,
  )
  let value = @expression_typing.check(
    syntax("\"CASE WHEN TRUE THEN 1 END\""),
    env(),
    test_limits(),
  ).unwrap()
  assert_eq(@expression_typing.node_at(value, 3).unwrap().role, ImplicitElse)
  let environment = env()
  for
    fields in [
      Some(@contract.primitive(NumberType, nullable=false)),
      Some(@contract.with_nullability(environment.fields.unwrap(), true)),
    ] {
    assert_true(
      @expression_typing.check(
        syntax("\"1\""),
        { ..environment, fields, },
        test_limits(),
      )
      is Err({ kind: InvalidScope("fields"), .. }),
    )
  }
}
