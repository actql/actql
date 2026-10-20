///|
fn local_projection_normalized_output(
  owner : PreparedClientProgram,
  field : String,
) -> Unit raise {
  match issue_prepared_client_local_normalization(owner) {
    Ok(_) => ()
    Err(Inventory(ProfileNotInstalled)) =>
      fail("original Local inventory: ProfileNotInstalled")
    Err(Inventory(CompletionObserved)) =>
      fail("original Local inventory: CompletionObserved")
    Err(_) => fail("original Local normalization failed outside the inventory")
  }
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(@execution.completed_column_name(output, 0), Some(field))
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Number(value)) &&
    value == 3.0,
  )
}

///|
test "public Pipe DROP retains its original projection normalization" {
  local_projection_normalized_output(
    local_explicit_cast_original(
      text="SELECT ABS(-3) AS id, 2 AS other |> DROP other",
      format=@source_frontend.Text,
    ),
    "id",
  )
}

///|
test "public Pipe RENAME retains its original projection normalization" {
  local_projection_normalized_output(
    local_explicit_cast_original(
      text="SELECT ABS(-3) AS id |> RENAME id AS renamed",
      format=@source_frontend.Text,
    ),
    "renamed",
  )
}

///|
test "authored AQL DROP retains its original checked projection normalization" {
  let owner = local_group_original_document(
    (
      #|{"version":"actql/0.1","id":"local.projection-drop","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"number","nullable":false}},"rows":[{"id":-3,"other":2}]},"as":"input"},{"derive":{"value":"abs(id)"}},{"drop":["id","other"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
  local_projection_normalized_output(owner, "value")
}

///|
test "authored AQL RENAME retains its original checked projection normalization" {
  let owner = local_group_original_document(
    (
      #|{"version":"actql/0.1","id":"local.projection-rename","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3}]},"as":"input"},{"rename":{"id":"renamed"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["renamed"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
  local_projection_normalized_output(owner, "renamed")
}
