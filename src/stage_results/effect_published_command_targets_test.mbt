///|
fn published_command_results(
  identifier? : String? = None,
  nullable? : Bool = false,
  input? : String = "{}",
) -> EffectResultBindings {
  let selector = "{\"published_command\":{\"target_ref\":\"connector://mailbox/current\"" +
    (match identifier {
      None => ""
      Some(name) => ",\"identifier_field\":\"" + name + "\""
    }) +
    "}}"
  let effects = "{\"send\":{\"command\":{\"from\":{\"result\":\"r\"},\"target\":" +
    selector +
    ",\"contract\":\"command:mail.send.v1\",\"input\":" +
    input +
    "}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    amount_nullable=nullable,
    reference_nullable=Some(false),
  )
  bind_effect_results(headers, checked, 100).unwrap()
}

///|
test "published Command static binding retains original domain and never invents a STORE Mapping" {
  let references = published_command_references("installation")
  let effects = published_command_results()
  let targets = bind_effect_command_targets(effects, references, 10000).unwrap()
  assert_eq(effect_command_target_count(targets), 2)
  for index in 0..<2 {
    let target = effect_command_target_at(targets, index).unwrap()
    let original = effect_command_target_published_binding(target).unwrap()
    assert_eq(
      @environment.published_command_binding_mode(original),
      @environment.Installation,
    )
    assert_true(effect_command_target_store_binding(target) is None)
    assert_true(
      physical_equal(
        @environment.published_command_binding_target(original),
        effect_command_target_contract(target),
      ),
    )
    assert_true(
      physical_equal(
        @environment.command_target_catalog(
          effect_command_target_contract(target),
        ),
        @environment.catalog_at(@environment.reference_contents(references), 0).unwrap(),
      ),
    )
    assert_true(
      physical_equal(
        effect_command_target_effect(target),
        effect_result_binding_at(effects, index).unwrap(),
      ),
    )
  }
  let work = effect_command_targets_work(targets)
  assert_true(bind_effect_command_targets(effects, references, work) is Ok(_))
  assert_true(
    bind_effect_command_targets(effects, references, work - 1) is Err(_),
  )
}

///|
test "published Command declared identifier retains the real typed source field" {
  let references = published_command_references("identifier-number")
  let effects = published_command_results(identifier=Some("amount"))
  let targets = bind_effect_command_targets(effects, references, 10000).unwrap()
  let target = effect_command_target_at(targets, 0).unwrap()
  let original = effect_command_target_published_binding(target).unwrap()
  assert_eq(
    @environment.published_command_binding_mode(original),
    @environment.Identifier,
  )
  let field = effect_result_field_binding_at(
    effect_command_target_effect(target),
    0,
  ).unwrap()
  assert_eq(effect_result_field_binding_role(field), EffectCommandIdentifier)
  assert_eq(
    @schema.field_reference_name(effect_result_field_binding_field(field)),
    "amount",
  )
  assert_true(
    @contract.type_equal(
      @environment.published_command_binding_identifier_type(original).unwrap(),
      @schema.field_contract(effect_result_field_binding_field(field)),
      10,
    ),
  )
  assert_true(effect_command_target_store_binding(target) is None)
}

///|
test "published Command rejects opposite modes and legacy missing declaration" {
  for
    (mode, identifier) in [
      ("installation", Some("amount")),
      ("identifier-number", None),
    ] {
    let issue = bind_effect_command_targets(
      published_command_results(identifier~),
      published_command_references(mode),
      10000,
    ).unwrap_err()
    assert_eq(
      effect_command_target_issue_kind(issue),
      PublishedCommandModeMismatch,
    )
  }
  let issue = bind_effect_command_targets(
    published_command_results(),
    published_command_references("legacy-field"),
    10000,
  ).unwrap_err()
  assert_eq(
    effect_command_target_issue_kind(issue),
    PublishedCommand(@environment.MissingBinding),
  )
}

///|
test "published Command identifier domain rejects nullable mismatched and absent fields" {
  for
    (mode, field, nullable) in [
      ("identifier-number", "amount", true),
      ("identifier", "amount", false),
      ("identifier-number", "ref", false),
    ] {
    let issue = bind_effect_command_targets(
      published_command_results(identifier=Some(field), nullable~),
      published_command_references(mode),
      10000,
    ).unwrap_err()
    assert_eq(
      effect_command_target_issue_kind(issue),
      PublishedCommandIdentifierMismatch,
    )
  }
  let effects = "{\"send\":{\"command\":{\"from\":{\"result\":\"r\"},\"target\":{\"published_command\":{\"target_ref\":\"connector://mailbox/current\",\"identifier_field\":\"missing\"}},\"contract\":\"command:mail.send.v1\",\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  assert_eq(
    effect_result_binding_issue_kind(
      bind_effect_results(headers, checked, 100).unwrap_err(),
    ),
    MissingField,
  )
}

///|
test "published Command domains share bounded admission accounts across all occurrences" {
  let effects = published_command_results(identifier=Some("amount"))
  let references = published_command_references("identifier-number")
  let targets = bind_effect_command_targets(effects, references, 10000).unwrap()
  let (nodes, text) = effect_command_targets_usage(targets)
  assert_true(nodes > 0 && text > 0)
  let limits : @contract.Limits = {
    max_nodes: nodes,
    max_depth: 10,
    max_text_bytes: text,
  }
  assert_true(
    bind_effect_command_targets(
      effects,
      references,
      10000,
      value_limits=Some(limits),
    )
    is Ok(_),
  )
  assert_true(
    bind_effect_command_targets(
      effects,
      references,
      10000,
      value_limits=Some({
        max_nodes: nodes - 1,
        max_depth: 10,
        max_text_bytes: text,
      }),
    )
    is Err(_),
  )
  assert_true(
    bind_effect_command_targets(
      effects,
      references,
      10000,
      value_limits=Some({
        max_nodes: nodes,
        max_depth: 10,
        max_text_bytes: text - 1,
      }),
    )
    is Err(_),
  )
  assert_eq(
    effect_command_target_issue_kind(
      bind_effect_command_targets(
        effects,
        references,
        10000,
        value_limits=Some({
          max_nodes: -1,
          max_depth: 10,
          max_text_bytes: text,
        }),
      ).unwrap_err(),
    ),
    InvalidLimits,
  )
}

///|
test "published Command selector alone cannot project or issue a nominal target" {
  let effects = published_command_results(
    input="{\"body\":{\"literal\":\"retained\"}}",
  )
  let targets = bind_effect_command_targets(
    effects,
    published_command_references("installation"),
    10000,
  ).unwrap()
  let inputs = bind_effect_command_inputs(
    targets,
    command_input_limits(work=2000, nodes=100, text=1000),
  ).unwrap()
  let binding = effect_command_input_at(inputs, 0).unwrap()
  let row = effect_plan_test_row("{\"amount\":1,\"ref\":null}")
  assert_eq(
    project_effect_command_row(binding, row, 2, 100, 1024, 64, 8).unwrap_err(),
    MissingTarget,
  )
}

///|
test "published Command identifier requires original guaranteed column presence" {
  let effects = "{\"send\":{\"command\":{\"from\":{\"result\":\"r\"},\"target\":{\"published_command\":{\"target_ref\":\"connector://mailbox/current\",\"identifier_field\":\"amount\"}},\"contract\":\"command:mail.send.v1\",\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    amount_presence=Some(@schema.Conditional),
  )
  let issue = bind_effect_results(headers, checked, 100).unwrap_err()
  assert_eq(effect_result_binding_issue_kind(issue), InvalidCommandIdentifier)
  assert_eq(effect_result_binding_issue_field(issue), Some("amount"))
}
