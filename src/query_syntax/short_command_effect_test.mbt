///|
test "short COMMAND accepts the fixed-target operation syntax from the public contract" {
  for
    text in [
      "FROM replies |> EFFECT COMMAND gmail.send ID id INPUT (to = recipient, subject = subject, body = body);",
      "SELECT id, recipient, subject, body FROM replies |> EFFECT send_mail COMMAND gmail.send ID id INPUT (to = recipient, subject = subject, body = body);",
    ] {
    assert_true(parse_query(text, query_limits()) is Ok(_), msg=text)
  }
}

///|
test "short COMMAND accepts per-row targets and optional empty input" {
  for
    text in [
      "FROM requests AS r |> EFFECT COMMAND slack.reply TARGET r.channel ID r.id INPUT (thread_ts = r.thread, text = r.text);",
      "FROM requests |> EFFECT archive COMMAND slack.archive_channel TARGET channel ID id;",
      "FROM requests |> EFFECT archive COMMAND slack.archive_channel TARGET channel ID id INPUT ();",
    ] {
    assert_true(parse_query(text, query_limits()) is Ok(_), msg=text)
  }
}

///|
test "short COMMAND remains terminal and outside producer bodies" {
  for
    text in [
      "FROM replies |> EFFECT COMMAND gmail.send ID id |> SELECT id;", "WITH r AS (FROM replies |> EFFECT COMMAND gmail.send ID id) FROM r;",
      "FROM replies |> EFFECT COMMAND gmail.send ID id |> EFFECT STORE archive.objects;",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "short COMMAND rejects absent row identities and malformed input assignments" {
  for
    text in [
      "FROM replies |> EFFECT COMMAND gmail.send;", "FROM replies |> EFFECT COMMAND gmail.send INPUT (body = body);",
      "FROM replies |> EFFECT COMMAND gmail.send ID id INPUT (body = body, BODY = body);",
      "FROM replies |> EFFECT COMMAND gmail.send ID id INPUT (body = body,);", "FROM replies |> EFFECT COMMAND gmail.send TARGET ID id;",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "short COMMAND preserves authored names paths expressions and defensive views" {
  let query = parse_query(
    "FROM requests AS r |> EFFECT notify COMMAND slack.reply TARGET r.channel ID r.id INPUT (thread_ts = r.thread, text = r.text || '!');",
    query_limits(),
  ).unwrap()
  let clause = terminal_short_command_effect(query).unwrap()
  assert_eq(clause.name.unwrap().value, "notify")
  assert_eq(clause.operation.map(part => part.value), ["slack", "reply"])
  assert_eq(clause.id.map(part => part.value), ["r", "id"])
  let target = clause.target.unwrap()
  assert_true(
    expression_node(target, expression_root(target)).unwrap().kind
    is Reference([_, _]),
  )
  assert_eq(clause.input.map(entry => entry.0.value), ["thread_ts", "text"])
  clause.operation.clear()
  clause.id.clear()
  clause.input.clear()
  let original = terminal_short_command_effect(query).unwrap()
  assert_eq(original.operation.length(), 2)
  assert_eq(original.id.length(), 2)
  assert_eq(original.input.length(), 2)
}

///|
test "short COMMAND uses structural operation words without stealing explicit Effect names" {
  for name in ["COMMAND", "STORE", "UPDATE"] {
    let query = parse_query(
      "FROM requests |> EFFECT " +
      name +
      " COMMAND slack.archive_channel TARGET channel ID id;",
      query_limits(),
    ).unwrap()
    assert_eq(
      terminal_short_command_effect(query).unwrap().name.unwrap().value,
      name,
    )
    assert_true(terminal_store_effect(query) is None)
  }
  let query = parse_query(
    "FROM requests |> EFFECT COMMAND command.send ID id;",
    query_limits(),
  ).unwrap()
  assert_true(terminal_short_command_effect(query).unwrap().name is None)
  let store = parse_query(
    "FROM requests |> EFFECT COMMAND STORE archive.objects;",
    query_limits(),
  ).unwrap()
  assert_eq(
    terminal_store_effect(store).unwrap().name.unwrap().value,
    "COMMAND",
  )
  assert_true(terminal_short_command_effect(store) is None)
}

///|
test "short COMMAND preserves its occurrence across a retained Model continuation" {
  let text = "FROM replies |> INFER score ITEM KEY (id) INPUT (n = body) KEEP (id, body) AS assessment |> RESULT assessed |> WHERE id IS NOT NULL |> EFFECT COMMAND gmail.send ID id INPUT (body = body)"
  let query = parse_query(text, query_limits()).unwrap()
  let original = terminal_short_command_effect(query).unwrap()
  let (prefix, tail) = effect_result_continuation(query, {
    value: "captured",
    quoted: false,
  }).unwrap()
  assert_true(terminal_short_command_effect(prefix) is None)
  assert_eq(terminal_short_command_effect(tail).unwrap().start, original.start)
  assert_eq(terminal_short_command_effect(tail).unwrap().end, original.end)
  assert_eq(original.end, text.length())
}

///|
test "short COMMAND and explicit long postludes keep separate declared occurrences" {
  let text = "FROM replies |> RESULT prepared |> EFFECT notify COMMAND gmail.send ID id; EFFECT upload COMMAND FROM RESULT prepared AS r TARGET r.destination CONTRACT upload INPUT (body = r.body);"
  let query = parse_query(text, query_limits()).unwrap()
  assert_eq(
    terminal_short_command_effect(query).unwrap().name.unwrap().value,
    "notify",
  )
  assert_eq(terminal_command_effect_count(query), 1)
  assert_eq(terminal_command_effect_at(query, 0).unwrap().name.value, "upload")
  assert_true(
    parse_query(
      text.replace(old="EFFECT upload", new="EFFECT NOTIFY"),
      query_limits(),
    )
    is Err(_),
  )
}

///|
test "short COMMAND preserves a completed set and the existing syntax work limit" {
  let text = "FROM left_rows |> UNION ALL (FROM right_rows) |> EFFECT COMMAND gmail.send ID id;"
  let query = parse_query(text, query_limits()).unwrap()
  assert_eq(query_binding_count(query), 1)
  let completed = query_binding_at(query, 0).unwrap()
  assert_eq(set_part_count(completed.query), 1)
  assert_true(terminal_short_command_effect(completed.query) is None)
  assert_eq(
    terminal_short_command_effect(query).unwrap().operation.map(part => {
      part.value
    }),
    ["gmail", "send"],
  )
  assert_true(
    parse_query(text, { ..query_limits(), max_syntax_nodes: 0, }) is Err(_),
  )
}
