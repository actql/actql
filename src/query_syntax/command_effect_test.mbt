///|
test "COMMAND postlude retains its Result scope and original expression origins" {
  let script = parse_query_script(
    "FROM transfers |> RESULT files; EFFECT upload COMMAND FROM RESULT files AS t TARGET t.destination CONTRACT `command:files.upload.v1` INPUT (name = t.name, content = t.content);",
    query_limits(),
  ).unwrap()
  assert_eq(command_effect_count(script), 1)
  let clause = command_effect_at(script, 0).unwrap()
  assert_eq(clause.name.value, "upload")
  assert_eq(clause.result_alias.value, "t")
  assert_eq(clause.contract.value, "command:files.upload.v1")
  assert_true(
    expression_node(clause.target, expression_root(clause.target)).unwrap().kind
    is Reference([_, _]),
  )
  assert_eq(clause.input.map(entry => entry.0.value), ["name", "content"])
  clause.input.clear()
  assert_eq(command_effect_at(script, 0).unwrap().input.length(), 2)
}

///|
test "COMMAND postlude follows WITH SERIALIZE and an ordinary destination JOIN" {
  let script = parse_query_script(
    (
      #|WITH destinations AS (FROM files.transfers |> WHERE name IS NOT NULL |> SELECT destination, name),
      #|attachment AS (FROM destinations |> SELECT name |> ASSERT UNIQUE BY (name)
      #||> SERIALIZE FORMAT CSV ORDER BY name
      #|OPTIONS (name = 'approved.csv', header = TRUE, null_marker = r'\N', max_rows = 1, max_bytes = 32))
      #|SELECT d.destination AS destination, a.name AS name, a.content AS content
      #|FROM attachment AS a JOIN destinations AS d ON a.name = d.name MAX_OUTPUT_ROWS 1 |> RESULT r;
      #|EFFECT upload COMMAND FROM RESULT r AS t TARGET t.destination
      #|CONTRACT `command:files.upload.v1` INPUT (name = t.name, content = t.content);
    ),
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(script_query(script)), 2)
  assert_eq(command_effect_count(script), 1)
}

///|
test "COMMAND postlude refuses duplicate names malformed boundaries and mixed terminal writes" {
  let prefix = "FROM transfers |> RESULT files; "
  let valid = "EFFECT upload COMMAND FROM RESULT files AS t TARGET t.destination CONTRACT c INPUT (name = t.name);"
  for
    text in [
      "FROM transfers;;",
      "FROM transfers |> RESULT files " + valid,
      prefix + valid + valid,
      prefix +
      "EFFECT upload COMMAND FROM RESULT files TARGET destination CONTRACT c INPUT ();",
      prefix +
      "EFFECT upload COMMAND FROM RESULT files AS t TARGET t.destination CONTRACT c INPUT (name = t.name, NAME = t.name);",
      prefix +
      "EFFECT upload COMMAND FROM RESULT files AS t TARGET t.destination CONTRACT c INPUT (name = t.name,);",
      prefix +
      "EFFECT upload COMMAND FROM RESULT files AS t TARGET t.destination CONTRACT c INPUT ()",
      "FROM transfers |> EFFECT save CREATE TABLE report; " + valid,
    ] {
    assert_true(parse_query_script(text, query_limits()) is Err(_), msg=text)
  }
}
