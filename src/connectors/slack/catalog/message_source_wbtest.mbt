///|
test "Slack messages declaration retains the exact id key without filter pushdown claims" {
  assert_eq(
    slack_message_facts_wire(),
    (
      #|{"relation_keys":{"candidate_keys":[["id"]]}}
    ),
  )
  let schema = slack_message_schema_wire(8192, 1000, 16).unwrap()
  let parsed = @source.parse_json_bytes(@utf8.encode(schema), {
    max_input_bytes: 8192,
    max_nodes: 1000,
    max_depth: 16,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 1000,
    max_depth: 16,
    max_string_bytes: 8192,
    max_total_string_bytes: 8192,
  }).unwrap()
  let root = @decode.open_object(cursor).unwrap()
  assert_true(@decode.lookup(root, "id") is Some(_))
}
