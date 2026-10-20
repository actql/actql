///|
fn string_try_number_test_environment(
  max_input_bytes? : Int = 256,
) -> @checked.CheckEnvironment {
  // An explicit admitted test profile, not operational Host/Account capacity.
  let default_policy =
    #|{"max_input_codepoints":64,"max_input_utf8_bytes":256,"max_output_bytes":64,"max_pattern_bytes":1,"max_replacements":1,"version":"actql-text-time-host-policy/0.1"}
  let policy = default_policy.replace(
    old="\"max_input_utf8_bytes\":256",
    new="\"max_input_utf8_bytes\":" + max_input_bytes.to_string(),
  )
  let unsigned = run_materials_environment_wire.replace(
    old="\"evidence_bundle_cid\":\"" + run_materials_environment_cid + "\",",
    new="",
  ).replace(
    old="\"version\":\"actql-capacity-host-policy/0.1\"}}",
    new="\"version\":\"actql-capacity-host-policy/0.1\"},\"text_time_evaluation\":" + policy + "}",
  )
  let cid = "sha256:" + @sha.hex(@utf8.encode(unsigned))
  let wire = unsigned.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  admit_client_check_environment(
    wire, cid,
    { text_time: true, veca: false },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false },
  ).unwrap()
}

///|
test "TRY_NUMBER original String task retains the admitted expression envelope through compilation" {
  let document =
    #|{"version":"actql/0.1","id":"string-conversion","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":false}},"rows":[{"text":"12.5"}]},"as":"input"},{"derive":{"n":{"try_number":{"value":{"field":"text"}}}},"as":"parsed"}],"results":{"r":{"from":"parsed","fields":["n"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  let limits = run_materials_limits()
  let prepared = match prepare_effect_free_client_program(
    document, Json, string_try_number_test_environment(), None, limits.preparation,
  ) {
    Ok(value) => value
    Err(Check(issue)) => {
      let phase = match @checked.diagnostic_cause(issue) {
        @checked.LocalConstructionFailure::InvalidLimits => "invalid_limits"
        @checked.LocalConstructionFailure::Program(_) => "program"
        @checked.LocalConstructionFailure::CapacityInputs(_) => "capacity_inputs"
        @checked.LocalConstructionFailure::Environment(_) => "environment"
        @checked.LocalConstructionFailure::Source(@checked.SourceFailure::Checks(@context.TextBounds(bound_issue))) => {
          debug_inspect(bound_issue, content="original String bounds must admit")
          "source/text_bounds"
        }
        @checked.LocalConstructionFailure::Source(@checked.SourceFailure::Checks(_)) => "source/checks"
        @checked.LocalConstructionFailure::Source(@checked.SourceFailure::Identity(_)) => "source/identity"
        @checked.LocalConstructionFailure::Source(@checked.SourceFailure::Requests(_)) => "source/requests"
        @checked.LocalConstructionFailure::Source(@checked.SourceFailure::RequestForm(_)) => "source/request_form"
        @checked.LocalConstructionFailure::Source(@checked.SourceFailure::Registration(_)) => "source/registration"
        @checked.LocalConstructionFailure::Source(@checked.SourceFailure::Declarations(_)) => "source/declarations"
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(Program(Program(Pipeline(_, nested))))
        ) => {
          debug_inspect(nested.kind, content="original String pipeline must admit")
          "source/source_view/pipeline"
        }
        @checked.LocalConstructionFailure::Source(@checked.SourceFailure::SourceView(_)) => "source/source_view"
        @checked.LocalConstructionFailure::Source(_) => "source/other"
        @checked.LocalConstructionFailure::Closure(_) => "closure"
        @checked.LocalConstructionFailure::Units(_) => "units"
        @checked.LocalConstructionFailure::Template(_, _) => "template"
      }
      fail("original String Program check failure: " + phase)
    }
    Err(Graph(issue)) => {
      debug_inspect(issue, content="original String Program must prepare")
      abort("unreachable after failed Graph diagnostic")
    }
    Err(_) => fail("original String Program failed before its task graph")
  }
  let owner = @strategy.graph_task_owner(prepared.graph, 0).unwrap()
  match @lower.lower_expression(owner, 1, 0, limits.sequence.expressions) {
    Ok(_) => ()
    Err(issue) => debug_inspect(issue.kind, content="original String expression must lower" )
  }
  let compilation = issue_prepared_client_task_compilation(
    prepared, run_materials_manifests(), limits.sequence,
    1000, 1000, 1000000, 100000, 100,
  )
  assert_true(compilation is Ok(_), msg="same original String envelope did not reach task compilation")
}

///|
test "TRY_NUMBER original String closure binds only the same pipeline and Parameters" {
  let document =
    #|{"version":"actql/0.1","id":"string-originals","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":false}},"rows":[{"text":"12.5"}]},"as":"input"},{"derive":{"n":{"try_number":{"value":{"field":"text"}}}},"as":"parsed"}],"results":{"r":{"from":"parsed","fields":["n"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  let environment = string_try_number_test_environment()
  let limits = run_materials_limits().preparation
  let parsed = @syntax.parse(document, limits.checking.input, format=Json).unwrap()
  let checked = match @checked.check_parsed(parsed, environment, None, limits.checking) {
    Checked(value) => value
    _ => fail("original String check must close")
  }
  let owners = prepare_client_stage_owners(checked, limits).unwrap()
  let owner = owners[0]
  let closure = @checked.expression_closure(checked).unwrap()
  let rebound = @lower.bind_program_expression_closure(
    owner, closure, 0, limits.lowering.max_work,
  ).unwrap()
  assert_true(physical_equal(
    @lower.bound_preparation(rebound), @lower.bound_preparation(owner),
  ))
  assert_true(physical_equal(
    @lower.parameter_bindings(rebound).unwrap(),
    @lower.parameter_bindings(owner).unwrap(),
  ))
  // Rechecking the very same parsed bytes and environment creates another
  // invocation's pipeline and Parameter originals, not a reusable permission.
  let foreign = match @checked.check_parsed(parsed, environment, None, limits.checking) {
    Checked(value) => value
    _ => fail("equal foreign String check must close independently")
  }
  assert_true(@lower.bind_program_expression_closure(
    owner, @checked.expression_closure(foreign).unwrap(), 0,
    limits.lowering.max_work,
  ) is Err({ kind: BindingOwnerMismatch, .. }))
  assert_true(@lower.bind_program_expression_closure(
    owner, closure, -1, limits.lowering.max_work,
  ) is Err({ kind: BindingOwnerMismatch, .. }))
  assert_true(@lower.bind_program_expression_closure(
    owner, closure, 1, limits.lowering.max_work,
  ) is Err({ kind: BindingOwnerMismatch, .. }))
  assert_true(@lower.bind_program_expression_closure(
    owner, closure, 0, 0,
  ) is Err({ kind: BindingBudgetExceeded, .. }))
}

///|
fn string_try_number_sequence(
  document : String, max_input_bytes? : Int = 256,
) -> @lower.PreparedSequence {
  let limits = run_materials_limits()
  let prepared = prepare_effect_free_client_program(
    document, Json, string_try_number_test_environment(max_input_bytes~), None, limits.preparation,
  ).unwrap()
  @lower.prepare_sequence(
    @strategy.graph_task_owner(prepared.graph, 0).unwrap(), limits.sequence,
  ).unwrap()
}

///|
fn string_try_number_generated(
  sequence : @lower.PreparedSequence,
) -> @execution.GeneratedSequence {
  let physical : @execution.RegistryLimits = {
    max_body_bytes: 65536, max_body_nodes: 8192, max_body_depth: 64,
  }
  let contracts = @execution.admit_relation_registry(
    product_asset_value(compiler_registered_body_wire()).unwrap(),
    product_asset_value(compiler_registered_values_wire()).unwrap(), physical,
  ).unwrap()
  let fragment_contract = @execution.admit_fragment_contract(
    contracts, product_asset_value(product_test_fragment_wire()).unwrap(), physical,
  ).unwrap()
  let fragment = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100, max_pointer_bytes: 10000, max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(fragment, 10L, 1000L).unwrap()
  let context = @execution.prepare_runtime_fragment(
    request, fragment_contract,
    { max_roots: 100, max_nodes: 10000, max_work: 100000,
      max_text_bytes: 100000, max_links: 10000, },
    physical,
    { max_input_rows: 10L, max_value_bytes: 1000L,
      max_live_value_bytes: 10000L, max_work: 100000L, },
  ).unwrap()
  @execution.prepare_generated_sequence(
    contracts, sequence, [context], ["derive_1"], 100000, 10000,
  ).unwrap()
}

///|
fn string_try_number_execution_limits() -> @execution.SequenceExecutionLimits {
  {
    rows: {
      max_rows: 100, metadata_entries: 10000, retained_entries: 10000,
      operation_entries: 10000,
      input_values: { max_nodes: 10000, max_text_bytes: 10000, max_depth: 100, max_work: 100000, },
      output_values: { max_nodes: 10000, max_text_bytes: 10000, max_depth: 100, max_work: 100000, },
    },
    max_work: 100000, max_frames: 100,
  }
}

///|
test "TRY_NUMBER original String admitted fragment executes conversion and NULL without swallowing input limits" {
  let document =
    #|{"version":"actql/0.1","id":"string-execution","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":true}},"rows":[{"text":"12.5"},{"text":"not a number"},{"text":null},{"text":"-0"},{"text":"1e999"} ]},"as":"input"},{"derive":{"n":{"try_number":{"value":{"field":"text"}}}},"as":"parsed"}],"results":{"r":{"from":"parsed","fields":["n"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  let sequence = string_try_number_sequence(document)
  let generated = string_try_number_generated(sequence)
  let outcome = @execution.execute_generated_sequence(
    generated, [], string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(outcome, @pipeline.Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 5)
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Number(12.5)))
  assert_true(@execution.completed_cell(output, 1, 1) is Some(Null))
  assert_true(@execution.completed_cell(output, 2, 1) is Some(Null))
  assert_true(@execution.completed_cell(output, 3, 1) is Some(Number(0.0)))
  assert_true(@execution.completed_cell(output, 4, 1) is Some(Null))
  // An invalid first character is not permission to skip complete input
  // preflight: the same admitted unbounded field exceeds its original policy.
  let too_long = document.replace(old="not a number", new="x".repeat(65))
  guard @execution.execute_generated_sequence(
    string_try_number_generated(string_try_number_sequence(too_long)), [],
    string_try_number_execution_limits(),
  ) is Err(Rows(1, Evaluation(1, 0, issue))) else {
    fail("complete invalid input must refuse at its original String preflight")
  }
  assert_true(issue.kind is TextBounds(InputCeiling))
  assert_true(@execution.execute_generated_sequence(
    generated, [], { ..string_try_number_execution_limits(), max_work: 1, },
  ) is Err(_))
}

///|
test "TRY_NUMBER original String preserves lazy demand and original child failures" {
  let document =
    #|{"version":"actql/0.1","id":"string-demand","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":false}},"rows":[{"text":"long-input"}]},"as":"input"},{"derive":{"n":"if(TRUE, 7, try_number(text))"},"as":"parsed"}],"results":{"r":{"from":"parsed","fields":["n"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  let generated = string_try_number_generated(string_try_number_sequence(
    document.replace(old="long-input", new="x".repeat(65)),
  ))
  let result = @execution.execute_generated_sequence(
    generated, [], string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(result, @pipeline.Step(1)).unwrap()
  assert_true(@execution.completed_cell(output, 0, 1) is Some(Number(7.0)))
  let demanded = document.replace(
    old="if(TRUE, 7, try_number(text))", new="try_number(to_string(1 / 0))",
  )
  guard @execution.execute_generated_sequence(
    string_try_number_generated(string_try_number_sequence(demanded)), [],
    string_try_number_execution_limits(),
  ) is Err(Rows(1, Evaluation(0, 0, issue))) else {
    fail("TRY_NUMBER must retain its demanded child's original failure")
  }
  assert_true(issue.kind is Scalar(ArithmeticFailure))
}

///|
test "TRY_NUMBER original String enforces UTF8 bytes independently of codepoint extent" {
  let document =
    #|{"version":"actql/0.1","id":"string-bytes","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"text":{"type":"string","nullable":false}},"rows":[{"text":"byte-input"}]},"as":"input"},{"derive":{"n":{"try_number":{"value":{"field":"text"}}}},"as":"parsed"}],"results":{"r":{"from":"parsed","fields":["n"]}}}],"results":{"r":{"from":{"stage":"main","result":"r"}}}}
  guard @execution.execute_generated_sequence(
    string_try_number_generated(string_try_number_sequence(
      document.replace(old="byte-input", new="😀".repeat(17)), max_input_bytes=64,
    )), [], string_try_number_execution_limits(),
  ) is Err(Rows(1, Evaluation(0, 0, issue))) else {
    fail("17 scalars with 68 UTF8 bytes must exceed the original 64-byte ceiling")
  }
  assert_true(issue.kind is TextBounds(InputCeiling))
}
