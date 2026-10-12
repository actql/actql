///|
test "LIST_FILES retains a static Source and exclusive decoded selector" {
  for
    text in [
      "SELECT f.name FROM LIST_FILES(docs.invoices, paths => ['a.pdf', 'b.pdf']) AS f",
      "FROM LIST_FILES(docs.invoices, paths => ['a.pdf', 'b.pdf']) AS f |> SELECT f.name",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_eq(relation(query), [
      { value: "docs", quoted: false, },
      { value: "invoices", quoted: false, },
    ])
    assert_eq(relation_alias(query), Some({ value: "f", quoted: false, }))
    guard file_list_selector(query) is Some(ExactPaths(expression)) else {
      fail("expected exact paths")
    }
    guard expression_node(expression, expression_root(expression)).unwrap().kind
      is ArrayConstructor(items, _) else {
      fail("expected array selector")
    }
    assert_eq(items.length(), 2)
    assert_eq(
      expression_node(expression, items[0]).unwrap().kind,
      StringLiteral("a.pdf"),
    )
    assert_eq(
      expression_node(expression, items[1]).unwrap().kind,
      StringLiteral("b.pdf"),
    )
  }
  assert_true(
    file_list_selector(
      parse_query(
        "FROM LIST_FILES(docs.archive) |> SELECT name",
        query_limits(),
      ).unwrap(),
    )
    is Some(AllFiles),
  )
  guard file_list_selector(
      parse_query(
        "FROM LIST_FILES(docs.archive, glob => @pattern) |> SELECT name",
        query_limits(),
      ).unwrap(),
    )
    is Some(Glob(expression)) else {
    fail("parameter glob")
  }
  assert_eq(
    expression_node(expression, expression_root(expression)).unwrap().kind,
    ParameterReference("pattern"),
  )
}

///|
test "LIST_FILES refuses dynamic Source names and mixed or unknown selectors" {
  for
    text in [
      "FROM LIST_FILES(@source) |> SELECT name", "FROM LIST_FILES(CONCAT('docs.', 'archive')) |> SELECT name",
      "FROM LIST_FILES('docs.archive') |> SELECT name",
    ] {
    guard parse_query(text, query_limits())
      is Err({ issue: Syntax("FileSourceNameMustBeStatic"), .. }) else {
      fail("dynamic source must not resolve to a Source")
    }
  }
  for
    text in [
      "FROM LIST_FILES(docs.archive, paths => [], glob => '*.pdf') |> SELECT name",
      "FROM LIST_FILES(docs.archive, glob => '*.pdf', paths => []) |> SELECT name",
      "FROM LIST_FILES(docs.archive, suffix => '.pdf') |> SELECT name", "FROM LIST_FILES(docs.archive, glob = '*.pdf') |> SELECT name",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_))
  }
}

///|
test "LIST_FILES rejects nonraw glob backslash before decoded values lose origin" {
  for
    text in [
      "FROM LIST_FILES(docs.archive, glob => 'a\\?.pdf') |> SELECT name", "FROM LIST_FILES(docs.archive, glob => r'a' '\\?.pdf') |> SELECT name",
      "FROM LIST_FILES(docs.archive, glob => '''a\\?.pdf''') |> SELECT name",
    ] {
    guard parse_query(text, query_limits(), source_path="file.input")
      is Err({ issue: Syntax("GlobEscapeAmbiguous"), span: Some(span), }) else {
      fail("glob source backslash must be refused")
    }
    assert_eq(span.source_path, "file.input")
  }
  for
    text in [
      "FROM LIST_FILES(docs.archive, glob => r'a\\?.pdf') |> SELECT name", "FROM LIST_FILES(docs.archive, glob => r'''a\\?.pdf''') |> SELECT name",
    ] {
    guard file_list_selector(parse_query(text, query_limits()).unwrap())
      is Some(Glob(expression)) else {
      fail("raw glob")
    }
    assert_eq(
      expression_node(expression, expression_root(expression)).unwrap().kind,
      StringLiteral("a\\?.pdf"),
    )
  }
}

///|
test "LIST_FILES keeps original nested/JOIN selectors and charges parser work" {
  let text = "WITH listed AS (FROM LIST_FILES(docs.archive, paths => []) |> SELECT name) SELECT f.name FROM listed AS f JOIN LIST_FILES(docs.invoices, glob => r'*.pdf') AS other ON f.name = other.name"
  let query = parse_query(text, query_limits()).unwrap()
  assert_true(file_list_selector(query) is None)
  assert_true(
    file_list_selector(query_binding_at(query, 0).unwrap().query) is Some(ExactPaths(_)),
  )
  assert_true(join_part_at(query, 0).unwrap().file_listing is Some(Glob(_)))
  let work = query_work(query)
  assert_true(parse_query(text, { ..query_limits(), max_work: work, }) is Ok(_))
  assert_true(
    parse_query(text, { ..query_limits(), max_work: work - 1, }) is Err(_),
  )
}
