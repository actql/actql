///|
test "parsed published frontend retains original Context Catalog and foreign Environment refusal" {
  let environment = prepared_publication_source_environment()
  let reads = Ref(0)
  let prepared = prepare_published_query_environment_with_readers(
    environment,
    prepared_publication_source_wire(environment),
    source_publication_cursor,
    (original, limits, contents) => {
      reads.val += 1
      publication_read_catalog(original, limits, contents)
    },
  ).unwrap()
  let original = prepared_published_query_catalog(prepared, environment).unwrap()
  for
    (text, format) in [
      ("SELECT id FROM records", @source_frontend.Sql),
      ("FROM records |> SELECT id |> RESULT saved", @source_frontend.Text),
    ] {
    let parsed = @source_frontend.parse_query(
      text,
      format,
      source_path="same-published.aql",
    ).unwrap()
    let (lowered, catalog, _) = lower_prepared_published_parsed_query(
      prepared,
      environment,
      parsed,
      None,
      public_primary=true,
    ).unwrap()
    assert_true(lowered.program is Some(_))
    assert_true(physical_equal(catalog, original))
    assert_true(
      lower_prepared_published_parsed_query(
        prepared,
        prepared_publication_source_environment(),
        parsed,
        None,
      )
      is Err(ForeignEnvironment),
    )
  }
  assert_eq(reads.val, 1)
}
