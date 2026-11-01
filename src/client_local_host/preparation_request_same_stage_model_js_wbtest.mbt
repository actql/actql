///|
// Same-stage acquisition/serialization/Infer topology as the installed mixed
// caller. The independent existing text-task and Source declaration vectors
// isolate constructor ownership from paid Model IO and Content media decoding.
// Resource admission remains the existing explicit component fixture.
test "same-stage acquired serialized Model preserves original capture module inputs" {
  let declaration = request_model_module_declaration()
  let (environment, _) = effect_model_plan_source(declaration=Some(declaration))
  let document =
    #|{"version":"actql/0.1","id":"same-stage-acquired-serialized-model","stages":[{"id":"main","inputs":{"remote":{"connector":"model/source-fixture","resource":"r","view":"records"}},"steps":[{"from":"remote","filter":"id >= 0","as":"scan"},{"select":["id"],"as":"captured"},{"assert_rows":{"unique_by":["id"]},"as":"unique_input"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":1,"max_bytes":128}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]},"as":"unique_attachment"},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"inferred"}],"results":{"answer":{"from":"inferred","fields":["name","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"answer"}}}}
  let ordinary = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let domain = {
    ..effect_model_plan_limits,
    retained_bytes: ordinary.retained_bytes,
    execution_bytes: ordinary.execution_bytes,
  }
  let (parent, child, _, input) = registration_parent_fixture(
    text=document,
    environment=Some(environment),
    initial_limits=Some(@resources.add_ledger_limits(ordinary, domain).unwrap()),
  )
  let outcome = finish_program_check_preparation(child).unwrap()
  let semantic = match outcome {
    @checked.Checked(_) => "checked"
    @checked.NeedsInputs(_) => "needs-inputs"
    @checked.Rejected(diagnostic) => {
      let category = @debug.to_string(@checked.diagnostic_category(diagnostic))
      let cause = match @checked.diagnostic_cause(diagnostic) {
        @checked.Units(@checked.UnsupportedStaticPath(_)) =>
          "Units.UnsupportedStaticPath"
        @checked.Units(@checked.UnclosedSourceExecution(_, _)) =>
          "Units.UnclosedSourceExecution"
        @checked.Units(@checked.UnclosedPublicationPolicy(_, _)) =>
          "Units.UnclosedPublicationPolicy"
        @checked.Units(_) => "Units"
        @checked.Closure(_) => "Closure"
        @checked.Source(@checked.Requests(reason)) => {
          let branch = match reason {
            @context.InvalidLimits => "InvalidLimits"
            @context.BudgetExceeded => "BudgetExceeded"
            @context.Declarations(_) => "Declarations"
            @context.Slots(_) => "Slots"
            @context.Requests(_) => "Requests"
            @context.Rows(_) => "Rows"
            @context.Policy(_) => "Policy"
            @context.Capacity(_) => "Capacity"
            @context.Producers(_) => "Producers"
          }
          "Source.Requests/" + branch
        }
        @checked.Source(@checked.Registration(_)) => "Source.Registration"
        @checked.Source(@checked.Declarations(_)) => "Source.Declarations"
        @checked.Source(@checked.Checks(_)) => "Source.Checks"
        @checked.Source(@checked.SourceView(@context.InvalidLimits)) =>
          "Source.SourceView.InvalidLimits"
        @checked.Source(
          @checked.SourceView(
            @context.SourceViewContextIssue::Program(
              @context.SourceViewProgramIssue::Program(
                @stage_results.LocalProgramIssue::Pipeline(stage, issue)
              )
            )
          )
        ) =>
          "Source.SourceView.Program.Pipeline/" +
          stage.to_string() +
          "/" +
          @debug.to_string(issue.kind)
        @checked.Source(
          @checked.SourceView(@context.SourceViewContextIssue::Program(reason))
        ) => {
          let branch = match reason {
            @context.SourceViewProgramIssue::InvalidLimits => "InvalidLimits"
            @context.SourceViewProgramIssue::Unavailable => "Unavailable"
            @context.SourceViewProgramIssue::ForeignEnvironment =>
              "ForeignEnvironment"
            @context.SourceViewProgramIssue::ForeignCalendarEnvironment =>
              "ForeignCalendarEnvironment"
            @context.SourceViewProgramIssue::CalendarSelection(_) =>
              "CalendarSelection"
            @context.SourceViewProgramIssue::MissingCalendarArtifact(_) =>
              "MissingCalendarArtifact"
            @context.SourceViewProgramIssue::MissingCalendarSelection(_, _) =>
              "MissingCalendarSelection"
            @context.SourceViewProgramIssue::ForeignSource => "ForeignSource"
            @context.SourceViewProgramIssue::ForeignPartition(_) =>
              "ForeignPartition"
            @context.SourceViewProgramIssue::BudgetExceeded => "BudgetExceeded"
            @context.SourceViewProgramIssue::Registration(_, issue) =>
              "Registration/" + @debug.to_string(issue)
            @context.SourceViewProgramIssue::Program(issue) =>
              match issue {
                @stage_results.LocalProgramIssue::InvalidLimits =>
                  "Program.InvalidLimits"
                @stage_results.LocalProgramIssue::CheckOnlyPrefix =>
                  "Program.CheckOnlyPrefix"
                @stage_results.LocalProgramIssue::BudgetExceeded =>
                  "Program.BudgetExceeded"
                @stage_results.LocalProgramIssue::ForeignEnvironmentSource =>
                  "Program.ForeignEnvironmentSource"
                @stage_results.LocalProgramIssue::ForeignModelEnvironment =>
                  "Program.ForeignModelEnvironment"
                @stage_results.LocalProgramIssue::SourceViewStageCount =>
                  "Program.SourceViewStageCount"
                @stage_results.LocalProgramIssue::MissingSourceViewRegistrations(
                  _
                ) => "Program.MissingSourceViewRegistrations"
                @stage_results.LocalProgramIssue::InvalidSourceViewRegistration(
                  _,
                  _
                ) => "Program.InvalidSourceViewRegistration"
                @stage_results.LocalProgramIssue::UnsupportedReceipt(_, _) =>
                  "Program.UnsupportedReceipt"
                @stage_results.LocalProgramIssue::LocalInput(_, _) =>
                  "Program.LocalInput"
                @stage_results.LocalProgramIssue::Import(_, _) =>
                  "Program.Import"
                @stage_results.LocalProgramIssue::Pipeline(_, reason) =>
                  "Program.Pipeline/" + @debug.to_string(reason.kind)
                @stage_results.LocalProgramIssue::Collection(_, _) =>
                  "Program.Collection"
                @stage_results.LocalProgramIssue::Results(_, _) =>
                  "Program.Results"
                @stage_results.LocalProgramIssue::Order(_, _) => "Program.Order"
                @stage_results.LocalProgramIssue::Ports(_, _) => "Program.Ports"
                @stage_results.LocalProgramIssue::TableInputs(_, _) =>
                  "Program.TableInputs"
                @stage_results.LocalProgramIssue::Wiring(_) => "Program.Wiring"
              }
          }
          "Source.SourceView.Program/" + branch
        }
        @checked.Source(@checked.SourceView(@context.Binding(_))) =>
          "Source.SourceView.Binding"
        @checked.Source(@checked.SourceView(@context.Context(_))) =>
          "Source.SourceView.Context"
        @checked.Source(@checked.RequestForm(reason)) =>
          "Source.RequestForm/" + @debug.to_string(reason)
        @checked.Source(@checked.Identity(_)) => "Source.Identity"
        @checked.Source(@checked.UnsupportedBindings(_)) =>
          "Source.UnsupportedBindings"
        @checked.Source(@checked.UnsupportedEffects(_)) =>
          "Source.UnsupportedEffects"
        @checked.Source(@checked.DeclarationWorkLimit) =>
          "Source.DeclarationWorkLimit"
        @checked.Source(@checked.CapacityMetadataBudget) =>
          "Source.CapacityMetadataBudget"
        @checked.Environment(_) => "Environment"
        @checked.Program(_) => "Program"
        @checked.CapacityInputs(_) => "CapacityInputs"
        @checked.Template(_, _) => "Template"
        @checked.InvalidLimits => "InvalidLimits"
      }
      category + "/" + cause
    }
  }
  let prepared = match
    compile_program_check_preparation(
      child,
      @publication_host.client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(WrongPhase) =>
      fail("same-stage checked fixture: WrongPhase/" + semantic)
    Err(Compilation(_)) =>
      fail("same-stage checked fixture: Compilation/" + semantic)
    Err(_) =>
      fail("same-stage checked fixture: other typed refusal/" + semantic)
  }
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let component = prepare_request_acquired_serialization_graph(
    parent,
    input,
    0,
    3,
    1,
    128,
    true,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits~,
    serialization=Some(component),
  ).unwrap()
  let compilation = prepare_request_model_compilation(
    parent,
    input,
    graph,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "same-stage-model", "same-original", "2026-10-31T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-stage-model",
  ).unwrap()
  let (_, execution_limits, measurement) = client_local_execution_limits(
    max_rows=1,
  )
  let prefix = prepare_request_model_serialization_plan(
    parent,
    input,
    request,
    compiled,
    definition,
    execution_limits,
    measurement,
    None,
    None,
  ).unwrap()
  assert_true(
    physical_equal(prefix.request, request) &&
    physical_equal(prefix._observed_compiled, compiled) &&
    physical_equal(prefix._observed_definition, definition),
  )
  let provider = @execution.execution_capacity(7L, 9L).unwrap()
  let calls = Ref(0)
  let result = prepare_request_model_capture_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    [declaration],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [4096L],
    [2048L],
    contracts,
    true,
    0,
    _ => {
      calls.val += 1
      []
    },
    providers=Some([Some(provider)]),
  )
  // Return this exact held input and settle its parent even when the real
  // constructor refuses. Debug renders the typed issue in this own fixture;
  // no JS enum/Option layout or old ordinary state is inspected.
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  match result {
    Err(Preparation(ForeignOriginal)) =>
      fail("same-stage capture module: Preparation.ForeignOriginal")
    Err(Installed(Unsupported)) =>
      fail("same-stage capture module: Installed.Unsupported")
    Err(ModelQuery(Sequences)) =>
      fail("same-stage capture module: ModelQuery.Sequences")
    Err(ModelQuery(_)) =>
      fail("same-stage capture module: ModelQuery other typed refusal")
    Err(ModelSource(_)) =>
      fail("same-stage capture module: ModelSource typed refusal")
    Err(CapacityExceeded(_)) =>
      fail("same-stage capture module: CapacityExceeded")
    Err(_) => fail("same-stage capture module: other typed refusal")
    Ok(original) => {
      assert_eq(calls.val, 1)
      assert_true(
        physical_equal(original.prepared, prepared) &&
        physical_equal(original.captures[0].provider.unwrap().1, provider),
      )
    }
  }
}
