///|
/// Independent parameterized compiler vectors over an existing real managed
/// producer. Returns SQL and expected source occurrences, never completion.
#export_name("managedTakeCompileFixture")
pub fn managed_take_compile_fixture(
  source : OwnedFixedFixture,
  output : @execution.ManagedCompletedOutput[Int],
  count : Int64,
  offset : Int64,
  table : String,
  ordinal : String,
  occurrence_alias : String,
  sql_bytes : Int,
  rename_ordinal : Bool,
) -> Array[String] raise {
  let steps = "[{\"take\":{\"count\":" +
    count.to_string() +
    ",\"offset\":" +
    offset.to_string() +
    (if rename_ordinal {
      "}},{\"select\":[{\"rowid\":\"amount\"}]}]"
    } else {
      "}},{\"select\":[\"amount\"]}]"
    })
  managed_take_compile_steps(
    source, output, steps, table, ordinal, occurrence_alias, sql_bytes,
  )
}

///|
#export_name("managedTakeChainCompileFixture")
pub fn managed_take_chain_compile_fixture(
  source : OwnedFixedFixture,
  output : @execution.ManagedCompletedOutput[Int],
  steps : String,
) -> Array[String] raise {
  managed_take_compile_steps(
    source, output, steps, "take_source", "rowid", "occurrence", 10000,
  )
}

///|
fn managed_take_compile_steps(
  source : OwnedFixedFixture,
  output : @execution.ManagedCompletedOutput[Int],
  steps : String,
  table : String,
  ordinal : String,
  occurrence_alias : String,
  sql_bytes : Int,
) -> Array[String] raise {
  let producer = @duckdb.fixed_query_owner(
    @duckdb.fixed_compute_query(source.compute),
  )
  let owner = issued_fixture_consumer(
    producer,
    steps~,
    target=@duckdb.fixed_query_target(
      @duckdb.fixed_compute_query(source.compute),
    ),
  )
  let input = @execution.prepare_managed_producer_read(
    owner, 0, producer, output, 100, 10000,
  ).unwrap()
  let query = @duckdb.prepare_managed_take_query(
    input,
    "main",
    table,
    ordinal,
    occurrence_alias,
    {
      max_entries: 1000,
      max_sql_bytes: sql_bytes,
      expressions: {
        max_nodes: 100,
        max_work: 1000,
        max_depth: 100,
        max_literal_nodes: 100,
        max_literal_text_bytes: 1000,
      },
    },
  ).unwrap()
  assert_true(@duckdb.managed_take_query_matches(query, input))
  let another = @execution.prepare_managed_producer_read(
    owner, 0, producer, output, 100, 10000,
  ).unwrap()
  assert_false(@duckdb.managed_take_query_matches(query, another))
  let selected = @duckdb.prepare_managed_take_selection(query, 100, 1000).unwrap()
  let result = [@duckdb.managed_take_query_sql(query)]
  for row in 0..<100 {
    match @execution.managed_view_selection_row(selected, row) {
      Some(occurrence) => result.push(occurrence.to_string())
      None => break
    }
  }
  if result.length() > 1 {
    assert_true(
      @duckdb.prepare_managed_take_selection(query, 0, 1000) is Err(Limit),
    )
    assert_true(
      @duckdb.prepare_managed_take_selection(query, 100, 0) is Err(Limit),
    )
  }
  result
}
