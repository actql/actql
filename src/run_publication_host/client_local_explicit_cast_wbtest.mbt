///|
let local_explicit_cast_public_sql : String = "SELECT 4 AS id, '日本語' AS note, CAST(NULL AS STRING) AS missing"

///|
fn local_explicit_cast_original(
  text? : String = local_explicit_cast_public_sql,
  format? : @source_frontend.Format = @source_frontend.Sql,
) -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  let lowered = @source_frontend.lower(text, format, Some(context)).unwrap()
  prepare_parsed_effect_free_client_program(
    lowered.program.unwrap(),
    environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "public explicit CAST NULL query retains its original checked operation before normalization" {
  let original = local_explicit_cast_original()
  let checked = @strategy.graph_program(original.graph)
  let tags : Array[String] = []
  let mut explicit_null = false
  for unit in 0..<@checked.unit_count(checked) {
    let pipeline = @checked.unit_pipeline(checked, unit).unwrap()
    for step in 0..<@pipeline.step_count(pipeline) {
      match @pipeline.step_at(pipeline, step).unwrap().operation {
        @pipeline.Unary(operation) =>
          for binding in 0..<@relation.binding_count(operation) {
            let expression = @relation.binding_expression_at(operation, binding).unwrap()
            for node in 0..<@expression.node_count(expression) {
              match @expression.node_form(expression, node).unwrap() {
                Expression(tag, body) => {
                  tags.push(tag)
                  if tag == "literal" && @decode.is_null(body) {
                    explicit_null = true
                  }
                }
                ImplicitNull => tags.push("#implicit-null")
                _ => ()
              }
            }
          }
        _ => ()
      }
    }
  }
  assert_true(tags.contains("cast"))
  assert_true(tags.contains("literal"))
  assert_false(tags.contains("#implicit-null"))
  assert_true(explicit_null)
}

///|
test "public explicit CAST NULL original can issue Local normalization without rewriting the query" {
  let original = local_explicit_cast_original()
  assert_true(issue_prepared_client_local_normalization(original) is Ok(_))
}

///|
test "explicit CAST normalization retains the exact closed catalog and original owner" {
  let owner = local_explicit_cast_original()
  let issued = issue_prepared_client_local_normalization(owner).unwrap()
  let expected =
    #|{"entries":[],"journal_cid":"sha256:de7192df9afefaf5006eb57bb62783ae5a7cab8dcb75b5b1cd507799a715efb4","rule_catalog_cid":"sha256:538424f689566bf75ba8e9e20241aad4bea6acdeccf301216bcd3dc64036ad49","version":"actql-normalization-journal/0.1"}
  let evidence = prepared_client_local_normalization_evidence(owner, issued).unwrap()
  assert_eq(@publication.run_evidence_value_json(evidence), expected)
  assert_true(
    restore_prepared_client_local_normalization(
      owner, issued, expected, "sha256:538424f689566bf75ba8e9e20241aad4bea6acdeccf301216bcd3dc64036ad49",
    )
    is Ok(_),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      issued,
      expected,
      client_local_completion_free_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
  let foreign = local_explicit_cast_original()
  assert_true(
    prepared_client_local_normalization_evidence(foreign, issued)
    is Err(ForeignPreparation),
  )
}

///|
test "explicit CAST with original supplied Parameters uses its own exact alternative" {
  let owner = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    "{\"id\":{\"type\":\"string\",\"nullable\":false}}",
    Some("{\"id\":\"exact supplied text\"}"),
    text="SELECT CAST(@id AS STRING) AS id",
  )
  let issued = issue_prepared_client_local_normalization(owner).unwrap()
  let expected =
    #|{"entries":[],"journal_cid":"sha256:3a120cf122225eaf427d4f3223cf0b3019f9d30251524186e56711c0bd0f5ab2","rule_catalog_cid":"sha256:0eebf603b459361c55386c3863c0fc6e3928cdae2def8aeca899272b3ecade47","version":"actql-normalization-journal/0.1"}
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, issued).unwrap(),
    ),
    expected,
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, issued, expected, "sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1",
    )
    is Err(ForeignCatalog),
  )
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    "{\"id\":{\"type\":\"number\",\"nullable\":false,\"default\":7}}",
    None,
    text="SELECT CAST(@id AS NUMBER) AS id",
  )
  ignore(local_default_parameter_normalization(defaulted))
}

///|
test "explicit CAST does not waive actual completion or uninstalled relation operations" {
  let implicit_else = local_explicit_cast_original(
    text="SELECT CAST(CASE WHEN TRUE THEN 'yes' END AS STRING) AS value",
  )
  assert_true(
    issue_prepared_client_local_normalization(implicit_else)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(implicit_else.local_normalization is None)
  let distinct = local_explicit_cast_original(
    text="SELECT DISTINCT CAST(ABS(-1) AS NUMBER) AS value",
  )
  ignore(local_distinct_normalization(distinct))
  let output = local_distinct_execute(distinct)
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(@execution.completed_column_name(output, 0), Some("value"))
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Number(value)) &&
    value == 1.0,
  )
  let unsupported = local_group_original_document(
    (
      #|{"version":"actql/0.1","id":"local.unsupported-cast-dedupe","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"number","nullable":false}},"rows":[{"id":-1,"other":2}]},"as":"input"},{"derive":{"value":"cast(abs(id) as NUMBER)"}},{"dedupe_rows":{"by":["id"],"order_by":[{"field":"id","dir":"asc","nulls":"last"}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
  assert_true(
    issue_prepared_client_local_normalization(unsupported)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(unsupported.local_normalization is None)
}

///|
test "the unchanged public CAST query evaluates its original Number Unicode and NULL cells" {
  let original = local_explicit_cast_original()
  let normalization = issue_prepared_client_local_normalization(original).unwrap()
  assert_true(
    prepared_client_local_normalization_evidence(original, normalization)
    is Ok(_),
  )
  let owner = @strategy.graph_task_owner(original.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(owner, run_materials_limits().sequence).unwrap()
  let generated = local_explicit_cast_generated(sequence)
  let completed = @execution.execute_generated_sequence(
    generated,
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(@execution.completed_column_count(output), 3)
  let mut seen = 0
  for column in 0..<@execution.completed_column_count(output) {
    match @execution.completed_column_name(output, column).unwrap() {
      "id" => {
        assert_true(
          @execution.completed_cell(output, 0, column) is Some(Number(value)) &&
          value == 4.0,
        )
        seen += 1
      }
      "note" => {
        assert_true(
          @execution.completed_cell(output, 0, column)
          is Some(Text("日本語")),
        )
        seen += 1
      }
      "missing" => {
        assert_true(@execution.completed_cell(output, 0, column) is Some(Null))
        seen += 1
      }
      _ => fail("unexpected public projection field")
    }
  }
  assert_eq(seen, 3)
}

///|
fn local_explicit_cast_generated(
  sequence : @lower.PreparedSequence,
) -> @execution.GeneratedSequence {
  let physical : @execution.RegistryLimits = {
    max_body_bytes: 65536,
    max_body_nodes: 8192,
    max_body_depth: 64,
  }
  let contracts = @execution.admit_relation_registry(
    product_asset_value(compiler_registered_body_wire()).unwrap(),
    product_asset_value(compiler_registered_values_wire()).unwrap(),
    physical,
  ).unwrap()
  let fragment_contract = @execution.admit_fragment_contract(
    contracts,
    product_asset_value(product_test_fragment_wire()).unwrap(),
    physical,
  ).unwrap()
  let fragment = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(fragment, 10L, 1000L).unwrap()
  let context = @execution.prepare_runtime_fragment(
    request,
    fragment_contract,
    {
      max_roots: 100,
      max_nodes: 10000,
      max_work: 100000,
      max_text_bytes: 100000,
      max_links: 10000,
    },
    physical,
    {
      max_input_rows: 10L,
      max_value_bytes: 1000L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
  ).unwrap()
  @execution.prepare_generated_sequence(
    contracts,
    sequence,
    [context],
    [
      @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(@lower.sequence_owner(sequence)),
          @lower.sequence_count(sequence) - 1,
        ).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
}
