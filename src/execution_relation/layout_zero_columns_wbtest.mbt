///|
// language.md#select forbids removing all fields of a nonempty input. A layout
// experiment cannot bypass this check just to obtain a zero-column relation.
test "all-column drop is rejected before any layout backend is selected" {
  let rows = Array::makei(1000, i => {
    "{\"id\":" + (1000 - i).to_string() + ",\"k\":0}"
  })
  let raw = "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows.join(",") +
    "]},\"as\":\"seed\"},{\"drop\":[\"id\",\"k\"]},{\"sort\":[]},{\"take\":10}]"
  let tree = @decode.admit(
    @source.parse_json(
      raw,
      { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      source_path="layout-values.json",
    ).unwrap(),
    {
      max_nodes: 100000,
      max_depth: 100,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
  ).unwrap()
  let result = @pipeline.check(tree, [], None, None, {
    max_steps: 100,
    max_work: 10000000,
    max_text_bytes: 1000000,
    max_nodes: 100000,
    max_tokens: 100000,
    max_depth: 100,
  })
  guard result is Err(issue) else { fail("all-column drop must not execute") }
  assert_true(issue.kind is Operation(@relation.EmptyBody))
  debug_inspect(issue.path, content="[Index(1), Key(\"drop\")]")
}
