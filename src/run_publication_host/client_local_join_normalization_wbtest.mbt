///|
let local_join_catalog : String = "sha256:aa327c80f2a09b4a199a77da8751e04e994bbf42ff28581f6620a73a864f5b3c"

///|
let local_join_public_sql : String = "WITH left_rows AS (SELECT 1 AS id), right_rows AS (SELECT 1 AS id)\nSELECT l.id AS id FROM left_rows AS l\nJOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 4\n"

///|
fn local_join_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let proof = match issue_prepared_client_local_normalization(owner) {
    Ok(value) => value
    Err(Inventory(issue)) =>
      fail("original keyed Join: " + @debug.to_string(issue))
    Err(_) => fail("original keyed Join preparation unavailable")
  }
  assert_eq(local_normalization_catalog_cid(proof.audit), local_join_catalog)
  guard proof.audit is CompletionFree(inventory) else {
    fail("completion-free keyed Join expected")
  }
  assert_true(@checked.local_completion_free_inventory_uses_join(inventory))
  let expected =
    #|{"entries":[],"journal_cid":"sha256:bd40a31041d5f40c10174e1bf6cc7652a82b3c0741635ab8d8f465275c3a0cff","rule_catalog_cid":"sha256:aa327c80f2a09b4a199a77da8751e04e994bbf42ff28581f6620a73a864f5b3c","version":"actql-normalization-journal/0.1"}
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, proof).unwrap(),
    ),
    expected,
  )
  proof
}

///|
test "original public WITH JOIN and Pipe JOIN select only their nominal new capability" {
  assert_eq(@utf8.encode(local_join_public_sql).length(), 159)
  assert_eq(
    @sha.hex(@utf8.encode(local_join_public_sql)),
    "2c7686cc6ae7815f9c2018e652f309859a6276cbf24f43e367774cb926b95d5c",
  )
  let owner = local_explicit_cast_original(text=local_join_public_sql)
  ignore(local_join_normalization(owner))
  let pipe = local_explicit_cast_original(
    text="FROM (SELECT 1 AS id) AS l |> JOIN (SELECT 1 AS id) AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 |> SELECT l.id AS id",
    format=@source_frontend.Text,
  )
  ignore(local_join_normalization(pipe))
}

///|
fn local_join_rows(
  kind : String,
  full? : Bool = false,
  tail? : String = "",
  options? : String = "",
  maximum? : Int = 8,
) -> PreparedClientProgram raise {
  let schema = "{\"id\":{\"type\":\"int64\",\"nullable\":" +
    (if full { "false" } else { "true" }) +
    "}}"
  let left = if full {
    "[{\"id\":\"9007199254740993\"},{\"id\":\"5\"}]"
  } else {
    "[{\"id\":\"9007199254740993\"},{\"id\":\"5\"},{\"id\":null}]"
  }
  let right = if full {
    "[{\"id\":\"9007199254740993\"},{\"id\":\"6\"}]"
  } else {
    "[{\"id\":\"9007199254740993\"},{\"id\":\"9007199254740993\"},{\"id\":\"6\"},{\"id\":null}]"
  }
  let projection = if kind == "semi" || kind == "anti" {
    "{\"id\":\"left.id\"}"
  } else {
    "{\"id\":\"left.id\",\"matched\":\"right.id\"}"
  }
  let assertion = if full {
    ",{\"assert_rows\":{\"unique_by\":[\"id\"]}}"
  } else {
    ""
  }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"local.join\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    left +
    "},\"as\":\"left_input\"}" +
    assertion +
    ",{\"select\":[\"id\"],\"as\":\"left\"},{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    right +
    "},\"as\":\"right_input\"}" +
    assertion +
    ",{\"select\":[\"id\"],\"as\":\"right\"},{\"from\":\"left\",\"join\":{\"with\":\"right\",\"kind\":\"" +
    kind +
    "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"max_output_rows\":" +
    maximum.to_string() +
    options +
    ",\"select\":" +
    projection +
    "},\"as\":\"joined\"}" +
    tail +
    "],\"results\":{\"rows\":{\"from\":\"" +
    (if tail == "" { "joined" } else { "projected" }) +
    "\",\"fields\":" +
    (if kind == "semi" || kind == "anti" || tail != "" {
      "[\"id\"]"
    } else {
      "[\"id\",\"matched\"]"
    }) +
    "}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  local_group_original_document(document)
}

///|
fn local_join_expect_cell(
  output : @execution.CompletedOutput,
  row : Int,
  column : Int,
  expected : Int64?,
) -> Unit raise {
  match expected {
    Some(wanted) =>
      assert_true(
        @execution.completed_cell(output, row, column)
        is Some(Captured(Signed64(actual))) &&
        actual == wanted,
      )
    None =>
      assert_true(@execution.completed_cell(output, row, column) is Some(Null))
  }
}

///|
test "original keyed Join execution preserves exact int64 multiplicity NULL and left order" {
  for kind in ["inner", "left", "semi", "anti"] {
    let owner = local_join_rows(kind)
    ignore(local_join_normalization(owner))
    let output = local_distinct_execute(owner)
    let expected : Array[Int64?] = match kind {
      "inner" => [Some(9007199254740993L), Some(9007199254740993L)]
      "left" =>
        [Some(9007199254740993L), Some(9007199254740993L), Some(5L), None]
      "semi" => [Some(9007199254740993L)]
      _ => [Some(5L), None]
    }
    assert_eq(@execution.completed_column_name(output, 0), Some("id"))
    assert_eq(@execution.completed_row_count(output), expected.length())
    for row, value in expected {
      local_join_expect_cell(output, row, 0, value)
    }
    if kind == "inner" || kind == "left" {
      assert_eq(@execution.completed_column_name(output, 1), Some("matched"))
      for row in 0..<expected.length() {
        local_join_expect_cell(
          output,
          row,
          1,
          if row < 2 {
            Some(9007199254740993L)
          } else {
            None
          },
        )
      }
    }
  }
}

///|
test "Full Join retains actual unique assertions before existing unmatched row execution" {
  let owner = local_join_rows("full", full=true)
  ignore(local_join_normalization(owner))
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_row_count(output), 3)
  for
    row, pair in [
      (Some(9007199254740993L), Some(9007199254740993L)),
      (Some(5L), None),
      (None, Some(6L)),
    ] {
    local_join_expect_cell(output, row, 0, pair.0)
    local_join_expect_cell(output, row, 1, pair.1)
  }
}

///|
test "public Join keeps same typed Default or supplied operands and foreign refusal" {
  let declarations = "{\"cap\":{\"type\":\"int64\",\"nullable\":false,\"default\":\"4\"}}"
  let text = "WITH left_rows AS (SELECT @cap AS id), right_rows AS (SELECT @cap AS id) SELECT l.id AS id FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 4"
  let supplied = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    Some("{\"cap\":\"4\"}"),
    text~,
  )
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    None,
    text~,
  )
  let proof = local_join_normalization(defaulted)
  ignore(local_join_normalization(supplied))
  assert_eq(
    local_parameter_values_identity(supplied),
    local_parameter_values_identity(defaulted),
  )
  assert_true(
    @parameter.bound_value_at(local_default_bound_values(defaulted), 0).unwrap().origin
    is @parameter.Default,
  )
  assert_true(
    prepared_client_local_normalization_evidence(supplied, proof)
    is Err(ForeignPreparation),
  )
  let copy : ClientLocalNormalization = {
    preparation: proof.preparation,
    audit: proof.audit,
    evidence: proof.evidence,
  }
  assert_true(
    prepared_client_local_normalization_evidence(defaulted, copy)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      defaulted,
      proof,
      local_assertion_expected_journal,
      local_assertion_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
}

///|
test "Join retains real projection journal entries and implicit completion refusal" {
  let owner = local_join_rows(
    "inner",
    tail=",{\"drop\":[\"matched\"],\"as\":\"projected\"}",
  )
  let proof = issue_prepared_client_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("real projection journal required")
  }
  assert_true(@checked.local_sort_normalization_inventory_uses_join(inventory))
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  let wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(owner, proof).unwrap(),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, wire, local_join_catalog,
    )
    is Ok(_),
  )
  let empty_owner = local_join_rows("inner")
  let empty_proof = local_join_normalization(empty_owner)
  let empty = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(empty_owner, empty_proof).unwrap(),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, empty, local_join_catalog,
    )
    is Err(SubstitutedJournal),
  )
  let implicit = local_explicit_cast_original(
    text="WITH l AS (SELECT CASE WHEN TRUE THEN 1 END AS id), r AS (SELECT 1 AS id) SELECT l.id AS id FROM l JOIN r ON l.id = r.id MAX_OUTPUT_ROWS 4",
  )
  assert_true(
    issue_prepared_client_local_normalization(implicit)
    is Err(Inventory(CompletionObserved)),
  )
}

///|
test "normalization never discharges actual Join NULL cardinality or output guard failures" {
  for scenario in ["null", "cardinality", "guard"] {
    let owner = local_join_rows(
      "inner",
      options=match scenario {
        "null" => ",\"null_key\":\"fail\""
        "cardinality" => ",\"cardinality\":\"many_to_one\""
        _ => ""
      },
      maximum=if scenario == "guard" { 1 } else { 8 },
    )
    ignore(local_join_normalization(owner))
    let task = @strategy.graph_task_owner(owner.graph, 0).unwrap()
    let sequence = @lower.prepare_sequence(
      task,
      run_materials_limits().sequence,
    ).unwrap()
    let result = @execution.execute_generated_sequence(
      local_group_generated(sequence),
      [],
      string_try_number_execution_limits(),
    )
    match scenario {
      "null" => assert_true(result is Err(Rows(4, JoinNullKey(_, _, _))))
      "cardinality" =>
        assert_true(result is Err(Rows(4, JoinDuplicateKey(_, _, _))))
      _ => assert_true(result is Err(Rows(4, RowLimit)))
    }
  }
}
