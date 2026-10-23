///|
fn readme_original_cursor(
  cursor : @decode.Cursor,
  path : Array[String],
) -> @decode.Cursor {
  let mut selected = cursor
  for key in path {
    selected = @decode.lookup(@decode.open_object(selected).unwrap(), key).unwrap()
  }
  selected
}

///|
test "original README intent preserves prior canonical facts and stop-before-commit request" {
  let wire : String =
    #|{"input":{"format":"aql","text":"SELECT a.id AS id, a.description AS notes,\n       u.active_users, u.trend\nFROM salesforce.accounts AS a\nJOIN snowflake.usage_30d AS u ON a.id = u.account_id\n|> INFER `model-task:churn-risk.v1`\n     INPUT (notes, active_users, trend) AS risk\n|> WHERE risk.outcome = 'ok' AND risk.value.level = 'high'\n|> RESULT updates\n|> EFFECT UPDATE salesforce.Account\n     ID id SET (\n       Churn_Risk__c = risk.value.level,\n       Risk_Reason__c = risk.value.reason\n     );\n"},"kind":"aql","parameters":null,"stopBefore":"commit"}
  let input = client_standard_program_preparation_limits().checking.input
  let calls = Ref(0)
  let read = (bytes, limits) => {
    calls.val += 1
    @source.parse_json_bytes_preserving(bytes, limits)
  }
  let before = previous_submitted_input_parts(
    wire,
    input.source.max_input_bytes,
    input.source.max_nodes,
    input.source.max_depth,
    input.tree,
    read,
  ).unwrap()
  assert_eq(calls.val, 2)
  calls.val = 0
  let after = prepare_client_submitted_input_parts_with_reader(
    wire,
    input.source.max_input_bytes,
    input.source.max_nodes,
    input.source.max_depth,
    input.tree,
    read,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(before.0, after.0)
  // Independent canonical intent/version preimage, including the exact
  // authored JOIN, INFER, RESULT and Effect text with its original newlines.
  assert_eq(
    after.0.cid,
    "sha256:5e5ab070fdb87b98f088d6726dd8eef223e4db9bc556b33f23c576ce57d70aab",
  )
  assert_eq(after.0.wire, wire)
  assert_true(client_submitted_intent_requests_commit_stop(after.0))
  assert_false(client_submitted_intent_requests_read_only(after.0))
  assert_eq(@canonical.stringify_value(before.1, 65536, 8192, 64), wire)
  assert_eq(@canonical.stringify_value(after.1, 65536, 8192, 64), wire)
  for
    path in [
      [],
      ["kind"],
      ["input"],
      ["input", "format"],
      ["input", "text"],
      ["parameters"],
      ["stopBefore"],
    ] {
    let prior = readme_original_cursor(before.2, path)
    let current = readme_original_cursor(after.2, path)
    assert_eq(@decode.cursor_span(prior), @decode.cursor_span(current))
    assert_eq(@decode.cursor_key_span(prior), @decode.cursor_key_span(current))
    assert_eq(@decode.cursor_path(prior), @decode.cursor_path(current))
  }
  assert_eq(
    @decode.text(readme_original_cursor(after.2, ["input", "format"])),
    Ok("aql"),
  )
  assert_eq(
    @decode.text(readme_original_cursor(after.2, ["input", "text"])),
    @decode.text(readme_original_cursor(before.2, ["input", "text"])),
  )
  assert_true(@decode.is_null(readme_original_cursor(after.2, ["parameters"])))
}
