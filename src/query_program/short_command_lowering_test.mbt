///|
// Ordinary scalar input, never a fabricated mailbox Reference. Legacy target
// cases below qualify normalization only; the Common input checker must still
// demand a real ResourceRef from its original issuer.
fn short_command_context() -> Context {
  let input = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"body":{"type":"string","nullable":false},"mailbox":{"type":"string","nullable":false},"secret":{"type":"string","nullable":false}},"rows":[{"id":"operation-1","body":"original body","mailbox":"original-target","secret":"not-payload"}]},"as":"messages"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "messages", quoted: false, }],
        name: "messages",
        source: GeneratedValues(input),
        visible_fields: ["id", "body", "mailbox", "secret"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn short_command_program(
  text : String,
  mode? : String = "installation",
) -> @program.Program raise {
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  match
    compile(
      query,
      short_command_context(),
      construction_limits(),
      command_targets=Some(command_publication_bind(mode)),
    ) {
    Ok(value) => value
    Err(issue) =>
      fail("short Command lowerer: " + store_capture_issue_label(issue))
  }
}

///|
fn short_command_header(program : @program.Program) -> @program.EffectHeader {
  let headers = @program.collect_effect_headers(program, 10, 10000).unwrap()
  @program.effect_header_at(headers, 0).unwrap()
}

///|
fn short_command_private(program : @program.Program) -> @wire.Cursor {
  store_capture_field(
    store_capture_field(
      @program.stage_body(@program.stages(program).last().unwrap()),
      "results",
    ),
    "aql_private_command",
  )
}

///|
test "short COMMAND installation emits the exact original contract and private input ID without a public Result" {
  for
    text in [
      "FROM messages |> EFFECT COMMAND mail.send ID id INPUT (body = body)", "SELECT id, body FROM messages |> EFFECT COMMAND mail.send ID id INPUT (body = body)",
      "WITH original AS (FROM messages) FROM original |> EFFECT COMMAND mail.send ID id INPUT (body = body)",
    ] {
    let program = short_command_program(text)
    let header = short_command_header(program)
    assert_eq(@program.effect_header_id(header), "aql_command_effect")
    assert_eq(@program.effect_header_kind(header), "command")
    assert_eq(
      @program.effect_header_contract_ref(header),
      "command:mail.send.v1",
    )
    assert_eq(
      @program.effect_header_published_command_target(header),
      Some(("connector://example/mailbox", None)),
    )
    assert_eq(@program.effect_header_command_input_key(header), Some("id"))
    assert_eq(
      @program.effect_header_source_result(header),
      Some("aql_private_command"),
    )
    assert_eq(@program.export_count(program), 0)
    let fields = @wire.elements(
        store_capture_field(short_command_private(program), "fields"),
      )
      .unwrap()
      .map(value => @wire.text(value).unwrap())
    assert_eq(fields, ["id", "body"])
    assert_eq(
      @wire.text(
        store_capture_field(
          store_capture_field(
            store_capture_field(@program.effect_header_body(header), "input"),
            "body",
          ),
          "field",
        ),
      ).unwrap(),
      "body",
    )
  }
}

///|
test "short COMMAND target identifier input ID and payload keep separate captured slots" {
  let program = short_command_program(
    "FROM messages |> EFFECT send COMMAND mail.send TARGET mailbox ID id INPUT (body = body)",
    mode="identifier",
  )
  let header = short_command_header(program)
  assert_eq(@program.effect_header_id(header), "send")
  assert_eq(
    @program.effect_header_published_command_target(header),
    Some(("connector://example/mailbox", Some("mailbox"))),
  )
  assert_eq(@program.effect_header_command_input_key(header), Some("id"))
  assert_eq(
    @wire.elements(
      store_capture_field(short_command_private(program), "fields"),
    )
    .unwrap()
    .map(value => @wire.text(value).unwrap()),
    ["id", "mailbox", "body"],
  )
  let legacy = short_command_program(
    "FROM messages |> EFFECT COMMAND mail.send TARGET mailbox ID id INPUT (body = body)",
    mode="legacy-field",
  )
  let old_header = short_command_header(legacy)
  assert_true(
    @program.effect_header_published_command_target(old_header) is None,
  )
  assert_eq(
    @wire.text(
      store_capture_field(
        store_capture_field(@program.effect_header_body(old_header), "target"),
        "field",
      ),
    ).unwrap(),
    "mailbox",
  )
  assert_eq(@program.effect_header_command_input_key(old_header), Some("id"))
}

///|
test "short COMMAND expressions use one ordinary derive before the closed capture" {
  let program = short_command_program(
    "FROM messages |> EFFECT COMMAND mail.send TARGET CONCAT(mailbox, '.suffix') ID id INPUT (body = CONCAT(body, '!'))",
    mode="identifier",
  )
  let derives = store_capture_steps(program).filter(step => {
    @wire.lookup(@wire.open_object(step).unwrap(), "derive") is Some(_)
  })
  assert_eq(derives.length(), 1)
  let values = store_capture_field(derives[0], "derive")
  assert_eq(@wire.object_length(values), Some(2))
  for (index, original, suffix) in [(0, "mailbox", ".suffix"), (1, "body", "!")] {
    let expression = @wire.field_at(values, index).unwrap().1
    let args = @wire.elements(store_capture_field(expression, "concat_strict")).unwrap()
    assert_eq(args.length(), 2)
    assert_eq(
      @wire.text(store_capture_field(args[0], "field")).unwrap(),
      original,
    )
    assert_eq(
      @wire.text(store_capture_field(args[1], "literal")).unwrap(),
      suffix,
    )
  }
  assert_eq(@program.export_count(program), 0)
}

///|
test "short COMMAND omitted and empty INPUT stay empty rather than copying columns" {
  let omitted = short_command_program(
    "FROM messages |> EFFECT COMMAND mail.send ID id",
  )
  let empty = short_command_program(
    "FROM messages |> EFFECT COMMAND mail.send ID id INPUT ()",
  )
  assert_eq(semantic(omitted), semantic(empty))
  assert_eq(
    @wire.object_length(
      store_capture_field(
        @program.effect_header_body(short_command_header(empty)),
        "input",
      ),
    ),
    Some(0),
  )
  assert_eq(
    @wire.elements(store_capture_field(short_command_private(empty), "fields"))
    .unwrap()
    .map(value => @wire.text(value).unwrap()),
    ["id"],
  )
}

///|
test "short COMMAND target mode is resolved before unknown ID or payload expressions" {
  for
    (mode, text) in [
      (
        "installation", "FROM messages |> EFFECT COMMAND mail.send TARGET absent ID absent INPUT (body = absent)",
      ),
      (
        "identifier", "FROM messages |> EFFECT COMMAND mail.send ID absent INPUT (body = absent)",
      ),
      (
        "legacy-field", "FROM messages |> EFFECT COMMAND mail.send ID absent INPUT (body = absent)",
      ),
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(
        query,
        short_command_context(),
        construction_limits(),
        command_targets=Some(command_publication_bind(mode)),
      )
      is Err(InvalidQuery),
    )
  }
  let missing = @query.parse_query(
    "FROM messages |> EFFECT COMMAND missing.send ID absent INPUT ()",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(
      missing,
      short_command_context(),
      construction_limits(),
      command_targets=Some(command_publication_bind("installation")),
    )
    is Err(CommandTargetBinding(UnresolvedTarget)),
  )
}

///|
test "short COMMAND preserves only explicit public Results and combines ordinary postludes" {
  let text = "FROM messages |> RESULT original |> WHERE body != '' |> EFFECT send COMMAND mail.send ID id INPUT (body = body); EFFECT audit COMMAND FROM RESULT original AS t TARGET t.mailbox CONTRACT `command:audit.v1` INPUT (body = t.body);"
  let program = short_command_program(text)
  assert_eq(@program.export_count(program), 1)
  let headers = @program.collect_effect_headers(program, 10, 10000).unwrap()
  assert_eq(@program.effect_header_count(headers), 2)
  assert_eq(
    @program.effect_header_id(@program.effect_header_at(headers, 0).unwrap()),
    "send",
  )
  assert_eq(
    @program.effect_header_id(@program.effect_header_at(headers, 1).unwrap()),
    "audit",
  )
}

///|
test "short COMMAND default effect name cannot collide with an explicit postlude" {
  let query = @query.parse_query_script(
    "FROM messages |> RESULT original |> EFFECT COMMAND mail.send ID id INPUT (body = body); EFFECT aql_command_effect COMMAND FROM RESULT original AS t TARGET t.mailbox CONTRACT c INPUT ();",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      query,
      short_command_context(),
      construction_limits(),
      command_targets=Some(command_publication_bind("installation")),
    )
    is Err(DuplicateOutput),
  )
}

///|
test "short COMMAND completed set and original Model continuation retain the same private ID" {
  for
    text in [
      "FROM messages |> UNION ALL (FROM messages) |> EFFECT COMMAND mail.send ID id INPUT (body = body)",
      "FROM messages |> ASSERT UNIQUE BY (id) |> INFER score ITEM KEY (id) INPUT (n = body) KEEP (id, body) AS assessment |> RESULT classified |> WHERE body != '' |> EFFECT COMMAND mail.send ID id INPUT (body = body)",
    ] {
    let program = short_command_program(text)
    assert_eq(
      @program.effect_header_command_input_key(short_command_header(program)),
      Some("id"),
    )
    assert_eq(
      @program.effect_header_source_result(short_command_header(program)),
      Some("aql_private_command"),
    )
  }
}

///|
test "short COMMAND Source lower retains the exact original publication only for its operation" {
  let publication = command_publication_bind("installation")
  let text = "FROM messages |> EFFECT COMMAND mail.send ID id INPUT (body = body)"
  let lowered = @frontend.lower(
    text,
    @frontend.Text,
    Some(short_command_context()),
    command_targets=Some(publication),
  ).unwrap()
  assert_true(physical_equal(lowered.command_targets.unwrap(), publication))
  assert_true(lowered.update_targets is None)
  assert_true(lowered.store_targets is None)
  let ordinary = @frontend.lower(
    "SELECT id FROM messages",
    @frontend.Sql,
    Some(short_command_context()),
    command_targets=Some(publication),
  ).unwrap()
  assert_true(ordinary.command_targets is None)
  let machine = @frontend.lower(
    lowered.document,
    @frontend.Json,
    None,
    command_targets=Some(publication),
  ).unwrap()
  assert_true(machine.command_targets is None)
}
