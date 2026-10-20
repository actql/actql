///|
let local_group_catalog_cid : String = "sha256:b63098d9379e482326c612be898d13d86c0c849d6c77afb7f2574b33cb2a78d5"

///|
let local_group_journal : String =
  #|{"entries":[],"journal_cid":"sha256:36ee9950b74a43a5403eda628c3d5cc1bc147283e6bca6710b1c079181467d09","rule_catalog_cid":"sha256:b63098d9379e482326c612be898d13d86c0c849d6c77afb7f2574b33cb2a78d5","version":"actql-normalization-journal/0.1"}

///|
fn local_group_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let issued = issue_prepared_client_local_normalization(owner).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, issued).unwrap(),
    ),
    local_group_journal,
  )
  assert_true(
    @checked.local_completion_free_inventory_uses_groups(
      match issued.audit {
        CompletionFree(value) => value
        SortCompletion(_) => fail("completion-free original expected")
      },
    ),
  )
  issued
}

///|
test "unchanged public COUNT query normalizes and evaluates the existing Number count" {
  let original = local_explicit_cast_original(text="SELECT COUNT(*) AS n")
  ignore(local_group_normalization(original))
  let task = @strategy.graph_task_owner(original.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  let completed = @execution.execute_generated_sequence(
    local_group_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(@execution.completed_column_name(output, 0), Some("n"))
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Number(value)) &&
    value == 1.0,
  )
}

///|
test "one Group catalog covers count extrema and original supplied cast combinations" {
  for
    text in [
      "SELECT COUNTIF(TRUE) AS n, MIN(ABS(-3)) AS lo, MAX(2) AS hi", "SELECT COUNT(CAST(NULL AS NUMBER)) AS n",
    ] {
    ignore(local_group_normalization(local_explicit_cast_original(text~)))
  }
  let declarations = "{\"value\":{\"type\":\"number\",\"nullable\":false,\"default\":-3}}"
  let text = "SELECT MIN(ABS(CAST(@value AS NUMBER))) AS lo"
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    let supplied = local_supplied_parameter_preparation(
      format,
      declarations,
      Some("{\"value\":-3}"),
      text~,
    )
    let issued = local_group_normalization(supplied)
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
    assert_true(
      prepared_client_local_normalization_evidence(defaulted, issued)
      is Err(ForeignPreparation),
    )
  }
}

///|
test "Group normalization retains original argument completion and unsupported relation refusals" {
  let implicit_else = local_explicit_cast_original(
    text="SELECT COUNT(CASE WHEN TRUE THEN 1 END) AS n",
  )
  assert_true(
    issue_prepared_client_local_normalization(implicit_else)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(implicit_else.local_normalization is None)
  let uncovered_relation = local_explicit_cast_original(
    text="SELECT DISTINCT COUNT(*) AS n",
  )
  assert_true(
    issue_prepared_client_local_normalization(uncovered_relation)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(uncovered_relation.local_normalization is None)
}

///|
test "Group normalization rejects equal foreign owners copies and predecessor journals" {
  let original = local_explicit_cast_original(text="SELECT COUNT(*) AS n")
  let issued = local_group_normalization(original)
  let equal_input = local_explicit_cast_original(text="SELECT COUNT(*) AS n")
  assert_true(
    prepared_client_local_normalization_evidence(equal_input, issued)
    is Err(ForeignPreparation),
  )
  let copy : ClientLocalNormalization = {
    preparation: issued.preparation,
    audit: issued.audit,
    evidence: issued.evidence,
  }
  assert_true(
    prepared_client_local_normalization_evidence(original, copy)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, issued, local_group_journal, local_checked_expression_catalog_cid,
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, issued, local_checked_expression_journal, local_group_catalog_cid,
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, issued, local_group_journal, local_group_catalog_cid,
    )
    is Ok(_),
  )
}

///|
test "authored Group keys fields distinct and filters retain the original checked execution" {
  let document =
    #|{"version":"actql/0.1","id":"local.group","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false},"amount":{"type":"number","nullable":true}},"rows":[{"key":"a","amount":3},{"key":"a","amount":null},{"key":"a","amount":3}]},"as":"input"},{"from":"input","group":{"by":["key"],"aggregates":{"n":{"fn":"count","field":"amount","distinct":true},"lo":{"fn":"min","field":"amount"},"hi":{"fn":"max","expr":"abs(amount)","filter":"amount IS NOT NULL"}}},"as":"grouped"}],"results":{"rows":{"from":"grouped","fields":["key","n","lo","hi"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  ignore(local_group_normalization(original))
  let task = @strategy.graph_task_owner(original.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  let completed = @execution.execute_generated_sequence(
    local_group_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  for column in 0..<@execution.completed_column_count(output) {
    match @execution.completed_column_name(output, column).unwrap() {
      "key" =>
        assert_true(
          @execution.completed_cell(output, 0, column) is Some(Text("a")),
        )
      "n" =>
        assert_true(
          @execution.completed_cell(output, 0, column) is Some(Number(v)) &&
          v == 1.0,
        )
      "lo" | "hi" =>
        assert_true(
          @execution.completed_cell(output, 0, column) is Some(Number(v)) &&
          v == 3.0,
        )
      _ => fail("unexpected Group output column")
    }
  }
}

///|
// These original sequences contain Values, Group, checked Derive and projection.
// Only the original dynamic Group bindings receive expression contexts; a
// count-only Group is not an expression kernel.
fn local_group_generated(
  sequence : @lower.PreparedSequence,
) -> @execution.GeneratedSequence raise {
  let contexts : Array[@execution.FragmentRuntimeContext] = []
  for index in 0..<@lower.sequence_count(sequence) {
    match @lower.sequence_step(sequence, index).unwrap() {
      ValuesStep(_) => ()
      RowStep(kernel) => {
        assert_true(
          @lower.kernel_group(kernel) is Some(_) ||
          @lower.kernel_count_group(kernel) is Some(_) ||
          @lower.kernel_is_projection(kernel) ||
          @lower.kernel_take(kernel) is Some(_) ||
          @lower.kernel_is_sort(kernel) ||
          @relation.operation(@lower.kernel_checked(kernel)) is @relation.Derive,
        )
        if @relation.binding_count(@lower.kernel_checked(kernel)) > 0 {
          contexts.push(local_group_context(sequence, index))
        }
      }
      _ => fail("unexpected operation in original Group execution counter")
    }
  }
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
  @execution.prepare_generated_sequence(
    contracts,
    sequence,
    contexts,
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

///|
fn local_group_original_document(
  document : String,
) -> PreparedClientProgram raise {
  let environment = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:9882e5f1412beaf650b0fdaf55035b198b7b87e8e9e3c3a0f07730953b0a72ed",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  match
    prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Check(issue)) => {
      match @checked.diagnostic_cause(issue) {
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(
            Program(Program(Pipeline(_, nested)))
          )
        ) =>
          debug_inspect(
            nested.kind,
            content="original keyed Group pipeline must admit",
          )
        @checked.LocalConstructionFailure::Source(source) => raise source
        cause => raise cause
      }
      abort("unreachable after failed original Group diagnostic")
    }
    Err(Syntax(_)) => fail("structured Group source syntax rejected")
    Err(Lowering(_)) => fail("structured Group lowering rejected")
    Err(Binding(_)) => fail("structured Group binding rejected")
    Err(Graph(_)) => fail("structured Group graph rejected")
    _ => fail("structured Group original preparation rejected")
  }
}

///|
fn local_group_context(
  sequence : @lower.PreparedSequence,
  step : Int,
) -> @execution.FragmentRuntimeContext {
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
  let contract = @execution.admit_fragment_contract(
    contracts,
    product_asset_value(product_test_fragment_wire()).unwrap(),
    physical,
  ).unwrap()
  let fragment = @lower.prepare_fragment_pipeline(sequence, step, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(fragment, 10L, 1000L).unwrap()
  @execution.prepare_runtime_fragment(
    request,
    contract,
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
}
