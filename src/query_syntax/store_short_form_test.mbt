///|
test "public STORE forms parse as authored terminal declarations" {
  for
    text in [
      "FROM local.orders |> EFFECT STORE local.archive;", "FROM transfers |> EFFECT STORE local.files SET (path = name, content = content);",
      "FROM transfers |> EFFECT upload STORE gcs.objects SET (name = name, content = content, overwrite = TRUE);",
    ] {
    let result = parse_query_script(text, query_limits())
    match result {
      Ok(_) => ()
      Err(issue) => {
        debug_inspect(issue, content="adopted STORE source must parse")
        fail("STORE source was refused before published-contract resolution")
      }
    }
  }
}

///|
test "original explicit typed COMMAND remains a parser control" {
  assert_true(
    parse_query_script(
      "FROM transfers |> RESULT files; EFFECT upload COMMAND FROM RESULT files AS t TARGET t.destination CONTRACT `command:files.upload.v1` INPUT (name = t.name, content = t.content);",
      query_limits(),
    )
    is Ok(_),
  )
}

///|
test "STORE keeps its authored target expressions and private terminal role" {
  let source = "FROM transfers |> RESULT before_write |> EFFECT upload STORE `gcs`.objects SET (name = original_name, content = captured.content, overwrite = FALSE);"
  let query = parse_query(source, query_limits(), source_path="upload.aql").unwrap()
  let clause = terminal_store_effect(query).unwrap()
  assert_eq(clause.name.map(part => part.value), Some("upload"))
  assert_eq(clause.target, [
    { value: "gcs", quoted: true, },
    { value: "objects", quoted: false, },
  ])
  assert_eq(clause.set.map(entry => entry.0.value), [
    "name", "content", "overwrite",
  ])
  assert_eq(clause.start, 41)
  assert_eq(clause.end, source.length() - 1)
  assert_true(terminal_effect(query) is None)
  assert_true(terminal_table_effect(query) is None)
  assert_eq(terminal_command_effect_count(query), 0)
  assert_eq(operation_count(query), 1)
  assert_true(operation_at(query, 0) is Some(RetainResult(_)))
  let original = clause.set[0].1
  assert_true(
    expression_node(original, expression_root(original)).unwrap().kind
    is Reference(_),
  )
  let origin = expression_origin(original, expression_root(original)).unwrap()
  assert_eq(@origin.span(origin).source_path, "upload.aql")
  clause.target.clear()
  clause.set.clear()
  let kept = terminal_store_effect(query).unwrap()
  assert_eq(kept.target.length(), 2)
  assert_eq(kept.set.length(), 3)
}

///|
test "STORE operation and Effect names keep qualified keyword roles" {
  for
    (text, name, qualifier) in [
      ("EFFECT STORE STORE.objects", None, "STORE"),
      ("EFFECT STORE UPDATE.objects", None, "UPDATE"),
      ("EFFECT STORE CREATE.objects", None, "CREATE"),
      ("EFFECT STORE STORE local.files", Some("STORE"), "local"),
      ("EFFECT UPDATE STORE local.files", Some("UPDATE"), "local"),
      ("EFFECT `SELECT` STORE local.files", Some("SELECT"), "local"),
    ] {
    let query = parse_query("FROM transfers |> " + text, query_limits()).unwrap()
    let clause = terminal_store_effect(query).unwrap()
    assert_eq(clause.name.map(part => part.value), name)
    assert_eq(clause.target[0].value, qualifier)
  }
  // STORE can still be an explicit name of the existing UPDATE operation.
  let update = parse_query(
    "FROM transfers |> EFFECT STORE UPDATE local.rows ID id SET (value = value)",
    query_limits(),
  ).unwrap()
  assert_eq(
    terminal_effect(update).unwrap().name.map(part => part.value),
    Some("STORE"),
  )
  assert_true(terminal_store_effect(update) is None)
}

///|
test "STORE never enters Pure Compute continuations or conflicting postludes" {
  for
    text in [
      "FROM transfers |> EFFECT STORE local.files |> SELECT name", "FROM transfers |> EFFECT STORE local.files; EFFECT again COMMAND FROM RESULT r AS t TARGET t.ref CONTRACT c INPUT ();",
      "WITH t AS (FROM transfers |> EFFECT STORE local.files) FROM t", "CREATE TABLE local.rows AS (FROM transfers |> EFFECT STORE local.files)",
      "FROM transfers |> UNION ALL (FROM other |> EFFECT STORE local.files)",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "STORE invalid target and malformed assignments are source refusals" {
  for
    suffix in [
      "", "STORE", "named STORE", "STORE files", "STORE 'local.files'", "STORE @destination",
      "STORE (local.files)", "STORE local.files()", "STORE local.files + 1", "STORE local.files SET ()",
      "STORE local.files SET (content =)", "STORE local.files SET (content = c,)",
      "STORE local.files SET (content = c, content = c)", "STORE local.files SET (content = c, `content` = c)",
      "SELECT STORE local.files", "STORE local.files FORMAT 'json'",
    ] {
    assert_true(
      parse_query("FROM transfers |> EFFECT " + suffix, query_limits())
      is Err(_),
      msg=suffix,
    )
  }
}

///|
test "STORE consumes the existing syntax and expression work budgets" {
  let source = "FROM transfers |> EFFECT STORE local.files SET (path = name, content = content)"
  let limits = query_limits()
  let original = parse_query(source, limits).unwrap()
  let work = query_work(original)
  assert_true(parse_query(source, { ..limits, max_work: work, }) is Ok(_))
  assert_true(parse_query(source, { ..limits, max_work: work - 1, }) is Err(_))
  assert_true(parse_query(source, { ..limits, max_syntax_nodes: 0, }) is Err(_))
  assert_true(
    parse_query(source, {
      ..limits,
      expression: { ..limits.expression, max_nodes: 0, },
    })
    is Err(_),
  )
}
