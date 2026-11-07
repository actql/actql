///|
// Actual retained Native Request facility. The producer token is component
// DATA; no Account, Journal, Runtime/Host authority or durable Run is supplied.
priv struct NativeMockReadmeRequestFacility {
  arena : @initial_arena.InstalledArenaHost
  domain : @initial_arena.InstalledArenaDomain
  physical : @initial_arena.InstalledArenaRetainedExecution
  parent : @local_values.ClientRequestPreparation[Array[Int]]
  input : Array[Int]
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
  { arena, domain, physical, parent, input, }
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
) -> String? raise {
  facility.arena.enter_domain_retained_execution(facility.physical).unwrap()
  let wire : Json = {
    "kind": "aql",
    "input": { "text": Json::string(document), "format": "aql-text" },
    "parameters": null,
  }
  let wire = local_project_mock_relation_wire(wire).unwrap()
  let intent = @run_host.prepare_client_submitted_intent(wire, 65536, 8192, 64).unwrap()
  let result = @local_host.prepare_native_client_submitted_request_input(
    facility.parent,
    facility.input,
    intent,
    environment,
    publication,
  )
  let issue = match result {
    Err(issue) => Some(native_mock_readme_request_issue(issue))
    Ok((preparation, borrow)) => {
      assert_eq(
        @local_host.native_client_submitted_preparation_intent_cid(preparation),
        @run_host.client_submitted_intent_cid(intent),
      )
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
              let infers = original.prepare_effect_graphs(
                facility.parent,
                facility.input,
                prepared,
                environment,
                contracts,
              )
              if infers.length() != 1 {
                stop("LocalOriginalModelGraphCount")
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
              )
              if !physical_equal(
                  @run_host.client_effect_compilation_owner(
                    compiled.allowed.compilation,
                  ),
                  prepared,
                ) {
                stop("LocalOriginalEffectCompilationChanged")
              }
              None
            } catch {
              ClientStop(message) => Some(message)
            }
          } else {
            None
          }
        }
        _ => Some("original README did not retain Effect computation")
      }
      @local_host.return_native_client_submitted_request_body(borrow).unwrap()
      |> ignore
      branch
    }
  }
  // Match the real command's first logical cleanup: it intentionally remains
  // pending until the SAME Native initializer reports physical retirement.
  // The actual close below still refuses live reservations or aliases.
  ignore(@local_values.abort_request_preparation_after_cleanup(facility.parent))
  facility.arena.leave_domain_retained_execution(facility.physical).unwrap()
  issue
}

///|
fn native_mock_readme_request_in_metadata_read(
  metadata : @initial_arena.InstalledArenaHost,
  read : @initial_arena.InstalledArenaOriginalRead,
  facility : NativeMockReadmeRequestFacility,
  effect_compilation? : Bool = false,
) -> String? raise {
  let original = native_project_mock_model_fixture("deal-review-missing")
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
  // No payload data.json exists. This is the unchanged complete authored
  // query through actual funded Native intake/check/compile, not execution.
  metadata.leave_domain_original_read(read).unwrap()
  let issue = native_mock_readme_request_payload(
    facility, environment, publication, document, original, effect_compilation,
  )
  facility.arena.close_domain_retained_execution(facility.physical).unwrap()
  @local_values.abort_request_preparation_after_cleanup(facility.parent).unwrap()
  facility.arena.close_domain_after_owner_ack(facility.domain).unwrap()
  facility.arena.try_close().unwrap()
  metadata.enter_domain_original_read(read).unwrap()
  original.retire_originals().unwrap() |> ignore
  issue
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
