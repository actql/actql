///|
fn selected_query_limits() -> QueryLimits {
  let lexical : LexicalLimits = {
    max_source_bytes: 10000,
    max_tokens: 1000,
    max_literal_bytes: 10000,
    max_work: 20000,
  }
  {
    lexical,
    expression: { lexical, max_nodes: 1000, max_depth: 100, max_work: 10000, },
    max_syntax_nodes: 100,
    max_cte_count: 20,
    max_work: 10000,
  }
}

///|
test "selected SQL and Pipe parse retain one original source document" {
  for
    (text, sql_only) in [
      ("-- original\nSELECT 'é' AS label, 1 AS id", true),
      ("((SELECT 1 AS id))", true),
      ("FROM rows |> SELECT id", false),
    ] {
    let documents : Array[@origin.Document] = []
    let limits = selected_query_limits()
    let script = parse_selected_query_script_owned(
        text,
        limits,
        sql_only,
        "original-query.sql",
        read_document=(text, max_bytes, path) => {
          let document = @origin.document(text, max_bytes, source_path=path)
          match document {
            Ok(value) => documents.push(value)
            Err(_) => ()
          }
          document
        },
      )
      .unwrap()
      .unwrap()
    assert_eq(documents.length(), 1)
    assert_true(physical_equal(script_document(script), documents[0]))
    let legacy = parse_query_script(
      text,
      limits,
      source_path="original-query.sql",
    ).unwrap()
    let actual = query_source(script_query(script))
    let expected = query_source(script_query(legacy))
    assert_eq(script_work(script), script_work(legacy))
    assert_eq(token_count(actual), token_count(expected))
    for i in 0..<token_count(actual) {
      assert_eq(token_at(actual, i), token_at(expected, i))
    }
    for resource in [Tokens, LiteralBytes, Work] {
      assert_eq(usage(actual, resource), usage(expected, resource))
    }
  }
}

///|
test "rejected query routes do not validate an unrelated body" {
  for
    (text, sql_only) in [
      ("PROGRAM '\\q'", false),
      ("FROM rows |> SELECT '\\q'", true),
      ("TIME_SERIES '\\q'", true),
      ("((FROM rows |> SELECT id))", true),
    ] {
    let reads = [0]
    assert_true(
      parse_selected_query_script_owned(
        text,
        selected_query_limits(),
        sql_only,
        "route.sql",
        read_document=(text, max_bytes, path) => {
          reads[0] += 1
          @origin.document(text, max_bytes, source_path=path)
        },
      )
      is Ok(None),
    )
    assert_eq(reads[0], 1)
  }
  // The legacy parenthesized SQL classifier owns the full token envelope.
  assert_true(
    parse_selected_query_script(
      "(FROM rows |> SELECT '\\q')",
      selected_query_limits(),
      true,
    )
    is Err({ issue: Lexical(_), .. }),
  )
}

///|
test "selected query retains exact lexical limits and original error spans" {
  let text = "SELECT 'é' AS label, 1 AS id"
  let limits = selected_query_limits()
  let original = tokenize(text, limits.lexical).unwrap()
  let exact = {
    ..limits,
    lexical: {
      max_source_bytes: @origin.input_bytes(original.document),
      max_tokens: usage(original, Tokens),
      max_literal_bytes: usage(original, LiteralBytes),
      max_work: usage(original, Work),
    },
  }
  assert_true(parse_selected_query_script(text, exact, true) is Ok(Some(_)))
  assert_true(
    parse_selected_query_script(
      text,
      {
        ..exact,
        lexical: { ..exact.lexical, max_work: exact.lexical.max_work - 1, },
      },
      true,
    )
    is Err({ issue: Limit(Work), .. }),
  )
  assert_true(
    parse_selected_query_script(
      text,
      {
        ..exact,
        lexical: {
          ..exact.lexical,
          max_source_bytes: exact.lexical.max_source_bytes - 1,
        },
      },
      true,
    )
    is Err({ issue: Source(@origin.InputLimit), .. }),
  )
  let bad = "-- é\nSELECT '\\q' AS bad"
  let legacy = parse_query_script(bad, limits, source_path="authored.sql")
  let selected = parse_selected_query_script(
    bad,
    limits,
    true,
    source_path="authored.sql",
  )
  match (legacy, selected) {
    (
      Err({ issue: Lexical(a), span: old_span, }),
      Err({ issue: Lexical(b), span: new_span, }),
    ) => {
      assert_eq(a, b)
      assert_eq(old_span, new_span)
      assert_eq(new_span.unwrap().source_path, "authored.sql")
    }
    _ => fail("selected parsing must retain the original lexical refusal")
  }
}
