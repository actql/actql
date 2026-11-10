///|
fn waiting_preview_fixture_display(
  state : String,
  preview : String,
  maximum? : Int = 65536,
) -> String? {
  try {
    let source = @source.parse_json_bytes_preserving(@utf8.encode(preview), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }).unwrap_or_else(() => stop("LocalEffectReviewDisplayUnavailable"))
    let root = @canonical.from_source(source, 8192, 64, 65536, data_keys=true) catch {
      _ => stop("LocalEffectReviewDisplayUnavailable")
    }
    local_waiting_preview_display(state, root, maximum~)
  } catch {
    ClientStop(_) => None
  }
}

///|
let waiting_preview_state : String =
  #|{"version":"actql-run-state/0.1","run_id":"paused-run","status":"waiting_checkpoint","revision":3,"updated_at":"2026-10-17T00:00:00.000Z","checkpoint":{"checkpoint_id":"original-checkpoint","checkpoint_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","kind":"effect_set"},"next_action":{"kind":"resolve_checkpoint","checkpoint_id":"original-checkpoint"},"result_available":false,"result_availability":{}}

///|
// A presentation-only fixture; the Host admits the real Preview before this
// renderer. Sentinels must stay private even when supplied beside visible DATA.
let waiting_preview_data : String =
  #|{"effects":[{"effect_id":"original-effect","effect_kind":"update","target":"Salesforce Opportunity","count":1,"preview_strength":"full_diff","changes":[{"target_row_identity":"Acme\n\u001b[31m","before":{"state":"present","value":{"StageName":"Proposal","Precise":9007199254740992}},"after":{"state":"present","value":{"StageName":"Negotiation","Precise":9007199254740994}},"target_guard":{"secret":"guard-private"}}],"required_permissions":["permission-private"]}],"private_continuation":"continuation-private","authoring_context":"authoring-private"}

///|
test "waiting human Preview retains exact stored changes and numeric precision" {
  let human = waiting_preview_fixture_display(
    waiting_preview_state, waiting_preview_data,
  ).unwrap()
  assert_true(
    human.has_prefix(local_run_state_display(waiting_preview_state).unwrap()),
  )
  assert_true(
    human.contains("Effect: \"update\"  Target: \"Salesforce Opportunity\""),
  )
  assert_true(human.contains("Items: 1"))
  assert_true(human.contains("Preview strength: \"full_diff\""))
  assert_true(human.contains("\"StageName\":\"Proposal\""))
  assert_true(human.contains("\"StageName\":\"Negotiation\""))
  assert_true(human.contains("9007199254740992"))
  assert_true(human.contains("9007199254740994"))
  assert_true(human.contains("Acme\\n\\u001b[31m"))
  assert_false(human.contains("\u{001b}"))
  for
    secret in [
      "guard-private", "permission-private", "continuation-private", "authoring-private",
    ] {
    assert_false(human.contains(secret))
  }
  assert_true(human.contains("read-only; not approval"))
}

///|
test "waiting human Preview preserves unavailable and absent rather than inventing diff" {
  let targeted = waiting_preview_data
    .replace_all(old="full_diff", new="targeted")
    .replace_all(
      old="{\"state\":\"present\",\"value\":{\"StageName\":\"Proposal\",\"Precise\":9007199254740992}}",
      new="{\"state\":\"unavailable\"}",
    )
    .replace_all(
      old="{\"state\":\"present\",\"value\":{\"StageName\":\"Negotiation\",\"Precise\":9007199254740994}}",
      new="{\"state\":\"absent\"}",
    )
  let human = waiting_preview_fixture_display(waiting_preview_state, targeted).unwrap()
  assert_true(human.contains("Preview strength: \"targeted\""))
  assert_true(human.contains("Before: {\"state\":\"unavailable\"}"))
  assert_true(human.contains("After: {\"state\":\"absent\"}"))
  assert_false(human.contains("Proposal"))
}

///|
test "waiting human Preview enforces exact text bound and no nonwaiting fallback" {
  let human = waiting_preview_fixture_display(
    waiting_preview_state, waiting_preview_data,
  ).unwrap()
  let bytes = @utf8.encode(human).length()
  assert_eq(
    waiting_preview_fixture_display(
      waiting_preview_state,
      waiting_preview_data,
      maximum=bytes,
    ),
    Some(human),
  )
  assert_eq(
    waiting_preview_fixture_display(
      waiting_preview_state,
      waiting_preview_data,
      maximum=bytes - 1,
    ),
    None,
  )
  for
    invalid in [
      "{",
      "{}",
      run_display_minimal,
      waiting_preview_state.replace_all(old="effect_set", new="preparation"),
    ] {
    assert_eq(
      waiting_preview_fixture_display(invalid, waiting_preview_data),
      None,
    )
  }
  for invalid in ["{", "{}", "{\"effects\":[{}]}"] {
    assert_eq(
      waiting_preview_fixture_display(waiting_preview_state, invalid),
      None,
    )
  }
}

///|
test "waiting human Preview keeps distinct composed and decomposed DATA keys" {
  let original = waiting_preview_data.replace_all(
    old="\"StageName\":\"Proposal\"",
    new="\"StageName\":\"Proposal\",\"é\":1,\"é\":2",
  )
  let human = waiting_preview_fixture_display(waiting_preview_state, original).unwrap()
  assert_true(human.contains("\"é\":1"))
  assert_true(human.contains("\"é\":2"))
}
