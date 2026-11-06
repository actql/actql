///|
test "derived optional public fixtures retain reserved CURRENT alias diagnostics" {
  let cases = [
    (
      "SELECT r.x AS original,x AS current,y FROM (FROM (SELECT 1 AS x,20 AS y UNION ALL SELECT 2,10) base |> AS r |> SET x=x+10) ORDER BY original",
      28,
    ),
    (
      "SELECT chosen.x AS current,chosen.y FROM (FROM (SELECT 1 AS x,20 AS y UNION ALL SELECT 2,10) base |> AS r |> SET x=x+10) chosen ORDER BY current",
      19,
    ),
    (
      "SELECT id,r.amount AS original,amount AS current FROM (FROM records |> AS r |> SET amount=99) ORDER BY id",
      41,
    ),
  ]
  for (source, position) in cases {
    for format in [Format::Sql, Format::Text] {
      guard lower(
          source,
          format,
          Some(test_context()),
          source_path="optional-derived.sql",
          public_primary=true,
        )
        is Err(
          QuerySyntax(
            {
              issue: Syntax("Reserved identifier requires backticks"),
              span: Some(span),
            }
          )
        ) else {
        fail("the original ordinary CURRENT alias must remain refused")
      }
      assert_eq(span.source_path, "optional-derived.sql")
      assert_eq(span.start_byte, position)
      assert_eq(span.end_byte, position)
    }
  }
}

///|
test "derived optional public fixtures quote CURRENT without changing range binding" {
  let context = bind_query_context([], "fixture.environment").unwrap()
  for
    source in [
      "SELECT r.x AS original,x AS `current`,y FROM (FROM (SELECT 1 AS x,20 AS y UNION ALL SELECT 2,10) base |> AS r |> SET x=x+10) ORDER BY original",
      "SELECT chosen.x AS `current`,chosen.y FROM (FROM (SELECT 1 AS x,20 AS y UNION ALL SELECT 2,10) base |> AS r |> SET x=x+10) chosen ORDER BY current",
    ] {
    for format in [Format::Sql, Format::Text] {
      let lowered = match
        lower(source, format, Some(context), public_primary=true) {
        Ok(value) => value
        Err(QuerySyntax(_)) => fail(source + ": QuerySyntax")
        Err(QueryLowering(UnknownColumn)) => fail(source + ": UnknownColumn")
        Err(QueryLowering(UnsupportedCte)) => fail(source + ": UnsupportedCte")
        Err(QueryLowering(Expression(_))) => fail(source + ": Expression")
        Err(_) => fail(source + ": other frontend issue")
      }
      let program = lowered.program.unwrap()
      assert_eq(@program.exports(program).map(entry => entry.0), ["main"])
      assert_eq(@program.export_count(program), 1)
    }
  }
  for format in [Format::Sql, Format::Text] {
    assert_true(
      parse_query(
        "SELECT id,r.amount AS original,amount AS `current` FROM (FROM records |> AS r |> SET amount=99) ORDER BY id",
        format,
      )
      is Ok(_),
    )
  }
}
