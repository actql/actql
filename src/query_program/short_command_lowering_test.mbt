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
  let selection = lowered.command_selection.unwrap()
  let selected = short_command_selection_target(selection)
  let expected = resolve_command_target_binding(
    publication,
    command_publication_alias().name,
    100,
  ).unwrap()
  assert_true(
    physical_equal(
      resolved_command_target_contract(selected),
      resolved_command_target_contract(expected),
    ),
  )
  assert_eq(short_command_selection_stage(selection), 0)
  assert_eq(short_command_selection_effect(selection), "aql_command_effect")
  assert_true(lowered.update_targets is None)
  assert_true(lowered.store_targets is None)
  let ordinary = @frontend.lower(
    "SELECT id FROM messages",
    @frontend.Sql,
    Some(short_command_context()),
    command_targets=Some(publication),
  ).unwrap()
  assert_true(ordinary.command_selection is None)
  let machine = @frontend.lower(
    lowered.document,
    @frontend.Json,
    None,
    command_targets=Some(publication),
  ).unwrap()
  assert_true(machine.command_selection is None)
}

///|
fn short_command_checked_candidate(
  text : String,
  mode : String,
) -> @check.EffectComputationCandidate {
  let environment = short_command_checked_environment(mode)
  let publication = @source_publication.published_command_targets(
      environment,
      command_source_publication(environment),
    )
    .unwrap()
    .unwrap()
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    short_command_context(),
    construction_limits(),
    command_targets=Some(publication),
  ).unwrap()
  @check.prepare_effect_computation_candidate(
    program,
    environment,
    None,
    [],
    check_limits(),
    10,
    10000,
  ).unwrap()
}

///|
fn short_command_checked_targets(
  candidate : @check.EffectComputationCandidate,
) -> @stage_results.EffectCommandTargets {
  let results = @stage_results.bind_effect_results(
    @check.effect_computation_headers(candidate),
    @check.effect_computation_stage_results(candidate),
    10000,
  ).unwrap()
  @stage_results.bind_effect_command_targets(
    results,
    @check.effect_computation_catalog_references(candidate),
    10000,
  ).unwrap()
}

///|
test "short COMMAND actual Common binding keeps typed payload and original ID distinct from bounded target" {
  for
    (mode, target) in [
      ("installation", ""),
      ("identifier", " TARGET 'mailbox-1'"),
    ] {
    let candidate = short_command_checked_candidate(
      "FROM messages |> EFFECT COMMAND mail.send" +
      target +
      " ID id INPUT (body = body)",
      mode,
    )
    let targets = short_command_checked_targets(candidate)
    let inputs = @stage_results.bind_effect_command_inputs(targets, {
      max_work: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    }).unwrap()
    let input = @stage_results.effect_command_input_at(inputs, 0).unwrap()
    assert_eq(
      @schema.field_reference_name(
        @stage_results.effect_command_input_key(input).unwrap(),
      ),
      "id",
    )
    assert_eq(@stage_results.effect_command_input_field_count(input), 1)
    assert_eq(
      @stage_results.effect_command_input_field_name(
        @stage_results.effect_command_input_field_at(input, 0).unwrap(),
      ),
      "body",
    )
    let original = @stage_results.effect_command_input_target(input)
    assert_eq(
      @environment.command_target_id(
        @stage_results.effect_command_target_contract(original),
      ),
      "command:mail.send.v1",
    )
  }
}

///|
test "short COMMAND actual Common rejects absent or incompatible required payload without defaults" {
  for
    (input, kind) in [
      ("", @stage_results.EffectCommandInputIssueKind::MissingField("body")),
      (
        " INPUT ()",
        @stage_results.EffectCommandInputIssueKind::MissingField("body"),
      ),
      (
        " INPUT (body = 1)",
        @stage_results.EffectCommandInputIssueKind::IncompatibleField("body"),
      ),
    ] {
    let candidate = short_command_checked_candidate(
      "FROM messages |> EFFECT COMMAND mail.send ID id" + input,
      "installation",
    )
    let targets = short_command_checked_targets(candidate)
    let issue = @stage_results.bind_effect_command_inputs(targets, {
      max_work: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    }).unwrap_err()
    assert_eq(@stage_results.effect_command_input_issue_kind(issue), kind)
  }
}

///|
test "short COMMAND actual Common never promotes a scalar field into a legacy ResourceRef" {
  let candidate = short_command_checked_candidate(
    "FROM messages |> EFFECT COMMAND mail.send TARGET mailbox ID id INPUT (body = body)",
    "legacy-field",
  )
  let issue = @stage_results.bind_effect_results(
    @check.effect_computation_headers(candidate),
    @check.effect_computation_stage_results(candidate),
    10000,
  ).unwrap_err()
  assert_eq(
    @stage_results.effect_result_binding_issue_kind(issue),
    @stage_results.InvalidCommandTarget,
  )
}

///|
test "short COMMAND actual Common enforces the original identifier domain beyond matching scalar kind" {
  let candidate = short_command_checked_candidate(
    "FROM messages |> EFFECT COMMAND mail.send TARGET mailbox ID id INPUT (body = body)",
    "identifier",
  )
  let results = @stage_results.bind_effect_results(
    @check.effect_computation_headers(candidate),
    @check.effect_computation_stage_results(candidate),
    10000,
  ).unwrap()
  let issue = @stage_results.bind_effect_command_targets(
    results,
    @check.effect_computation_catalog_references(candidate),
    10000,
  ).unwrap_err()
  assert_eq(
    @stage_results.effect_command_target_issue_kind(issue),
    @stage_results.PublishedCommandIdentifierMismatch,
  )
}

///|
test "short COMMAND legacy selection retains installation occurrence absent from canonical field target" {
  let first = command_publication_alias()
  let other = {
    ..first,
    name: [
      { value: "other", quoted: false, },
      { value: "send", quoted: false, },
    ],
    target_ref: "connector://other/mailbox",
    installation_owner_cid: "sha256:" + "f".repeat(64),
  }
  let publication = command_publication_bind("legacy-field", aliases=[
    first, other,
  ])
  let lowered = ["mail.send", "other.send"].map(operation => {
    @frontend.lower(
      "FROM messages |> EFFECT COMMAND " +
      operation +
      " TARGET mailbox ID id INPUT (body = body)",
      @frontend.Text,
      Some(short_command_context()),
      command_targets=Some(publication),
    ).unwrap()
  })
  assert_eq(
    semantic(lowered[0].program.unwrap()),
    semantic(lowered[1].program.unwrap()),
  )
  for index, original in [first, other] {
    let selected = lowered[index].command_selection.unwrap()
    let target = short_command_selection_target(selected)
    assert_eq(
      resolved_command_target(target),
      (original.target_ref, original.command_ref),
    )
    assert_eq(
      resolved_command_target_identity(target).3,
      original.installation_owner_cid,
    )
    assert_true(resolved_command_target_binding(target) is None)
    assert_eq(short_command_selection_stage(selected), 0)
    assert_eq(short_command_selection_effect(selected), "aql_command_effect")
  }
}

///|
test "short COMMAND retained occurrence comes from the actual Model continuation emission" {
  let source = "FROM messages |> ASSERT UNIQUE BY (id) |> INFER score ITEM KEY (id) INPUT (n = body) KEEP (id, body) AS assessment |> RESULT classified |> WHERE body != '' |> EFFECT send COMMAND mail.send ID id INPUT (body = body)"
  let lowered = @frontend.lower(
    source,
    @frontend.Text,
    Some(short_command_context()),
    command_targets=Some(command_publication_bind("installation")),
  ).unwrap()
  let selected = lowered.command_selection.unwrap()
  let program = lowered.program.unwrap()
  assert_eq(@program.stage_count(program), 2)
  let header = short_command_header(program)
  assert_eq(
    short_command_selection_stage(selected),
    @program.effect_header_stage(header),
  )
  assert_eq(short_command_selection_stage(selected), 1)
  assert_eq(
    short_command_selection_effect(selected),
    @program.effect_header_id(header),
  )
  assert_eq(short_command_selection_effect(selected), "send")
}

///|
test "short COMMAND private capture is not an authored Result for a long postlude" {
  for name in ["aql_private_command"] {
    let script = @query.parse_query_script(
      "FROM messages |> EFFECT COMMAND mail.send ID id INPUT (body = body); EFFECT audit COMMAND FROM RESULT " +
      name +
      " AS t TARGET t.id CONTRACT `command:audit.v1` INPUT (body = t.body);",
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile_query_script(
        script,
        short_command_context(),
        construction_limits(),
        command_targets=Some(command_publication_bind("installation")),
      )
      is Err(UnsupportedEffect),
    )
  }
}

///|
test "short COMMAND private port does not reserve the same public Result spelling" {
  let program = short_command_program(
    "FROM messages |> RESULT aql_private_command |> EFFECT COMMAND mail.send ID id INPUT (body = body); EFFECT audit COMMAND FROM RESULT aql_private_command AS t TARGET t.mailbox CONTRACT `command:audit.v1` INPUT (body = t.body);",
  )
  assert_eq(@program.export_count(program), 1)
  let headers = @program.collect_effect_headers(program, 10, 10000).unwrap()
  assert_eq(@program.effect_header_count(headers), 2)
  let observed : Array[String] = []
  for index in 0..<@program.effect_header_count(headers) {
    let header = @program.effect_header_at(headers, index).unwrap()
    if @program.effect_header_id(header) == "audit" {
      observed.push(@program.effect_header_id(header))
      assert_true(
        @program.effect_header_source_result(header) !=
        Some("aql_private_command"),
      )
    }
  }
  assert_eq(observed, ["audit"])
}

///|
test "short COMMAND postlude empty identifier is rejected by the original lexer" {
  assert_true(
    @query.parse_query_script(
      "FROM messages |> EFFECT COMMAND mail.send ID id INPUT (body = body); EFFECT audit COMMAND FROM RESULT `` AS t TARGET t.id CONTRACT `command:audit.v1` INPUT (body = t.body);",
      syntax_limits(),
    )
    is Err({ issue: Lexical(EmptyIdentifier), .. }),
  )
}

///|
test "short COMMAND nested input ID uses one existing typed property projection" {
  let values = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"operation":{"type":"object","nullable":false,"additional_properties":false,"fields":{"id":{"type":"string","nullable":false}}},"body":{"type":"string","nullable":false}},"rows":[{"operation":{"id":"original-id"},"body":"original body"}]},"as":"messages"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..short_command_context(),
    inputs: [
      {
        relation: [{ value: "messages", quoted: false, }],
        name: "messages",
        source: GeneratedValues(values),
        visible_fields: ["operation", "body"],
        graph_bindings: [],
      },
    ],
  }
  let environment = short_command_checked_environment("installation")
  let publication = @source_publication.published_command_targets(
      environment,
      command_source_publication(environment),
    )
    .unwrap()
    .unwrap()
  let lowered = @frontend.lower(
    "FROM messages |> EFFECT COMMAND mail.send ID operation.id INPUT (body = body)",
    @frontend.Text,
    Some(context),
    command_targets=Some(publication),
  ).unwrap()
  let candidate = match
    @check.prepare_effect_computation_candidate(
      lowered.program.unwrap(),
      environment,
      None,
      [],
      check_limits(),
      10,
      10000,
    ) {
    Ok(value) => value
    Err(Computation(Source(SourceView(Program(Program(Pipeline(_, detail))))))) =>
      fail(@debug.to_string(detail.kind))
    Err(Computation(Source(issue))) => raise issue
    Err(Computation(issue)) => raise issue
    Err(_) =>
      fail("original nested ID must reach the existing Command input checker")
  }
  let inputs = @stage_results.bind_effect_command_inputs(
    short_command_checked_targets(candidate),
    { max_work: 10000, max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  ).unwrap()
  let input = @stage_results.effect_command_input_at(inputs, 0).unwrap()
  let key = @stage_results.effect_command_input_key(input).unwrap()
  assert_true(!@schema.field_contract(key).nullable)
  assert_true(@schema.field_contract(key).shape is @contract.Text(_))
  let derives = store_capture_steps(lowered.program.unwrap()).filter(step => {
    @wire.lookup(@wire.open_object(step).unwrap(), "derive") is Some(_)
  })
  assert_eq(derives.length(), 1)
  assert_eq(
    @wire.object_length(store_capture_field(derives[0], "derive")),
    Some(1),
  )
}
