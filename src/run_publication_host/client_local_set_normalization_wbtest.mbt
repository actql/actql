///|
fn local_set_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let proof = match issue_prepared_client_local_normalization(owner) {
    Ok(proof) => proof
    Err(Inventory(issue)) => {
      let writer = @encode.writer(1000000, 100000, 100)
      @syntax.emit_program_source(owner.source, writer)
      fail(@debug.to_string(issue) + ": " + @encode.finish(writer))
    }
    Err(_) => fail("original set evidence unavailable")
  }
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    "sha256:0f0003ec6a1ec4520a7b9615b916d903dafc138e94145e5a57d45a1bf7937f33",
  )
  guard proof.audit is CompletionFree(inventory) else {
    fail("original completion-free set expected")
  }
  assert_true(@checked.local_completion_free_inventory_uses_set(inventory))
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, proof).unwrap(),
    ),
    "{\"entries\":[],\"journal_cid\":\"sha256:fa574394197dbcc891e0425a26dfb9b358352e5b21babe5f48ba260da6f8c4a6\",\"rule_catalog_cid\":\"sha256:0f0003ec6a1ec4520a7b9615b916d903dafc138e94145e5a57d45a1bf7937f33\",\"version\":\"actql-normalization-journal/0.1\"}",
  )
  proof
}

///|
test "public SQL and Pipe set queries retain their original checked operators" {
  for
    text in [
      "SELECT 1 AS n UNION ALL SELECT 2 AS n", "SELECT 1 AS n UNION DISTINCT SELECT 1 AS n",
      "SELECT 1 AS n INTERSECT DISTINCT SELECT 1 AS n", "SELECT 1 AS n EXCEPT DISTINCT SELECT 2 AS n",
    ] {
    let owner = local_explicit_cast_original(text~)
    ignore(local_set_normalization(owner))
  }
  for
    text in [
      "SELECT 1 AS n |> UNION ALL (SELECT 2 AS n)", "SELECT 1 AS n |> UNION DISTINCT (SELECT 1 AS n)",
      "SELECT 1 AS n |> INTERSECT DISTINCT (SELECT 1 AS n)", "SELECT 1 AS n |> EXCEPT DISTINCT (SELECT 2 AS n)",
    ] {
    let owner = local_explicit_cast_original(
      text~,
      format=@source_frontend.Text,
    )
    ignore(local_set_normalization(owner))
  }
}

///|
fn local_set_rows(kind : String) -> PreparedClientProgram raise {
  let body = if kind == "append" {
    "{\"with\":\"right\"}"
  } else {
    "{\"with\":\"right\",\"duplicates\":\"distinct\"}"
  }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"local.set\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"n\":1},{\"n\":1},{\"n\":2}]},\"as\":\"left\"},{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"n\":1},{\"n\":3}]},\"as\":\"right\"},{\"from\":\"left\",\"" +
    kind +
    "\":" +
    body +
    ",\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"n\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  local_group_original_document(document)
}

///|
test "original Append and Set execute complete rows with existing duplicate and order rules" {
  for kind in ["append", "except", "intersect"] {
    let owner = local_set_rows(kind)
    ignore(local_set_normalization(owner))
    let output = local_distinct_execute(owner)
    let expected = match kind {
      "append" => [1.0, 1.0, 2.0, 1.0, 3.0]
      "except" => [2.0]
      _ => [1.0]
    }
    assert_eq(@execution.completed_row_count(output), expected.length())
    for row, wanted in expected {
      assert_true(
        @execution.completed_cell(output, row, 0) is Some(Number(value)) &&
        value == wanted,
      )
    }
  }
}

///|
test "set evidence never admits an equal foreign preparation or predecessor journal" {
  let owner = local_set_rows("append")
  let proof = local_set_normalization(owner)
  let equal = local_set_rows("append")
  assert_true(
    prepared_client_local_normalization_evidence(equal, proof)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, local_distinct_expected_journal, local_distinct_catalog_cid,
    )
    is Err(ForeignCatalog),
  )
  let implicit = local_explicit_cast_original(
    text="SELECT CASE WHEN TRUE THEN 1 END AS n UNION ALL SELECT 2 AS n",
  )
  match issue_prepared_client_local_normalization(implicit) {
    Err(Inventory(CompletionObserved)) => ()
    Err(Inventory(issue)) => {
      let writer = @encode.writer(1000000, 100000, 100)
      @syntax.emit_program_source(implicit.source, writer)
      fail(
        "implicit completion: " +
        @debug.to_string(issue) +
        ": " +
        @encode.finish(writer),
      )
    }
    _ => fail("implicit completion must remain refused")
  }
}

///|
test "public set operands retain exact supplied bindings and refuse equal defaults" {
  let declarations = "{\"id\":{\"type\":\"int64\",\"nullable\":false,\"default\":\"9007199254740993\"}}"
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    let text = if format == @source_frontend.Sql {
      "SELECT @id AS n UNION ALL SELECT @id AS n"
    } else {
      "SELECT @id AS n |> UNION ALL (SELECT @id AS n)"
    }
    let supplied = local_supplied_parameter_preparation(
      format,
      declarations,
      Some("{\"id\":\"9007199254740993\"}"),
      text~,
    )
    ignore(local_set_normalization(supplied))
    let defaulted = local_supplied_parameter_preparation(
      format,
      declarations,
      None,
      text~,
    )
    assert_eq(
      local_parameter_values_identity(supplied),
      local_parameter_values_identity(defaulted),
    )
    assert_true(
      issue_prepared_client_local_normalization(defaulted)
      is Err(Inventory(ProfileNotInstalled)),
    )
    assert_true(defaulted.local_normalization is None)
  }
}

///|
test "Set followed by actual Sort completion retains its nonempty original journal" {
  let document =
    #|{"version":"actql/0.1","id":"local.set-sort","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false},"n":{"type":"number","nullable":false}},"rows":[{"n":1,"k":3},{"n":2,"k":1},{"n":1,"k":2}]},"as":"left"},{"values":{"schema":{"k":{"type":"number","nullable":false},"n":{"type":"number","nullable":false}},"rows":[]},"as":"right"},{"from":"left","except":{"with":"right","duplicates":"distinct"}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["n","k"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let owner = local_group_original_document(document)
  let proof = issue_prepared_client_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("original Set Sort completion expected")
  }
  assert_true(@checked.local_sort_normalization_inventory_uses_set(inventory))
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  let wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(owner, proof).unwrap(),
  )
  let empty_owner = local_set_rows("append")
  let empty = local_set_normalization(empty_owner)
  let empty_wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(empty_owner, empty).unwrap(),
  )
  let catalog = local_normalization_catalog_cid(proof.audit)
  assert_true(
    restore_prepared_client_local_normalization(owner, proof, wire, catalog)
    is Ok(_),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, empty_wire, catalog,
    )
    is Err(SubstitutedJournal),
  )
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_row_count(output), 3)
  for row, expected in [(1.0, 2.0), (1.0, 3.0), (2.0, 1.0)] {
    assert_eq(@execution.completed_column_count(output), 2)
    for column in 0..<@execution.completed_column_count(output) {
      let wanted = match @execution.completed_column_name(output, column) {
        Some("n") => expected.0
        Some("k") => expected.1
        _ => fail("unexpected original Set result column")
      }
      assert_true(
        @execution.completed_cell(output, row, column) is Some(Number(value)) &&
        value == wanted,
      )
    }
  }
}
