///|
// Until the original published Command target and input-key correspondence are
// admitted, a parsed Effect must not be discarded into a successful pure query.
test "short COMMAND refuses unresolved lowering at both actual compiler entrances" {
  for
    text in [
      "FROM pair |> EFFECT COMMAND gmail.send ID x INPUT (body = y);", "FROM pair |> EFFECT send COMMAND slack.post TARGET x ID y INPUT ();",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, pair_context(), construction_limits())
      is Err(UnsupportedEffect),
    )
    assert_true(
      compile_query_script(
        @query.single_query_script(query),
        pair_context(),
        construction_limits(),
      )
      is Err(UnsupportedEffect),
    )
  }
}

///|
test "short COMMAND lowers the original published installation and retained authored key" {
  let query = @query.parse_query(
    "FROM pair |> EFFECT COMMAND mail.send ID x INPUT (body = CONCAT('value:', CAST(y AS STRING)));",
    syntax_limits(),
  ).unwrap()
  let publication = command_publication_bind("installation")
  let program = compile(
    query,
    pair_context(),
    construction_limits(),
    command_targets=Some(publication),
  )
  assert_true(
    program is Ok(_),
    msg="a checked original Command publication must reach lowering",
  )
}

///|
fn short_command_program(text : String, mode : String) -> @program.Program {
  compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
    command_targets=Some(command_publication_bind(mode)),
  ).unwrap()
}

///|
test "short COMMAND retains the exact fixed original target and separate authored input key" {
  let program = short_command_program(
    "FROM pair |> EFFECT COMMAND mail.send ID x INPUT (body = CONCAT('value:', CAST(y AS STRING)))",
    "installation",
  )
  let header = store_capture_header(program)
  assert_eq(@program.effect_header_contract_ref(header), "command:mail.send.v1")
  assert_eq(
    @program.effect_header_published_command_target(header),
    Some(("connector://example/mailbox", None)),
  )
  assert_eq(@program.effect_header_command_input_key(header), Some("x"))
  assert_eq(@program.export_count(program), 0)
  assert_true(!semantic(program).contains("\"mapping\""))
  let captures = store_capture_steps(program).filter(step => {
    @wire.lookup(@wire.open_object(step).unwrap(), "derive") is Some(_)
  })
  assert_eq(captures.length(), 1)
  let input = store_capture_field(@program.effect_header_body(header), "input")
  let body = store_capture_field(input, "body")
  assert_true(
    @wire.lookup(@wire.open_object(body).unwrap(), "field") is Some(_),
  )
}

///|
test "short COMMAND identifier and legacy Ref targets preserve distinct declared modes" {
  for (mode, published) in [("identifier", true), ("legacy-field", false)] {
    let program = short_command_program(
      "FROM pair AS p |> EFFECT send COMMAND mail.send TARGET p.y ID p.x INPUT (body = 'literal')",
      mode,
    )
    let header = store_capture_header(program)
    assert_eq(@program.effect_header_id(header), "send")
    assert_eq(@program.effect_header_command_input_key(header), Some("x"))
    if published {
      assert_eq(
        @program.effect_header_published_command_target(header),
        Some(("connector://example/mailbox", Some("y"))),
      )
      assert_true(short_command_target_field(header) is None)
    } else {
      assert_true(
        @program.effect_header_published_command_target(header) is None,
      )
      assert_eq(short_command_target_field(header), Some("y"))
    }
  }
}

///|
test "short COMMAND target values are captured once without synthesizing a Reference" {
  for expression in ["7", "(x + 1)"] {
    let program = short_command_program(
      "FROM pair |> EFFECT COMMAND mail.send TARGET " +
      expression +
      " ID x INPUT (body = 'original')",
      "identifier",
    )
    let header = store_capture_header(program)
    let (_, field) = @program.effect_header_published_command_target(header).unwrap()
    assert_true(field is Some(_))
    assert_true(short_command_target_field(header) is None)
    assert_true(!semantic(program).contains("resource_ref"))
    assert_eq(
      store_capture_steps(program)
      .filter(step => {
        @wire.lookup(@wire.open_object(step).unwrap(), "derive") is Some(_)
      })
      .length(),
      1,
    )
  }
}

///|
test "short COMMAND rejects wrong target mode unknown fields and unresolved or ambiguous original publication" {
  for
    (text, mode) in [
      ("FROM pair |> EFFECT COMMAND mail.send TARGET x ID y", "installation"),
      ("FROM pair |> EFFECT COMMAND mail.send ID x", "identifier"),
      ("FROM pair |> EFFECT COMMAND mail.send ID x", "legacy-field"),
      (
        "FROM pair |> EFFECT COMMAND mail.send TARGET x ID missing", "identifier",
      ),
      (
        "FROM pair |> EFFECT COMMAND mail.send TARGET foreign.x ID y", "identifier",
      ),
      (
        "FROM pair |> EFFECT COMMAND mail.send ID x INPUT (body = absent)", "installation",
      ),
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
        command_targets=Some(command_publication_bind(mode)),
      )
      is Err(_),
      msg=text,
    )
  }
  let query = @query.parse_query(
    "FROM pair |> EFFECT COMMAND unknown.send ID x",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(
      query,
      pair_context(),
      construction_limits(),
      command_targets=Some(command_publication_bind("installation")),
    )
    is Err(CommandTargetBinding(UnresolvedTarget)),
  )
  let original = command_publication_alias()
  let ambiguous = command_publication_bind("installation", aliases=[
    original,
    { ..original, installation_owner_cid: "sha256:" + "f".repeat(64), },
  ])
  let query = @query.parse_query(
    "FROM pair |> EFFECT COMMAND mail.send ID x",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(
      query,
      pair_context(),
      construction_limits(),
      command_targets=Some(ambiguous),
    )
    is Err(CommandTargetBinding(AmbiguousTarget)),
  )
}

///|
test "short COMMAND ordinary and Script entrances agree and keep public Results separate" {
  let text = "FROM pair |> RESULT visible |> EFFECT sent COMMAND mail.send ID x INPUT (body = 'original')"
  let publication = command_publication_bind("installation")
  let parsed = @query.parse_query(text, syntax_limits()).unwrap()
  let first = compile(
    parsed,
    pair_context(),
    construction_limits(),
    command_targets=Some(publication),
  ).unwrap()
  let second = compile_query_script(
    @query.single_query_script(parsed),
    pair_context(),
    construction_limits(),
    command_targets=Some(publication),
  ).unwrap()
  assert_eq(semantic(first), semantic(second))
  assert_eq(@program.export_count(first), 1)
  assert_eq(@program.effect_header_id(store_capture_header(first)), "sent")
}

///|
fn short_command_target_field(header : @program.EffectHeader) -> String? {
  let target = store_capture_field(
    @program.effect_header_body(header),
    "target",
  )
  @wire.lookup(@wire.open_object(target).unwrap(), "field").map(value => {
    @wire.text(value).unwrap()
  })
}

///|
test "Source lowering retains the same original Command publication and never attaches it to structured old input" {
  let publication = command_publication_bind("installation")
  for
    (format, text) in [
      (
        @frontend.Sql,
        "SELECT x, y FROM pair |> EFFECT COMMAND mail.send ID x INPUT (body = 'original')",
      ),
      (
        @frontend.Text,
        "FROM pair |> EFFECT COMMAND mail.send ID x INPUT (body = 'original')",
      ),
    ] {
    let lowered = @frontend.lower(
      text,
      format,
      Some(pair_context()),
      command_targets=Some(publication),
    ).unwrap()
    assert_true(physical_equal(lowered.command_targets.unwrap(), publication))
    assert_eq(
      @program.effect_header_command_input_key(
        store_capture_header(lowered.program.unwrap()),
      ),
      Some("x"),
    )
  }
  for
    (format, expected) in [
      (@frontend.Json, @program.Json),
      (@frontend.Yaml, @program.Yaml),
    ] {
    let original = "{\"unparsed\":true}"
    let lowered = @frontend.lower(
      original,
      format,
      None,
      command_targets=Some(publication),
    ).unwrap()
    assert_eq(lowered.document, original)
    assert_eq(lowered.format, expected)
    assert_true(lowered.command_targets is None)
  }
}

///|
test "short COMMAND original ID range survives local SET and never becomes mutation identity" {
  let program = short_command_program(
    "FROM pair AS original |> SET x = x + 1 |> EFFECT COMMAND mail.send ID original.x INPUT (body = 'same')",
    "installation",
  )
  let header = store_capture_header(program)
  let key = @program.effect_header_command_input_key(header).unwrap()
  // SET writes a new private slot; the immutable range retains original x.
  assert_eq(key, "x")
  let derived = store_capture_steps(program).filter(step => {
    @wire.lookup(@wire.open_object(step).unwrap(), "derive") is Some(_)
  })
  assert_eq(derived.length(), 2)
  let current = short_command_program(
    "FROM pair AS original |> SET x = x + 1 |> EFFECT COMMAND mail.send ID x INPUT (body = 'same')",
    "installation",
  )
  let current_key = @program.effect_header_command_input_key(
    store_capture_header(current),
  ).unwrap()
  assert_true(current_key != key)
  assert_true(current_key.has_prefix("aql_pipe_set_"))
  assert_true(semantic(program).contains("\"input_key\""))
  assert_true(!semantic(program).contains("\"mutation_identity\""))
  let renamed = short_command_program(
    "FROM pair |> SELECT x AS key, y |> EFFECT COMMAND mail.send ID key INPUT (body = 'same')",
    "installation",
  )
  assert_eq(
    @program.effect_header_command_input_key(store_capture_header(renamed)),
    Some("key"),
  )
}

///|
test "short COMMAND CTE and set inputs use only their actual completed exported scope" {
  for
    text in [
      "WITH original AS (FROM pair) FROM original |> EFFECT COMMAND mail.send ID x INPUT (body = 'same')",
      "FROM pair |> UNION ALL (FROM pair) |> EFFECT COMMAND mail.send ID x INPUT (body = 'same')",
    ] {
    let program = short_command_program(text, "installation")
    assert_true(
      @program.effect_header_command_input_key(store_capture_header(program))
      is Some(_),
    )
    assert_eq(
      @program.effect_header_count(
        @program.collect_effect_headers(program, 10, 10000).unwrap(),
      ),
      1,
    )
  }
  let query = @query.parse_query(
    "FROM pair |> SELECT y |> EFFECT COMMAND mail.send ID x INPUT (body = 'same')",
    syntax_limits(),
    source_path="command-scope.sql",
  ).unwrap()
  // The original ID expression now shares the ordinary expression resolver.
  // Keep the missing-column refusal and demand its exact authored location.
  guard compile(
      query,
      pair_context(),
      construction_limits(),
      command_targets=Some(command_publication_bind("installation")),
    )
    is Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(origin), })
    ) else {
    fail("missing Command ID must retain the original reference diagnostic")
  }
  let span = @origin.span(origin)
  assert_eq(span.source_path, "command-scope.sql")
  assert_eq(span.start_byte, 53)
  assert_eq(span.end_byte, 54)
}

///|
test "short COMMAND and declared postlude compose one effects object without name substitution" {
  let script = @query.parse_query_script(
    "FROM pair |> RESULT visible |> EFFECT sent COMMAND mail.send ID x INPUT (body = 'same'); EFFECT later COMMAND FROM RESULT visible AS t TARGET t.x CONTRACT `command:legacy.v1` INPUT ();",
    syntax_limits(),
  ).unwrap()
  let program = compile_query_script(
    script,
    pair_context(),
    construction_limits(),
    command_targets=Some(command_publication_bind("installation")),
  ).unwrap()
  let headers = @program.collect_effect_headers(program, 10, 10000).unwrap()
  assert_eq(@program.effect_header_count(headers), 2)
  assert_eq(
    @program.effect_header_id(@program.effect_header_at(headers, 0).unwrap()),
    "sent",
  )
  assert_eq(
    @program.effect_header_id(@program.effect_header_at(headers, 1).unwrap()),
    "later",
  )
}

///|
test "short COMMAND target selection honors its original expression work bound" {
  let query = @query.parse_query(
    "FROM pair |> EFFECT COMMAND mail.send ID x INPUT (body = 'same')",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(
      query,
      pair_context(),
      { ..construction_limits(), max_expression_work: 0, },
      command_targets=Some(command_publication_bind("installation")),
    )
    is Err(CommandTargetBinding(WorkLimit)),
  )
}
