///|
fn frontend_table_write_fixture() -> @query.TableWriteBinding {
  {
    name: [
      { value: "analytics", quoted: false, },
      { value: "report", quoted: false, },
    ],
    target_ref: "connector://local/report",
    mapping_ref: "mapping:local.report.v1",
    mapping_cid: "sha256:" + "a".repeat(64),
    capability_cid: "sha256:" + "b".repeat(64),
    installation_binding_cid: "sha256:" + "c".repeat(64),
    action: @query.Create,
  }
}

///|
test "Table SQL and Text use the same explicitly published write binding" {
  let binding = frontend_table_write_fixture()
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let sql = lower(
    "CREATE TABLE analytics.report AS SELECT 1 AS id",
    Sql,
    Some(context),
    table_writes=[binding],
  ).unwrap()
  let pipe = lower(
    "SELECT 1 AS id |> CREATE TABLE analytics.report",
    Text,
    Some(context),
    table_writes=[binding],
  ).unwrap()
  assert_eq(sql.document, pipe.document)
  assert_eq(@program.export_count(sql.program.unwrap()), 0)
  assert_true(
    lower(
      "CREATE TABLE analytics.report AS SELECT 1 AS id",
      Sql,
      Some(test_context()),
    )
    is Err(QueryLowering(TableWriteBinding(UnknownTable))),
  )
}

///|
test "Table frontend keeps operation intent separate from selected action" {
  let binding = frontend_table_write_fixture()
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let create = lower(
    "CREATE TABLE analytics.report AS SELECT 1 AS id",
    Sql,
    Some(context),
    table_writes=[binding],
  ).unwrap()
  let replace = lower(
    "CREATE OR REPLACE TABLE analytics.report AS SELECT 1 AS id",
    Sql,
    Some(context),
    table_writes=[binding],
  ).unwrap()
  assert_true(create.document != replace.document)
  assert_true(replace.document.contains("\"action\":\"create\""))
  let fixed = {
    ..binding,
    action: @query.Replace(
      "12345678-1234-1234-1234-123456789abc",
      "sha256:" + "d".repeat(64),
    ),
  }
  assert_true(
    lower(
      "CREATE TABLE analytics.report AS SELECT 1 AS id",
      Sql,
      Some(context),
      table_writes=[fixed],
    )
    is Err(QueryLowering(TableWriteBinding(ActionMismatch))),
  )
}
