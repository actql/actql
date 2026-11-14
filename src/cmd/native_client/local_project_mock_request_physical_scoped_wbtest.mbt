///|
// Actual retained Native Request facility. The producer token is component
// DATA; no Account, Journal, Runtime/Host authority or durable Run is supplied.
priv struct NativeMockReadmeRequestFacility {
  arena : @initial_arena.InstalledArenaHost
  domain : @initial_arena.InstalledArenaDomain
  physical : @initial_arena.InstalledArenaRetainedExecution
  parent : @local_values.ClientRequestPreparation[Array[Int]]
  input : Array[Int]
  mut run : @local_values.ClientInstalledManagedRun?
}

///|
fn native_mock_readme_request_facility() -> NativeMockReadmeRequestFacility raise {
  let input = [1]
  // Use the existing ordinary initial Request policy without lowering its
  // checked demand or raising a logical cap to make this Program pass.
  let policy = @local_values.client_local_preparation_initial_limits(
    @local_values.client_local_resource_policy(),
  ).unwrap()
  let payload = policy.retained_bytes + policy.execution_bytes
  let mut domain_bytes = payload
  for _ in 0..<16 {
    let required = @initial_bootstrap.execution_domain_necessary_bytes(
      domain_bytes, payload,
    )
    assert_true(required > 0L)
    if required <= domain_bytes {
      break
    }
    domain_bytes = required
  }
  let bytes = domain_bytes * 2L
  let arena = @initial_arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    {
      // The parent must supply the actual SAME child declarations. The old
      // generic 100000/100GB fixture was smaller than ordinary graph_work
      // and its declared transfer quota, before any Program was inspected.
      planning_work: policy.planning_work * 2,
      attempts: policy.attempts * 2,
      holdings: policy.holdings * 2,
      transfer_bytes: policy.transfer_bytes * 2L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).unwrap()
  arena.acquire().unwrap()
  let backing = arena.borrow_backing().unwrap()
  arena.enter_backing_borrow_scope(backing).unwrap()
  let domain = match
    arena.prepare_domain_in_process(backing, domain_bytes, policy).unwrap() {
    @initial_arena.PreparedDomain(value) => value
    @initial_arena.PendingDomain(_, issue) =>
      fail("README Request domain pending: " + @debug.to_string(issue))
  }
  arena.transfer_domain(domain).unwrap()
  arena.leave_backing_borrow_scope(backing).unwrap()
  arena.return_backing_borrow(backing).unwrap()
  arena.prepare_domain_read(domain).unwrap()
  let (physical, initial) = match
    arena
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: 1048576L,
      bootstrap_execution: 1048576L,
    })
    .unwrap() {
    @initial_arena.ReadyRequestExecution(physical, initial) =>
      (physical, initial)
    @initial_arena.PendingRequestExecution(_, _) =>
      fail("README initial Request pending")
  }
  // Match the ordinary command: the Request control precedes payload entry
  // and remains in its original outer lifetime through physical retirement.
  let parent = @local_values.begin_backed_request_preparation(
    initial,
    input,
    @local_values.client_local_resource_policy(),
  ).unwrap()
  { arena, domain, physical, parent, input, run: None, }
}

///|
fn native_mock_readme_local_issue(
  issue : @checked.LocalConstructionFailure,
) -> String {
  match issue {
    Units(UnclosedSourceExecution(stage, input)) =>
      "Units.UnclosedSourceExecution(" +
      stage.to_string() +
      "," +
      input.to_string() +
      ")"
    Units(UnclosedPublicationPolicy(stage, input)) =>
      "Units.UnclosedPublicationPolicy(" +
      stage.to_string() +
      "," +
      input.to_string() +
      ")"
    Units(_) => "Units"
    Template(_, cause) => {
      let label = match cause {
        BudgetExceeded => "BudgetExceeded"
        Capacity(_) => "Capacity"
        Semantics(_) => "Semantics"
        Definition(_) => "Definition"
        Orders(_, _) => "Orders"
        Profiles(_, _) => "Profiles"
        Values(_, _, _) => "Values"
        Pipeline(_, _) => "Pipeline"
        Context(_, _) => "Context"
        Publication(_, _) => "Publication"
        Contracts(_) => "Contracts"
        ConsumerDeclaration(_, _) => "ConsumerDeclaration"
      }
      "Template." + label
    }
    InvalidLimits => "InvalidLimits"
    Program(_) => "Program"
    CapacityInputs(_) => "CapacityInputs"
    Environment(_) => "Environment"
    Source(Requests(Requests(Facts(cause)))) =>
      "Source.Requests.Requests.Facts(" + @debug.to_string(cause.kind) + ")"
    Source(Requests(Requests(Join(stage, cause)))) =>
      "Source.Requests.Requests.Join(" +
      stage.to_string() +
      "," +
      @debug.to_string(cause.kind) +
      ")"
    Source(Requests(Requests(Stage(stage, cause)))) => {
      let label = match cause {
        InvalidLimits => "InvalidLimits"
        ForeignRequests => "ForeignRequests"
        WorkLimit => "WorkLimit"
        PartialCorrelation(_) => "PartialCorrelation"
        MissingKeyedConsumer(_) => "MissingKeyedConsumer"
        InvalidKeyedConsumer(_, _) => "InvalidKeyedConsumer"
        Mode(_, _) => "Mode"
        Request(_, _) => "Request"
        Binding(_, _) => "Binding"
      }
      "Source.Requests.Requests.Stage(" + stage.to_string() + "," + label + ")"
    }
    Source(Requests(Rows(Stage(stage, cause)))) =>
      "Source.Requests.Rows.Stage(" +
      stage.to_string() +
      "," +
      @debug.to_string(cause) +
      ")"
    Source(Requests(Capacity(Stage(stage, cause)))) =>
      "Source.Requests.Capacity.Stage(" +
      stage.to_string() +
      "," +
      @debug.to_string(cause) +
      ")"
    Source(Requests(cause)) => {
      let label = match cause {
        InvalidLimits => "InvalidLimits"
        BudgetExceeded => "BudgetExceeded"
        Declarations(_) => "Declarations"
        Slots(_) => "Slots"
        Requests(_) => "Requests"
        Rows(_) => "Rows"
        Policy(_) => "Policy"
        Capacity(_) => "Capacity"
        Producers(_) => "Producers"
      }
      "Source.Requests." + label
    }
    Source(cause) => {
      let label = match cause {
        DeclarationWorkLimit => "DeclarationWorkLimit"
        CapacityMetadataBudget => "CapacityMetadataBudget"
        UnsupportedBindings(_) => "UnsupportedBindings"
        UnsupportedEffects(_) => "UnsupportedEffects"
        Requests(_) => "Requests"
        RequestForm(_) => "RequestForm"
        Checks(_) => "Checks"
        Identity(_) => "Identity"
        Declarations(_) => "Declarations"
        Registration(_) => "Registration"
        SourceView(_) => "SourceView"
      }
      "Source." + label
    }
    Closure(_) => "Closure"
  }
}

///|
fn native_mock_readme_phase_issue(
  issue : @local_values.ClientRequestPreparationIssue,
) -> String {
  match issue {
    ProgramCheck(EffectInput(Computation(cause))) =>
      "ProgramCheck.EffectInput.Computation." +
      native_mock_readme_local_issue(cause)
    ProgramCheck(EffectInput(cause)) => {
      let label = match cause {
        InvalidLimits => "InvalidLimits"
        InvalidProgram(_) => "InvalidProgram"
        Headers(_) => "Headers"
        MissingEffects => "MissingEffects"
        Computation(_) => "Computation"
        Phase(_) => "Phase"
      }
      "ProgramCheck.EffectInput." + label
    }
    ProgramCheck(EffectCompilation(Graph(cause))) =>
      "ProgramCheck.EffectCompilation.Graph(" + @debug.to_string(cause) + ")"
    ProgramCheck(EffectCompilation(cause)) => {
      let label = match cause {
        Syntax(_) => "Syntax"
        Candidate(_) => "Candidate"
        RequestValuePolicies(_) => "RequestValuePolicies"
        RequestValuePolicyConstruction => "RequestValuePolicyConstruction"
        Mapping(_) => "Mapping"
        Static(_) => "Static"
        Stage(_) => "Stage"
        Graph(_) => "Graph"
        TargetSelection(_) => "TargetSelection"
      }
      "ProgramCheck.EffectCompilation." + label
    }
    ProgramCheck(cause) => {
      let label = match cause {
        Capacity(_) => "Capacity"
        Check(_) => "Check"
        Catalog(_) => "Catalog"
        SourceRegistration(_) => "SourceRegistration"
        TopologyEntry(_) => "TopologyEntry"
        Prelude(_) => "Prelude"
        Compilation(_) => "Compilation"
        EffectInput(_) => "EffectInput"
        EffectCompilation(_) => "EffectCompilation"
        SourceInput(_) => "SourceInput"
        Work(_) => "Work"
        ChangedInputs => "ChangedInputs"
        WrongPhase => "WrongPhase"
        Overflow => "Overflow"
        RequestPolicySubjects(_) => "RequestPolicySubjects"
      }
      "ProgramCheck." + label
    }
    other => command_preparation_cleanup_cause(CommandRequestPreparation(other))
  }
}

///|
// Closed authored-source diagnosis only. Keep original typed rejection apart
// from a physical construction refusal or missing implementation branch.
fn native_mock_readme_request_issue(
  issue : @local_host.NativeClientSubmittedPreparationIssue,
) -> String {
  match issue {
    RequestPreparation(cause) =>
      "RequestPreparation(" + native_mock_readme_phase_issue(cause) + ")"
    Request(Preparation(cause)) =>
      "Request.Preparation(" + native_mock_readme_phase_issue(cause) + ")"
    Request(CheckOutcome(@checked.Rejected(diagnostic))) => {
      let category = @debug.to_string(@checked.diagnostic_category(diagnostic))
      let cause = match @checked.diagnostic_cause(diagnostic) {
        Program(_) => "Program"
        CapacityInputs(_) => "CapacityInputs"
        Environment(_) => "Environment"
        Source(_) => "Source"
        Closure(_) => "Closure"
        Units(_) => "Units"
        Template(_, _) => "Template"
        InvalidLimits => "InvalidLimits"
      }
      "Request.CheckOutcome.Rejected(" + category + "," + cause + ")"
    }
    Request(CheckOutcome(_)) => "Request.CheckOutcome"
    Request(QuerySyntax(_)) => "Request.QuerySyntax"
    Request(QueryLowering(_)) => "Request.QueryLowering"
    Request(Publication(_)) => "Request.Publication"
    InvalidSubmittedInput => "InvalidSubmittedInput"
    SubmittedInputLimit => "SubmittedInputLimit"
    Declarations(_) => "Declarations"
    Preparation(_) => "Preparation"
    ReadOnlyEffect => "ReadOnlyEffect"
    RequestBranchUnavailable => "RequestBranchUnavailable"
  }
}

///|
// All new Request/body aliases leave this frame before its issuer closes the
// physical payload. Metadata belongs to its separately retained original Read.
fn native_mock_readme_request_payload(
  facility : NativeMockReadmeRequestFacility,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  document : String,
  original : LocalProjectMockDeclarations,
  effect_compilation : Bool,
  effect_source_inputs : Bool,
  content_join : Bool,
  check_policy? : Bool = false,
  authored_predicate? : Bool = false,
  effect_result_source? : Bool = false,
  effect_recipe? : Bool = false,
  effect_material_restore? : Bool = false,
  effect_prepared_restore? : Bool = false,
) -> String? raise {
  facility.arena.enter_domain_retained_execution(facility.physical).unwrap()
  let wire : Json = {
    "kind": "aql",
    "input": { "text": Json::string(document), "format": "aql-text" },
    "parameters": null,
  }
  let wire = local_project_mock_relation_wire(wire).unwrap()
  let intent = @run_host.prepare_client_submitted_intent(wire, 65536, 8192, 64).unwrap()
  let verified = Ref(0)
  let declined = Ref(0)
  let result = @local_host.prepare_native_client_submitted_request_input(
    facility.parent,
    facility.input,
    intent,
    environment,
    publication,
    verify_request_value_policy=if check_policy {
      Some(subject => {
        // This is the original Host callback, before the first compilation or
        // body borrow. Failed phase observation cannot construct a new body.
        assert_true(
          @local_values.borrow_request_effect_plan_input(
            facility.parent,
            facility.input,
          )
          is Err(_),
        ) catch {
          _ => return None
        }
        verified.val += 1
        assert_true(
          original.verify_static_request_policy(
            explain_fixture_environment(),
            subject,
          )
          is None,
        ) catch {
          _ => return None
        }
        let copied = @json.parse(subject) catch { _ => return None }
        if copied is Object(fields) &&
          fields.get("request") is Some(Object(values)) &&
          fields.get("origins") is Some(Object(origins)) &&
          values.contains("paths") {
          values["paths"] = Json::array([Json::string("private-selector")])
          assert_true(
            original.verify_static_request_policy(
              environment,
              local_project_mock_relation_wire(copied).unwrap(),
            )
            is None,
          ) catch {
            _ => return None
          }
          values["paths"] = Json::null()
          origins["paths"] = (
            { "origin": "supplied", "parameter": "selector" } : Json)
          assert_true(
            original.verify_static_request_policy(
              environment,
              local_project_mock_relation_wire(copied).unwrap(),
            )
            is None,
          ) catch {
            _ => return None
          }
        }
        let policy = original.verify_static_request_policy(environment, subject)
        if policy is None {
          declined.val += 1
        }
        policy
      })
    } else {
      None
    },
  )
  let issue = match result {
    Err(issue) => Some(native_mock_readme_request_issue(issue))
    Ok((preparation, borrow)) => {
      assert_eq(
        @local_host.native_client_submitted_preparation_intent_cid(preparation),
        @run_host.client_submitted_intent_cid(intent),
      )
      let mut body_returned = false
      let branch = match
        @local_host.native_client_submitted_preparation(preparation) {
        EffectComputation(prepared) => {
          let candidate = @run_host.prepared_client_effect_computation_candidate(
            prepared,
          )
          let headers = @checked.effect_program_static_headers(candidate)
          assert_eq(@syntax.effect_header_count(headers), 1)
          assert_eq(
            @syntax.effect_header_kind(
              @syntax.effect_header_at(headers, 0).unwrap(),
            ),
            "update",
          )
          if effect_compilation {
            let assets = @run_host.client_local_product_assets()
            let contracts = @local_values.prepare_installed_sequence_contracts(
              assets.registry,
              assets.values,
              Some(assets.fragment),
              assets.ordered,
            ).unwrap()
            try {
              let models = match
                original.prepare_effect_models(
                  facility.parent,
                  facility.input,
                  @run_host.prepared_client_effect_infer_occurrences(prepared).unwrap(),
                  environment,
                  contracts,
                ) {
                Ok(value) => value
                Err(issue) =>
                  stop(native_model_graph_test_cause(original, prepared, issue))
              }
              let infers = models.map(value => value.graph)
              if infers.length() != 1 {
                stop("LocalOriginalModelGraphCount")
              }
              if check_policy {
                assert_true(verified.val > 0)
                let graph = infers[0]
                let execution = @run_host.client_infer_plan_graph_execution_contract(
                  graph,
                )
                let region = @compiler_environment.model_task_region_at(
                  @compiler_environment.model_execution_task(execution),
                  0,
                ).unwrap()
                match
                  @run_host.admit_client_infer_occurrence_egress(
                    graph.occurrence,
                    execution,
                    () => {
                      Some({
                        classification: @compiler_environment.Public,
                        region,
                        provider_retention: false,
                        training_use: false,
                      })
                    },
                  ) {
                  Ok(_) if !authored_predicate => ()
                  Err(@run_host.UnknownClassification) if authored_predicate =>
                    ()
                  Ok(_) =>
                    fail(
                      "authored predicate must retain its unverified provenance",
                    )
                  Err(issue) =>
                    fail(
                      "original README egress: " +
                      @debug.to_string(issue) +
                      "; subjects=" +
                      verified.val.to_string() +
                      "; declined=" +
                      declined.val.to_string(),
                    )
                }
                assert_true(
                  @run_host.admit_client_infer_occurrence_egress(
                    graph.occurrence,
                    execution,
                    () => {
                      Some({
                        classification: @compiler_environment.Unknown,
                        region,
                        provider_retention: false,
                        training_use: false,
                      })
                    },
                  )
                  is Err(@run_host.UnknownClassification),
                )
              }
              let request = local_effect_request_identity(
                preparation,
                "sha256:" + "a".repeat(64),
                "original-readme-request",
              )
              let source_inputs = if effect_source_inputs {
                let direct = @run_host.select_client_effect_direct_acquisition_occurrences(
                  prepared, 1000000,
                ).unwrap()
                original.prepare_effect_sources(prepared, direct)
              } else {
                []
              }
              if effect_source_inputs {
                if source_inputs.length() != 2 {
                  stop("LocalOriginalSourceInputCount")
                }
                if !physical_equal(
                    source_inputs[0]._retained_source,
                    original.sources[0],
                  ) ||
                  !physical_equal(
                    source_inputs[1]._retained_source,
                    original.sources[1],
                  ) ||
                  !(source_inputs[0]._retained_reader is Rows(_)) ||
                  !(source_inputs[1]._retained_reader is Files(_, _)) ||
                  source_inputs[0]._retained_coordinates ==
                  source_inputs[1]._retained_coordinates {
                  stop("LocalOriginalSourceInputsChanged")
                }
              }
              let compiled = local_effect_first_compilation(
                preparation,
                "sha256:" + "a".repeat(64),
                "sha256:" + "b".repeat(64),
                "local-test",
                "original-readme-request",
                "2026-10-10T00:00:00.000Z",
                "2099-01-01T00:00:00.000Z",
                infers~,
                models~,
                request=Some(request),
                source_inputs~,
              )
              if !physical_equal(
                  @run_host.client_effect_compilation_owner(
                    compiled.allowed.compilation,
                  ),
                  prepared,
                ) {
                stop("LocalOriginalEffectCompilationChanged")
              }
              // The first compiler retains the exact early provider/bounds
              // selection. Later execution must not reselect either object.
              assert_true(physical_equal(compiled._retained_models, models))
              assert_true(
                compiled.model_compiled is Some(model_run) &&
                @run_host.check_client_compiled_run_definition(
                  model_run,
                  compiled.definition,
                )
                is Ok(_),
              )
              let saved_policies = if check_policy {
                Some(computation => {
                  local_saved_effect_request_value_policies(
                    computation,
                    @run_host.client_standard_program_preparation_limits().checking.compilation,
                    inventory => {
                      guard @execution.preparation_representation_cost(
                          inventory,
                        )
                        is Some(bytes) &&
                        bytes >= 0L else {
                        return Err(@run_host.RequestValuePolicyConstruction)
                      }
                      Ok(())
                    },
                    subject => {
                      original.verify_restored_static_request_policy(subject)
                    },
                  )
                })
              } else {
                None
              }
              if effect_material_restore {
                let wire = @run_host.client_effect_issued_normalization_materials_wire(
                  compiled.issued,
                )
                let read_with_policies = (candidate : String, reverify : Bool) => {
                  @run_host.admit_client_effect_run_materials(
                    candidate,
                    @publication.publication_contract_identity(
                      compiled.definition,
                    ),
                    { text_time: false, veca: false, },
                    {
                      rela: true,
                      sga: false,
                      tea: false,
                      calendar: false,
                      text_rank: false,
                    },
                    native_request_manifests,
                    {
                      preparation: @run_host.client_standard_program_preparation_limits(),
                      sequence: @run_host.client_standard_values_sequence_limits(),
                      max_sequence_steps: 1000,
                      max_sequence_work: 1000,
                      max_evidence_bytes: 65536,
                      max_evidence_nodes: 8192,
                      max_evidence_depth: 64,
                    },
                    @run_host.client_standard_effect_computation_limits(),
                    expected_request=Some(compiled.request),
                    request_value_policies=if reverify {
                      saved_policies
                    } else {
                      None
                    },
                  )
                }
                if check_policy {
                  assert_true(
                    read_with_policies(wire, false)
                    is Err(Normalization(UnverifiedOriginalMaterials)),
                  )
                }
                let read = (candidate : String) => {
                  read_with_policies(candidate, true)
                }
                let restored = match read(wire) {
                  Ok(value) => value
                  Err(Normalization(UnverifiedOriginalMaterials)) =>
                    fail("Original saved keyed Template did not restore")
                  Err(_) => fail("Original saved keyed materials refused")
                }
                assert_eq(
                  @publication.run_evidence_value_json(
                    @run_host.client_effect_compilation_template(
                      restored.compilation,
                    ),
                  ),
                  @publication.run_evidence_value_json(
                    @run_host.client_effect_compilation_template(
                      compiled.allowed.compilation,
                    ),
                  ),
                )
                assert_true(
                  @run_host.restore_client_effect_run_normalization(restored)
                  is Ok(_),
                )
                guard @json.parse(wire) is Object(fields) &&
                  fields["infer_native_read_profile_json"] is String(profile) else {
                  fail("Original selected native read profile was not retained")
                }
                let malformed = fields.copy()
                malformed["infer_native_read_profile_json"] = Json::number(1)
                assert_true(
                  read(
                    local_project_mock_relation_wire(Json::object(malformed)).unwrap(),
                  )
                  is Err(Input(MaterialsMalformed)),
                )
                let foreign = fields.copy()
                guard @json.parse(profile) is Object(profile_fields) else {
                  fail("Original Native read profile shape")
                }
                profile_fields.remove("transport_cid")
                profile_fields["source_view_contract_cid"] = Json::string(
                  "sha256:" + "0".repeat(64),
                )
                let changed = @publication.seal_publication_contract(
                  "native_file_content_read",
                  local_project_mock_relation_wire(Json::object(profile_fields)).unwrap(),
                  65536,
                  8192,
                  64,
                ).unwrap()
                foreign["infer_native_read_profile_json"] = Json::string(
                  @publication.publication_contract_json(changed),
                )
                assert_true(
                  read(
                    local_project_mock_relation_wire(Json::object(foreign)).unwrap(),
                  )
                  is Err(Input(MaterialsEvidence("infer_execution_contract"))),
                )
                let missing = fields.copy()
                missing.remove("infer_native_read_profile_json")
                assert_true(
                  read(
                    local_project_mock_relation_wire(Json::object(missing)).unwrap(),
                  )
                  is Err(Normalization(UnverifiedOriginalMaterials)),
                )
                // This isolated restored preparation has no Run borrowers.
                // Cut its existing custody back-references before the same
                // physical Request close checks that all aliases have left.
                @run_host.clear_prepared_client_effect_custody_after_cleanup(
                  restored.prepared,
                )
              }
              if effect_prepared_restore {
                let wire = @run_host.issue_client_effect_prepared_original(
                  compiled.allowed.compilation,
                ).unwrap()
                let restored = @run_host.admit_client_effect_prepared_original(
                  wire,
                  @publication.publication_contract_identity(
                    @run_host.client_effect_compilation_compiled_plan(
                      compiled.allowed.compilation,
                    ),
                  ),
                  { text_time: false, veca: false, },
                  {
                    rela: true,
                    sga: false,
                    tea: false,
                    calendar: false,
                    text_rank: false,
                  },
                  native_request_manifests,
                  {
                    preparation: @run_host.client_standard_program_preparation_limits(),
                    sequence: @run_host.client_standard_values_sequence_limits(),
                    max_sequence_steps: 1000,
                    max_sequence_work: 1000,
                    max_evidence_bytes: 65536,
                    max_evidence_nodes: 8192,
                    max_evidence_depth: 64,
                  },
                  @run_host.client_standard_effect_computation_limits(),
                  request_value_policies=saved_policies,
                ).unwrap()
                let compilation = @run_host.client_effect_prepared_original_compilation(
                  restored,
                )
                assert_true(
                  @run_host.issue_client_effect_prepared_original(compilation)
                  is Ok(same) &&
                  same == wire,
                )
                assert_eq(
                  @publication.run_evidence_value_json(
                    @run_host.client_effect_compilation_template(compilation),
                  ),
                  @publication.run_evidence_value_json(
                    @run_host.client_effect_compilation_template(
                      compiled.allowed.compilation,
                    ),
                  ),
                )
                @run_host.clear_prepared_client_effect_custody_after_cleanup(
                  @run_host.client_effect_prepared_original_prepared(restored),
                )
              }
              let selected = models[0]
              if effect_recipe {
                native_mock_readme_effect_recipe(
                  prepared,
                  original,
                  selected._retained_limits.identity.wire,
                )
              }
              if effect_result_source {
                // The exact original README, original typed Effect compiler
                // and checked Run supply both inventories. No fake Result,
                // Model completion or successful physical execution is issued.
                let bound = @run_host.bind_client_effect_compiled_run(
                  prepared,
                  compiled.allowed,
                  compiled.definition,
                ).unwrap()
                let checked = @run_host.prepared_client_effect_run_graph(bound)
                let graph = @strategy.checked_effect_run_graph(checked)
                assert_eq(@strategy.graph_task_count(graph), 6)
                assert_eq(@strategy.graph_result_task(graph, 0), Some(2))
                assert_eq(@strategy.checked_effect_run_source_count(checked), 1)
                let source = @strategy.checked_effect_run_source_at(checked, 0).unwrap()
                assert_eq(@strategy.checked_effect_source_task(source), 5)
                assert_true(
                  @strategy.graph_result_task(graph, 0) !=
                  Some(@strategy.checked_effect_source_task(source)),
                )
              }
              assert_true(physical_equal(selected.graph, infers[0]))
              assert_true(
                physical_equal(
                  selected._retained_profile,
                  original.model_profile.unwrap(),
                ),
              )
              assert_true(
                physical_equal(
                  selected._retained_provider,
                  original
                  .model_provider(
                    @run_host.client_infer_plan_graph_execution_contract(
                      selected.graph,
                    ),
                  )
                  .unwrap(),
                ),
              )
              assert_true(selected._retained_limits.model.max_items > 0)
              assert_true(selected._retained_limits.model.ledger.attempts > 0)
              if effect_source_inputs &&
                !physical_equal(compiled._retained_sources, source_inputs) {
                stop("LocalOriginalSourceInputsChanged")
              }
              if content_join {
                @local_host.return_native_client_submitted_request_body(borrow).unwrap()
                |> ignore
                body_returned = true
                native_mock_readme_content_join(
                  facility,
                  original,
                  prepared,
                  compiled,
                  contracts,
                  infers[0],
                )
              }
              None
            } catch {
              ClientStop(message) => Some(message)
              error => raise error
            }
          } else {
            None
          }
        }
        _ => Some("original README did not retain Effect computation")
      }
      if !body_returned {
        @local_host.return_native_client_submitted_request_body(borrow).unwrap()
        |> ignore
      }
      branch
    }
  }
  // Match the real command's first logical cleanup: it intentionally remains
  // pending until the SAME Native initializer reports physical retirement.
  // The actual close below still refuses live reservations or aliases.
  if facility.run is None {
    ignore(
      @local_values.abort_request_preparation_after_cleanup(facility.parent),
    )
  }
  facility.arena
  .leave_domain_retained_execution(facility.physical)
  .native_content_join_stage("leave same original Native Request frame")
  issue
}

///|
fn native_mock_readme_request_in_metadata_read(
  metadata : @initial_arena.InstalledArenaHost,
  read : @initial_arena.InstalledArenaOriginalRead,
  facility : NativeMockReadmeRequestFacility,
  effect_compilation? : Bool = false,
  effect_source_inputs? : Bool = false,
  content_join? : Bool = false,
  static_policy? : Bool = false,
  authored_predicate? : Bool = false,
  effect_result_source? : Bool = false,
  effect_recipe? : Bool = false,
  effect_material_restore? : Bool = false,
  effect_prepared_restore? : Bool = false,
) -> String? raise {
  let original = native_project_mock_model_fixture(
    if content_join {
      "deal-review"
    } else {
      "deal-review-missing"
    },
  )
  original.prepare_source_declarations().unwrap()
  // SAME selected Native file implementation, with the explicit immutable
  // authority metadata port already disclosed for this source component.
  original.file_sources = Some([
    local_project_mock_file_source(
      original.sources[1],
      "sha256:" + "8".repeat(64),
    ).unwrap(),
  ])
  // Exact metadata-only ports of the existing installation projection. This
  // does not qualify Runtime/Account observations or authorize any operation.
  original.write_installations = Some(
    local_project_mock_write_installations(
      original.sources[0],
      "sha256:" + "d".repeat(64),
      "sha256:" + "8".repeat(64),
    ).unwrap(),
  )
  original
  .prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    local_utc_now,
  )
  .unwrap()
  let source_environment = original
    .prepare_source_environment(explain_fixture_environment())
    .unwrap()
  let environment = original
    .prepare_model_environment(source_environment)
    .unwrap()
  let (publication, _) = original
    .prepare_source_publication(environment)
    .unwrap()
  let document = local_project_required_declaration(
    original._retained_project,
    Some("deal-review.aql"),
  ).unwrap()
  let document = if authored_predicate {
    let changed = document.replace(
      old="|> ASSERT UNIQUE BY (id)",
      new="WHERE TRUE\n|> ASSERT UNIQUE BY (id)",
    )
    assert_true(changed != document)
    changed
  } else {
    document
  }
  // The earlier cases intentionally omit payload data. The distinct joined
  // component selects the exact existing template with its fresh data file.
  metadata.leave_domain_original_read(read).unwrap()
  let issue = native_mock_readme_request_payload(
    facility,
    environment,
    publication,
    document,
    original,
    effect_compilation,
    effect_source_inputs,
    content_join,
    check_policy=static_policy,
    authored_predicate~,
    effect_result_source~,
    effect_recipe~,
    effect_material_restore~,
    effect_prepared_restore~,
  )
  facility.arena
  .close_domain_retained_execution(facility.physical)
  .native_content_join_stage("close same original Native Request frame")
  match facility.run {
    Some(run) => {
      @local_values.retire_installed_managed_run(run).native_content_join_stage(
        "same Run retirement after actual Native frame close",
      )
      facility.run = None
    }
    None =>
      @local_values.abort_request_preparation_after_cleanup(facility.parent).unwrap()
  }
  facility.arena
  .close_domain_after_owner_ack(facility.domain)
  .native_content_join_stage("close same original Native Request domain")
  facility.arena
  .try_close()
  .native_content_join_stage("close same original Native Request host")
  metadata.enter_domain_original_read(read).unwrap()
  original.retire_originals().unwrap() |> ignore
  issue
}

///|
test "Native README original Request verifies static policies before its first Model compilation" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    static_policy=true,
  )
}

///|
test "Native README Effect result source is distinct from its retained Model root" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    static_policy=true,
    effect_result_source=true,
  )
}

///|
test "Native README original Request retains Unknown for an authored TRUE predicate" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    static_policy=true,
    authored_predicate=true,
  )
}

///|
test "Native original whole README checks through the same retained Request and returns its original Effect body" {
  native_project_mock_model_backed_read(false, readme_request=true)
}

///|
fn native_mock_lookup_policy_in_original_read() -> Unit raise {
  let original = native_project_mock_model_fixture("deal-review-missing")
  defer original.retire()
  original.prepare_source_declarations().unwrap()
  assert_true(original.file_lookup_policy() is None)
  original.file_sources = Some([
    local_project_mock_file_source(
      original.sources[1],
      "sha256:" + "8".repeat(64),
    ).unwrap(),
  ])
  let selected = original.file_lookup_policy().unwrap()
  guard selected is Object(fields) else {
    fail("selected Native lookup policy")
  }
  let limits = @local_values.client_local_preparation_initial_limits(
    @local_values.client_local_resource_policy(),
  ).unwrap()
  assert_eq(
    fields.get("max_total_decoded_response_bytes"),
    Some(
      Json::number(
        Int64::min(limits.retained_bytes, limits.execution_bytes).to_double(),
      ),
    ),
  )
  assert_eq(
    fields.get("max_request_bytes_per_attempt"),
    Some(
      Json::number(local_project_mock_file_limits().page.max_bytes.to_double()),
    ),
  )
  assert_eq(
    fields.get("max_total_duration_ms"),
    Some(Json::number(local_project_mock_file_duration_ms().to_double())),
  )
  // An already selected Host policy remains exact, even if tighter. The
  // Source does not replace it with its implementation's default envelope.
  fields["max_total_duration_ms"] = Json::number(100)
  let base = explain_fixture_environment()
  let writer = @encode.writer(4000000, 400000, 64)
  @compiler_environment.emit(@checked.checking_environment_wire(base), writer)
  guard local_project_mock_json(@encode.finish(writer)) is Object(body) &&
    body.get("host_policy_profile") is Some(Object(policy)) else {
    fail("original Host policy")
  }
  policy["lookup_execution"] = selected
  ignore(body.remove("evidence_bundle_cid"))
  let preimage = local_project_mock_relation_wire(Json::object(body)).unwrap()
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
  body["evidence_bundle_cid"] = Json::string(cid)
  let supplied = local_admitted_check_environment(
    local_project_mock_relation_wire(Json::object(body)).unwrap(),
    cid,
  ).unwrap()
  let prepared = original.prepare_source_environment(supplied).unwrap()
  let out = @encode.writer(4000000, 400000, 64)
  @compiler_environment.emit(@checked.checking_environment_wire(prepared), out)
  guard local_project_mock_json(@encode.finish(out)) is Object(merged) &&
    merged.get("host_policy_profile") is Some(Object(actual)) else {
    fail("prepared Host policy")
  }
  assert_eq(actual.get("lookup_execution"), Some(selected))
  original.retire_originals().unwrap() |> ignore
  assert_true(original.file_lookup_policy() is None)
}

///|
test "Native Mock lookup policy requires selected file originals and preserves explicit Host bounds" {
  native_project_mock_model_backed_read(false, lookup_policy=true)
}

///|
test "Native original whole README compiles its first Effect Task with the same funded Request Model Graph" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
  )
}

///|
test "Native original whole README retains its two distinct checked Source readers before first Effect Task" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
  )
}

///|
test "Native README first compiler retains the same prepared Model provider profile and bounds" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
  )
}

///|
test "Native Model selection backs all three simultaneous original vectors" {
  // Bounds (20H/32R/78W), Work including its publication snapshot
  // (12H/55R/19W, including lookup-entry and retained review controls), and its four-reference
  // selection holder are per occurrence. The first occurrence also retains
  // the compiled view (4H/12R/3W) and THREE growing vectors: selected Models,
  // compiler Graph arguments, and business.model_work. Two occurrences give
  // six vector elements; the shared Array convention gives 9H/57R/6W.
  let later = native_mock_effect_model_selection_storage(0)
  assert_eq(later.record_headers, 33L)
  assert_eq(later.reference_slots, 91L)
  assert_eq(later.scalar_words, 97L)
  let first = native_mock_effect_model_selection_storage(2)
  assert_eq(first.record_headers, 46L)
  assert_eq(first.reference_slots, 160L)
  assert_eq(first.scalar_words, 106L)
  assert_eq(first.owned_utf16_units, 0L)
  assert_eq(first.owned_wire_bytes, 0L)
}

///|
// Bounded authored-source diagnosis after the actual Native caller refused.
// Read only immutable original identities, not application values or state.
// Return through its existing ClientStop catch so normal physical cleanup runs.
fn native_model_graph_test_cause(
  original : LocalProjectMockDeclarations,
  prepared : @run_host.PreparedClientEffectComputation,
  issue : @local_values.ClientRequestProgramPlanIssue,
) -> String {
  let fallback = command_preparation_cleanup_cause(
    CommandBusinessModelGraph(issue),
  )
  guard issue is @local_values.ModelGraph(@run_host.ForeignExecution) &&
    @run_host.prepared_client_effect_infer_occurrence(prepared)
    is Some(occurrence) &&
    original.models.length() == 1 &&
    original.models[0].execution is Some(execution) &&
    @test_lower.node_at(
      @test_lower.bound_preparation(occurrence.preparation),
      occurrence.step,
    )
    is Some(node) &&
    @test_lower.payload(node) is @test_lower.Infer(infer) else {
    return fallback
  }
  if !physical_equal(
      @test_infer.model_task(infer),
      @compiler_environment.model_execution_task(execution),
    ) {
    return "NativeModelGraphOriginalTaskMismatch"
  }
  guard @run_host.select_client_effect_model_keyed_acquisition(
      prepared, occurrence,
    )
    is Ok(Some(keyed)) &&
    @run_host.client_keyed_acquisition_source_evidence_facts(keyed)
    is Some(facts) &&
    original.file_sources is Some(files) else {
    return "NativeModelGraphOriginalKeyedMissing"
  }
  let binding = @run_host.client_keyed_acquisition_binding(keyed)
  if @compiler_environment.lookup_execution_policy(
      @sourceviews.lookup_bounds_policy(binding.bounds),
    )
    is None {
    return "NativeModelGraphOriginalLookupPolicyMissing"
  }
  let selected = @sourceviews.keyed_request_input(
    @sourceviews.parameterized_keyed_request(
      @sourceviews.keyed_join_request(binding.join),
    ),
  )
  let request = @compiler_environment.contract_identity(
      @compiler_environment.reference_contract(
        @compiler_environment.source_request_reference(
          @sourceviews.selected_contract(selected),
        ),
      ),
    ).2
  for file in files {
    for pair in file._retained_listings {
      let reader = pair.1
      if reader.content.source_ref == facts.source_ref &&
        reader.content.view_cid == facts.source_view_contract_cid {
        guard @publication.native_file_read_profile_contract_bindings(
            reader._retained_read_profile.contract(),
          )
          is Some((source, request_schema, response)) else {
          return "NativeModelGraphProfileKind"
        }
        if source != facts.source_view_contract_cid {
          return "NativeModelGraphProfileSource"
        }
        if request_schema != request {
          return "NativeModelGraphProfileRequestSchema"
        }
        if response != facts.carrier_schema_contract_cid {
          return "NativeModelGraphProfileResponseSchema"
        }
        guard @test_planning.keyed_source_evidence_members(
            @run_host.client_keyed_acquisition_facts(keyed),
          )
          is Ok(members) &&
          @compiler_environment.connector_source_evidence_supports(members, [
            @publication.publication_contract_identity(
              reader._retained_read_profile.contract(),
            ),
          ]) else {
          return "NativeModelGraphProfileUndeclared"
        }
        return "NativeModelGraphOriginalProfileMatched"
      }
    }
  }
  "NativeModelGraphOriginalProfileMissing"
}

///|
// Actual checked README selection and original file provider, with the finite
// Product's existing 1MiB private-record setting. These are constructor DATA,
// not a completed input inventory or authority to execute a physical row.
fn native_mock_readme_effect_recipe(
  prepared : @run_host.PreparedClientEffectComputation,
  original : LocalProjectMockDeclarations,
  wire : @execution.RowWireLimits,
) -> Unit raise {
  let installation = original.write_installations.unwrap()[0]
  let binding = installation._retained_source._retained_rows
    .iter()
    .find_first(value => {
      value.view.resource == installation.write.mapping.resource
    })
    .unwrap()
  let physical = @row_file.native_relation_file_target_io_capacity(
    binding.provider,
    installation.write.mapping.write_fields.length(),
  ).unwrap()
  let request = native_mock_effect_request_bytes(
    wire,
    binding.limits.page.max_bytes,
    installation.binding,
    installation.write.mapping.mapping_cid,
  ).unwrap()
  assert_true(request > 2 * wire.max_bytes + binding.limits.page.max_bytes)
  let codec = @local_host.native_client_effect_storage_limits()
  assert_eq(codec.ledger.max_wire_bytes, 65536)
  assert_eq(codec.ledger.max_nodes, 128)
  assert_eq(codec.ledger.max_depth, 16)
  assert_eq(codec.receipt.max_wire_bytes, 65536)
  assert_eq(codec.receipt.max_nodes, 4096)
  assert_eq(codec.receipt.max_depth, 64)
  assert_eq(codec.response_bytes, 1048576)
  let quantities = native_mock_effect_recipe_capacities(
    wire, 1048576, request, physical,
  ).unwrap()
  assert_eq(quantities.length(), 6)
  assert_true(physical_equal(quantities[3], physical))
  let control_r = @execution.execution_capacity_retained_bytes(quantities[4])
  let control_e = @execution.execution_capacity_execution_bytes(quantities[4])
  // Frozen d414's pre-inventory Ledger observation, before any member record:
  // held=60922084, reserved R=223729857/E=303631383. This regression checks
  // ONLY the two-row control growth that failed there; the unchanged 512MiB
  // facility and later capture/physical lifetimes still require runtime proof.
  assert_true(60922084L + 223729857L + 13936L + 2L * control_r < 536870912L)
  assert_true(60922084L + 303631383L + 33936L + 2L * control_e < 536870912L)
  // Raw response Bytes remain two simultaneous full original buffers.
  assert_true(control_r >= 2L * codec.response_bytes.to_int64())
  assert_true(control_e >= control_r)
  if @env.get_env_var("ACTQL_TEST_NATIVE_IMPORT_QUOTE") == Some("1") {
    let (imports, maximum) = native_mock_effect_import_construction(
      prepared, wire,
    )
    assert_true(
      @execution.execution_capacity_retained_bytes(maximum) >
      @execution.execution_capacity_retained_bytes(imports),
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(maximum) > 536870912L,
    )
    let initial_recipe = quantities.copy()
    initial_recipe[0] = imports
    initial_recipe[1] = @execution.execution_capacity(0L, 0L).unwrap()
    let maximum_recipe = quantities.copy()
    maximum_recipe[0] = @execution.add_execution_capacity(
      quantities[0],
      maximum,
    ).unwrap()
    assert_true(
      @local_values.prepare_installed_effect_staged_extent(
        @local_values.prepare_installed_effect_capture_recipe_extent(
          "native.mock.file.capture", initial_recipe,
        ).unwrap(),
        @local_values.prepare_installed_effect_capture_recipe_extent(
          "native.mock.file.capture", maximum_recipe,
        ).unwrap(),
      )
      is Ok(_),
    )
    println(
      "Initial imports R=" +
      @execution.execution_capacity_retained_bytes(imports).to_string() +
      ",E=" +
      @execution.execution_capacity_execution_bytes(imports).to_string(),
    )
    println(
      "Base fixed E=" +
      @execution.execution_capacity_execution_bytes(quantities[0]).to_string() +
      ",per-row E=" +
      @execution.execution_capacity_execution_bytes(quantities[1]).to_string(),
    )
    let capture_r = @execution.execution_capacity_retained_bytes(
        initial_recipe[0],
      ) +
      2L * @execution.execution_capacity_retained_bytes(initial_recipe[1])
    let capture_e = @execution.execution_capacity_execution_bytes(
        initial_recipe[0],
      ) +
      2L * @execution.execution_capacity_execution_bytes(initial_recipe[1])
    println(
      "Original import/capture quote R=" +
      capture_r.to_string() +
      ",E=" +
      capture_e.to_string(),
    )
    if 60922084L + 223729857L + 13936L + 2L * control_r + capture_r >=
      536870912L ||
      60922084L + 303631383L + 33936L + 2L * control_e + capture_e >= 536870912L {
      fail(
        "Actual Native import/capture constructor does not fit beside the original frozen pre-capture Ledger",
      )
    }
  }
}

///|
test "Native README Effect recipe uses its selected row and original storage codecs" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    static_policy=true,
    effect_recipe=true,
  )
}

///|
test "Native original two-row staged import construction fits its unchanged facility" {
  assert_eq(@env.get_env_var("ACTQL_TEST_NATIVE_IMPORT_QUOTE"), Some("1"))
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    static_policy=true,
    effect_recipe=true,
  )
}

///|
test "Native README saved keyed Model Effect restores the exact original first Template" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    static_policy=true,
    effect_material_restore=true,
  )
}

///|
test "Native README held keyed Model Effect restores its exact prepared-original material" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    static_policy=true,
    effect_prepared_restore=true,
  )
}

///|
// Exact authored numeric caller, on the existing Request and original Mock
// declaration. This diagnoses route/graph selection only: no Source payload,
// Journal, Account, Run admission or physical Start is supplied here.
fn[T, E] Result::native_file_route_value(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail("Native File Source diagnostic: " + stage)
  }
}

///|
fn native_pure_file_request_payload(
  facility : NativeMockReadmeRequestFacility,
  original : LocalProjectMockDeclarations,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  prepare_plan~ : Bool,
  prepared_control~ : Bool,
  boundary? : Bool = false,
  budget_refusal? : Bool = false,
) -> String? raise {
  facility.arena
  .enter_domain_retained_execution(facility.physical)
  .native_file_route_value("enter original Request")
  let document = if boundary {
    let document = @files.read_bounded_text_file(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
      "native-file-task-boundary.json",
      65536L,
      trim_newline=false,
    ).unwrap()
    assert_eq(
      @sha.hex(@utf8.encode(document)),
      "b51302160d745487db7a27ba8d17eb6a0e46eb70562838caaff13da583bdaa9b",
    )
    document
  } else {
    "SELECT SUM(CASE WHEN trend = 'down' THEN 4 ELSE 12 END) AS total, AVG(CASE WHEN trend = 'down' THEN 4 ELSE 12 END) AS average FROM snowflake.usage_30d"
  }
  let intent = @run_host.prepare_client_submitted_intent(
    local_project_mock_relation_wire({
      "kind": "aql",
      "input": {
        "text": Json::string(document),
        "format": if boundary {
          "json"
        } else {
          "sql"
        },
      },
      "parameters": null,
    }).unwrap(),
    65536,
    8192,
    64,
  ).native_file_route_value("authored intent")
  let issue = match
    @local_host.prepare_native_client_submitted_request_input(
      facility.parent,
      facility.input,
      intent,
      environment,
      publication,
      verify_request_value_policy=Some(subject => {
        original.verify_static_request_policy(environment, subject)
      }),
    ) {
    Err(issue) => Some(native_mock_readme_request_issue(issue))
    Ok((preparation, borrow)) => {
      let mut whole : (
        @run_host.PreparedClientProgram,
        @run_host.ClientRequestIdentity,
        @local_values.ClientInstalledWholeSourceCapacity,
        @row_host.RowDeclaration,
        Int64,
        @run_host.ClientRunCompilation,
      )? = None
      let issue = match
        @local_host.native_client_submitted_preparation(preparation) {
        Computation(prepared) => {
          assert_eq(@run_host.prepared_client_acquisition_count(prepared), 1)
          assert_true(
            @run_host.prepared_client_composed_infer_occurrences(prepared)
            .unwrap()
            .is_empty(),
          )
          let request = @run_host.prepare_source_free_client_request_identity(
            prepared,
            "sha256:" + "8".repeat(64),
            "native-numeric-file-component",
          ).native_file_route_value("original Request identity")
          let selected = @local_values.select_installed_source_input(
            prepared, request, 0, 0,
          ).native_file_route_value("select actual acquisition route")
          let graph = @run_host.prepared_client_graph(prepared)
          if boundary {
            assert_eq(@strategy.graph_task_count(graph), 33)
            assert_eq(@strategy.graph_captured_prefix(graph), 1)
            assert_eq(@strategy.graph_result_task(graph, 0), Some(32))
          }
          let route = match selected {
            @sourceviews.QueryRoute(_) => "query"
            @sourceviews.WholeInputRoute(_) => "whole-input"
          }
          let mut plan_issue = None
          if prepare_plan {
            guard selected is @sourceviews.WholeInputRoute(source) else {
              fail("actual authored aggregate must retain its Whole input")
            }
            let outcome = Ok(
              native_pure_file_capture_plan(
                facility, original, prepared, request, source,
              ),
            ) catch {
              ClientStop(message) => Err(message)
              error => raise error
            }
            match outcome {
              Ok((capacity, declaration, transport, artifact)) =>
                whole = Some(
                  (
                    prepared, request, capacity, declaration, transport, artifact,
                  ),
                )
              Err(message) => plan_issue = Some(message)
            }
          }
          println(
            "Native numeric Source: tasks=" +
            @strategy.graph_task_count(graph).to_string() +
            ",captured=" +
            @strategy.graph_captured_prefix(graph).to_string() +
            ",route=" +
            route,
          )
          plan_issue
        }
        EffectComputation(_) => Some("numeric File Source must remain Pure")
      }
      @local_host.return_native_client_submitted_request_body(borrow).native_file_route_value(
        "return original body",
      )
      |> ignore
      if whole
        is Some((prepared, request, capacity, declaration, transport, artifact)) {
        let owner = @local_values.begin_request_capture_managed_run(
          facility.parent,
          request,
        ).native_file_route_value("adopt SAME Whole Plan")
        facility.run = Some(owner)
        assert_true(
          physical_equal(
            @local_values.installed_managed_run_compilation_original(
              owner, prepared,
            ).unwrap(),
            artifact,
          ),
        )
        let physical = facility.arena
          .borrow_domain_retained_execution_ledger(facility.physical)
          .native_file_route_value("observe original physical Ledger")
        let usage = @initial_resources.ledger_usage(physical)
        if budget_refusal {
          let admission = @local_values.installed_managed_preparation_admission_original(
            owner, prepared, request,
          ).unwrap()
          let original_extent = @initial_resources.prepared_run_native_capacity(
            admission, prepared, physical,
          ).unwrap()
          let limit = @initial_resources.ledger_limits(physical)
          // Request one byte beyond THIS original finite allowance. Refusal
          // cannot change its debit, identity, work history or cleanup duties.
          assert_true(
            @initial_resources.reserve_prepared_run_native_work_capacity(
              admission,
              prepared,
              physical,
              limit.retained_bytes + 1L,
              original_extent.1,
            )
            is Err(
              @initial_resources.Resource(@initial_resources.RetentionLimit)
            ),
          )
          assert_eq(@initial_resources.ledger_usage(physical), usage)
          assert_eq(
            @initial_resources.prepared_run_native_capacity(
              admission, prepared, physical,
            ).unwrap(),
            original_extent,
          )
        }
        println(
          "Native Whole Plan physical Ledger before Source: reservations=\{usage.live_reservations},R=\{usage.reserved_retention_bytes},E=\{usage.reserved_execution_bytes}",
        )
        if prepared_control {
          let before_quote = @initial_resources.ledger_usage(physical)
          let (physical_graph, _, _, _) = @local_values.installed_managed_capture_publication_geometry_original(
            owner, prepared, request,
          ).unwrap()
          let selected = original.sources
            .iter()
            .find_first(source => {
              physical_equal(source._retained_declaration, declaration)
            })
            .unwrap()
          let resource = @row_host.row_input_acquisition_target_resource(
            @local_values.installed_whole_source_acquisition(capacity),
          )
          let row = selected._retained_rows
            .iter()
            .find_first(row => row.view.resource == resource)
            .unwrap()
          assert_eq(row._retained_selection.items_path.length(), 3)
          assert_eq(row._retained_selection.key_path.unwrap().length(), 3)
          assert_eq(row.limits.page.max_bytes, 1048576)
          // Keep the standalone diagnostic's 64 KiB refusal. This managed
          // quote instead binds the actual original provider and Whole Plan.
          assert_true(
            @local_host.native_relation_file_entry_read_capacity(
              row._retained_selection,
              row.limits,
            )
            is None,
          )
          let quoted = @local_host.native_relation_whole_file_entry_read_capacity(
            row._retained_selection,
            row.limits,
            row.provider,
            physical_graph,
          ).unwrap()
          let tasks = @strategy.graph_task_count(physical_graph).to_int64()
          let ports = @strategy.graph_data_count(physical_graph).to_int64()
          let task_loop = (16L + 12L * tasks + 2L * ports) * 16L +
            (32L + 16L * tasks + 4L * ports) * 8L +
            (8L + 4L * tasks + ports) * 8L
          // Independent 3+3-path vector: entry30146 + Work48234 + clock4274
          // + prepared-provider119696 + fixed Whole wrappers704 + task loop.
          assert_eq(
            @execution.execution_capacity_retained_bytes(quoted),
            203054L + task_loop,
          )
          assert_eq(
            @execution.execution_capacity_execution_bytes(quoted),
            203054L + task_loop,
          )
          assert_eq(@initial_resources.ledger_usage(physical), before_quote)
          let admission = @local_values.installed_managed_preparation_admission_original(
            owner, prepared, request,
          ).unwrap()
          // Finite component constructor DATA, not a normal Native Work quote
          // or physical entry grant. Grow the SAME body, never a second token.
          let (r, e) = @initial_resources.prepared_run_native_capacity(
            admission, prepared, physical,
          ).native_file_route_value("observe original Native body extent")
          let before = @initial_resources.ledger_usage(physical)
          assert_eq(r, before.reserved_retention_bytes)
          assert_eq(e, before.reserved_execution_bytes)
          assert_eq(@initial_resources.ledger_usage(physical), before)
          @initial_resources.reserve_prepared_run_native_work_capacity(
            admission,
            prepared,
            physical,
            r + 2048L,
            e + 2048L,
          ).native_file_route_value(
            "back component constructor on SAME original body",
          )
          assert_true(
            @initial_resources.prepared_run_usage_isolated(admission, physical),
          )
          let after = @initial_resources.ledger_usage(physical)
          assert_eq(after.live_reservations, usage.live_reservations)
          assert_eq(after.reserved_retention_bytes, r + 2048L)
          assert_eq(after.reserved_execution_bytes, e + 2048L)
          assert_eq(after.attempts, usage.attempts)
          assert_eq(after.planning_work, usage.planning_work)
          assert_true(after.peak_retention_bytes >= usage.peak_retention_bytes)
        }
        let (read, source, acquisition, actual) = @local_values.begin_installed_managed_whole_source_read(
          owner, prepared, request, declaration,
        ).native_file_route_value("retain SAME Whole read without starting it")
        assert_true(physical_equal(actual, capacity))
        assert_true(
          @row_host.row_input_acquisition_matches_source(acquisition, source),
        )
        let admitted = @local_values.installed_managed_whole_source_ledger(
          owner, prepared, request, capacity, transport, transport,
        ).native_file_route_value("observe SAME admitted Whole Ledger")
        assert_true(physical_equal(admitted, physical))
        @local_values.retire_installed_source_read(read).native_file_route_value(
          "retire unstarted original Whole read",
        )
        match @local_values.retire_installed_managed_run(owner) {
          Err(@local_values.Resource(@initial_resources.Unavailable)) => ()
          Err(_) => fail("unexpected original Whole Run retirement refusal")
          Ok(_) => fail("Core cannot ACK a still-entered Native Request frame")
        }
      }
      issue
    }
  }
  if facility.run is None {
    ignore(
      @local_values.abort_request_preparation_after_cleanup(facility.parent),
    )
  }
  facility.arena
  .leave_domain_retained_execution(facility.physical)
  .native_file_route_value("leave original Request")
  issue
}

///|
fn native_pure_file_request_in_metadata_read(
  metadata : @initial_arena.InstalledArenaHost,
  read : @initial_arena.InstalledArenaOriginalRead,
  facility : NativeMockReadmeRequestFacility,
  prepare_plan? : Bool = false,
  prepared_control? : Bool = false,
  boundary? : Bool = false,
  budget_refusal? : Bool = false,
) -> String? raise {
  let original = native_project_mock_model_fixture("churn-risk")
  original
  .prepare_source_declarations()
  .native_file_route_value("prepare original declarations")
  // The ordinary Project publishes the same combined Source/Model environment
  // even for a Pure non-INFER query. Preserve that existing metadata path.
  original
  .prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    local_utc_now,
  )
  .native_file_route_value("prepare original Model metadata")
  let source_environment = original
    .prepare_source_environment(explain_fixture_environment())
    .native_file_route_value("prepare original Environment")
  let environment = original
    .prepare_model_environment(source_environment)
    .native_file_route_value("prepare original combined Environment")
  let (publication, _) = original
    .prepare_source_publication(environment)
    .native_file_route_value("prepare original publication")
  metadata
  .leave_domain_original_read(read)
  .native_file_route_value("leave metadata Read")
  let issue = native_pure_file_request_payload(
    facility,
    original,
    environment,
    publication,
    prepare_plan~,
    prepared_control~,
    boundary~,
    budget_refusal~,
  )
  facility.arena
  .close_domain_retained_execution(facility.physical)
  .native_file_route_value("close original Request execution")
  match facility.run {
    Some(owner) => {
      @local_values.retire_installed_managed_run(owner).native_file_route_value(
        "retire SAME Whole Run after actual frame close",
      )
      facility.run = None
    }
    None =>
      @local_values.abort_request_preparation_after_cleanup(facility.parent).native_file_route_value(
        "retire original Request payload",
      )
  }
  facility.arena
  .close_domain_after_owner_ack(facility.domain)
  .native_file_route_value("close original Request domain")
  facility.arena
  .try_close()
  .native_file_route_value("close original Request arena")
  metadata
  .enter_domain_original_read(read)
  .native_file_route_value("reenter metadata Read")
  original
  .retire_originals()
  .native_file_route_value("retire original declarations")
  |> ignore
  issue
}

///|
test "Native numeric File Source keeps its actual Pure Request and acquisition route" {
  native_project_mock_model_backed_read(false, pure_file_source=true)
}

///|
fn native_pure_file_capture_plan(
  facility : NativeMockReadmeRequestFacility,
  original : LocalProjectMockDeclarations,
  prepared : @run_host.PreparedClientProgram,
  request : @run_host.ClientRequestIdentity,
  source : @sourceviews.SourceAcquisition,
) -> (
  @local_values.ClientInstalledWholeSourceCapacity,
  @row_host.RowDeclaration,
  Int64,
  @run_host.ClientRunCompilation,
) raise {
  let subject = @sourceviews.declaration(
    @sourceviews.mode_input(@sourceviews.source_acquisition_mode(source)),
  )
  let selected = original.sources
    .iter()
    .find_first(value => {
      value._retained_connection == subject.connector &&
      value._retained_declaration.views.any(view => {
        view.resource == subject.resource
      })
    })
    .unwrap()
  let row = selected._retained_rows
    .iter()
    .find_first(row => row.view.resource == subject.resource)
    .unwrap()
  // Native intake already returned this SAME reserved Plan-input borrower.
  // A second reserve is WrongPhase; do not duplicate the original phase.
  let assets = @run_host.client_local_product_assets()
  let contracts = @local_values.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).native_file_route_value("retain original installed contracts")
  let limits = @local_values.request_program_compilation_limits(
    facility.parent,
    facility.input,
  ).native_file_route_value("retain original compiler limits")
  let artifact = @local_values.prepare_request_program_compilation(
    facility.parent,
    facility.input,
    contracts,
    manifests=native_request_manifests,
    compilation_limits=limits,
    retained_output=false,
    provider_factory=native_request_provider_factory,
  ).native_file_route_value("compile original Source Program once")
  let transport = row.limits.page.max_bytes.to_int64()
  // Exercise the actual CLI module constructor, preserving its SAME original
  // parent/input/assets and the already compiled artifact above. This remains
  // a physical Request component, not Journal/Source IO/normal acceptance.
  let capacity = prepare_local_native_whole_file_request_module(
    facility.parent,
    facility.input,
    prepared,
    request,
    selected._retained_declaration,
    row,
    contracts,
    assets,
  )
  (capacity, selected._retained_declaration, transport, artifact)
}

///|
test "Native File Source adopts its actual Whole Plan on the same backed Request" {
  native_project_mock_model_backed_read(false, pure_file_plan=true)
}

///|
test "Native Whole Plan retains constructor capacity on its SAME preparation reservation" {
  native_project_mock_model_backed_read(false, pure_file_control=true)
}

///|
test "Native thirty three task File Plan keeps its same finite Request and physical Ledger" {
  native_project_mock_model_backed_read(false, pure_file_boundary=true)
}

///|
test "Native thirty three task File Plan refuses unfunded growth without changing its original cleanup" {
  native_project_mock_model_backed_read(
    false,
    pure_file_boundary=true,
    pure_file_budget_refusal=true,
  )
}
