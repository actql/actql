///|
// Transport-only fixture: real completed values use the product import adapter.
// The literal SELECT observes stored parameters; it is not a Compute strategy
// or evidence that the provisional transport result satisfies consumer limits.
test "completed scalar import transport fixtures" {
  for
    (name, contract, literal) in [
      ("text", "{\"type\":\"string\",\"nullable\":true}", "\"日本語\""),
      ("boolean", "{\"type\":\"boolean\",\"nullable\":true}", "false"),
      ("integer", "{\"type\":\"number\",\"nullable\":true}", "9007199254740992"),
      ("number", "{\"type\":\"number\",\"nullable\":true}", "-1.5"),
      (
        "decimal", "{\"type\":\"decimal\",\"precision\":38,\"scale\":2,\"nullable\":true}",
        "\"999999999999999999999999999999999999.99\"",
      ),
      ("date", "{\"type\":\"date\",\"nullable\":true}", "\"2000-02-29\""),
      (
        "timestamp", "{\"type\":\"timestamp\",\"nullable\":true}", "\"1969-12-31T23:59:59.999Z\"",
      ),
    ] {
    let input = duckdb_fixed_values(
      "[{\"values\":{\"schema\":{\"x\":" +
      contract +
      "},\"rows\":[{\"x\":" +
      literal +
      "},{\"x\":null},{\"x\":" +
      literal +
      "}]},\"as\":\"seed\"}]",
    )
    let imported = @duckdb.prepare_fixed_import(input, "fixed", 1, 1000).unwrap()
    let writer = @encode.writer(10000, 1000, 10)
    @encode.begin_object(writer)
    @encode.key(writer, "name")
    @encode.string_value(writer, name)
    @encode.key(writer, "create")
    @encode.string_value(writer, @duckdb.fixed_import_create_sql(imported))
    @encode.key(writer, "insert")
    @encode.string_value(writer, @duckdb.fixed_import_insert_sql(imported))
    @encode.key(writer, "rows")
    @encode.begin_array(writer)
    for row in 0..<@execution.producer_read_row_count(input) {
      @duckdb.emit_physical_parameter(
        @duckdb.fixed_import_parameter(imported, row, 0).unwrap(),
        writer,
      )
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    println("ACTQL_SCALAR_IMPORT " + @encode.finish(writer))
  }
}
