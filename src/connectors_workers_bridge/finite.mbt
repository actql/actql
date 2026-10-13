///|
/// Thin trusted assembly for one source-free task. Every checked Program,
/// compilation, admission, capacity and completion remains with its existing
/// Owner. This initial installation profile is not a language restriction.
pub(all) suberror WorkersFiniteFailure {
  InvalidInstallation
  UnsupportedProfile
  Preparation(@publication_host.ClientProgramPreparationIssue)
  Compilation(@publication_host.ClientValuesCompilationIssue)
  Binding(@publication_host.ClientValuesRunBindingIssue)
  Sequence(@publication_host.ClientTaskSequenceIssue)
  Registry(@execution.RegistryIssue)
  Ledger(@resources.LedgerIssue)
  Run(@strategy.RunIssue)
  Local(@binding15.LocalDispatchIssue)
  Search(@strategy.SearchIssue)
  Host(@host_driver.ComputeHostIssue[@strategy.RunIssue])
}

///|
#export_name("workersFiniteEnvironment")
pub fn workers_finite_environment(
  wire : String,
  cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
) -> @checked.CheckEnvironment raise WorkersFiniteFailure {
  match
    @publication_host.admit_client_check_environment(
      wire, cid, expressions, operations,
    ) {
    Some(value) => value
    None => raise InvalidInstallation
  }
}

///|
fn workers_finite_contract_body(
  wire : String,
) -> @identity.CanonicalValue raise WorkersFiniteFailure {
  let source = match
    @source.parse_json(wire, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }) {
    Ok(value) => value
    Err(_) => raise InvalidInstallation
  }
  @identity.from_source(source, 10000, 100, 100000) catch {
    _ => raise InvalidInstallation
  }
}

///|
#export_name("workersFiniteContracts")
pub fn workers_finite_contracts(
  registry : String,
  values : String,
) -> @execution.RegisteredRelationContracts raise WorkersFiniteFailure {
  match
    @execution.admit_relation_registry(
      workers_finite_contract_body(registry),
      workers_finite_contract_body(values),
      { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
    ) {
    Ok(value) => value
    Err(issue) => raise Registry(issue)
  }
}

///|
#export_name("workersFiniteManifests")
pub fn workers_finite_manifests(
  grammar : String,
  barriers : String,
) -> @publication_host.ClientCompilationManifests raise WorkersFiniteFailure {
  match
    @publication_host.admit_client_compilation_manifests(
      grammar, barriers, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(_) => raise InvalidInstallation
  }
}

///|
fn workers_finite_profile(
  prepared : @publication_host.PreparedClientProgram,
) -> Unit raise WorkersFiniteFailure {
  let graph = @publication_host.prepared_client_graph(prepared)
  if !@strategy.graph_source_free_inputs_complete(graph) ||
    @strategy.graph_program_has_effects(graph) ||
    @strategy.graph_task_count(graph) != 1 ||
    @strategy.graph_task_input_count(graph, 0) != Some(0) ||
    @publication_host.prepared_client_result_count(prepared) != 1 {
    raise UnsupportedProfile
  }
}

///|
/// Checking and lowering are pure and use the common bounded intake. No
/// source selector, provider, Ledger or Run is opened by preparation.
#export_name("workersFinitePrepare")
pub fn workers_finite_prepare(
  document : String,
  environment : @checked.CheckEnvironment,
) -> @publication_host.PreparedClientProgram raise WorkersFiniteFailure {
  let prepared = match
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(issue) => raise Preparation(issue)
  }
  workers_finite_profile(prepared)
  prepared
}

///|
#export_name("workersFiniteCompile")
pub fn workers_finite_compile(
  prepared : @publication_host.PreparedClientProgram,
  manifests : @publication_host.ClientCompilationManifests,
  sequence : @lower.SequenceLimits,
  max_work : Int,
  max_entries : Int,
) -> @publication_host.ClientValuesCompilation raise WorkersFiniteFailure {
  workers_finite_profile(prepared)
  match
    @publication_host.issue_prepared_client_values_compilation(
      prepared, manifests, sequence, max_entries, max_work, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => raise Compilation(issue)
  }
}

///|
#export_name("workersFiniteTemplate")
pub fn workers_finite_template(
  compilation : @publication_host.ClientValuesCompilation,
) -> @publication.RunEvidenceValue {
  @publication_host.client_values_compilation_template(compilation)
}

///|
#export_name("workersFiniteCompiledPlan")
pub fn workers_finite_compiled_plan(
  compilation : @publication_host.ClientValuesCompilation,
) -> @publication.PublicationContract {
  @publication_host.client_values_compilation_compiled_plan(compilation)
}

///|
/// The installing request Owner must already hold the original accepted Run
/// and current authority. This bridge cannot issue either. Binding is checked
/// before opening the caller's original Ledger or a physical task owner.
/// The JS entry additionally requires a protected, same-runtime Account gate.
#export_name("workersFiniteOpen")
pub fn workers_finite_open(
  prepared : @publication_host.PreparedClientProgram,
  compilation : @publication_host.ClientValuesCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  contracts : @execution.RegisteredRelationContracts,
  sequence_limits : @lower.SequenceLimits,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  capacity : @connector.FixedComputeCapacity,
  ledger : @resources.Ledger,
  search : @strategy.SearchLimits,
  milliseconds : Int64,
  max_work : Int,
  max_entries : Int,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise WorkersFiniteFailure {
  workers_finite_profile(prepared)
  if milliseconds < 0L || max_work <= 0 || max_entries <= 0 {
    raise InvalidInstallation
  }
  match
    @publication_host.bind_source_free_client_values_run(
      prepared, compilation, admission, definition,
    ) {
    Ok(_) => ()
    Err(issue) => raise Binding(issue)
  }
  let sequence = match
    @publication_host.prepare_client_task_sequence(
      prepared,
      0,
      contracts,
      [],
      sequence_limits,
      max_work,
      max_entries,
    ) {
    Ok(value) => value
    Err(issue) => raise Sequence(issue)
  }
  // The Local implementation owns the resource formula. Unknown capacity is
  // refusal, never a zero estimate or a different execution destination.
  if @execution.generated_sequence_capacity(sequence, execution, measurement)
    is None {
    raise InvalidInstallation
  }
  let registry = match
    @connector.prepare_capability_registry(
      [
        {
          name: "in-process",
          acquisition: false,
          fixed_compute: true,
          effect: false,
        },
      ],
      1,
      max_work,
    ) {
    Ok(value) => value
    Err(_) => raise InvalidInstallation
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  let run = match @strategy.open_source_free_dag(graph, ledger) {
    Ok(value) => value
    Err(issue) => raise Run(issue)
  }
  errdefer {
    // No task has started. Keep charged planning facts in the original Ledger.
    @strategy.stop_captured_dag(run)
    @strategy.refresh_captured_retention(run)
  }
  let modules = match
    @builtin.configure_compute_modules(
      @host_driver.open_dispatch_driver(run),
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          @connector.capability_registration_at(registry, 0).unwrap(),
          {
            sequences: [sequence],
            managed_providers: [],
            managed_capacity: capacity,
            execution,
            measurement,
            max_work,
          },
          issue => {
            @strategy.RunIssue::Implementation(
              WorkersFiniteFailure::Local(issue),
            )
          },
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      ),
    ) {
    Ok(value) => value
    Err(_) => raise InvalidInstallation
  }
  let local_module = @builtin.configured_local_module(modules).unwrap()
  let slots = @binding15.local_dispatch_work_slots()
  let offer = match
    @binding15.estimate_local_dispatch_offer(
      local_module,
      0,
      [
        {
          work_slots: Array::makei(slots, index => index),
          milliseconds: Some(milliseconds),
        },
      ],
      max_work,
    ) {
    Ok(value) => value
    Err(issue) => raise Local(issue)
  }
  match @strategy.configure_strategy_search(run, search) {
    Ok(_) => ()
    Err(issue) => raise Search(issue)
  }
  let choices = match
    @strategy.prepare_strategy_choices(run, [offer], registry, None) {
    Ok(value) => value
    Err(issue) => raise Search(issue)
  }
  match @strategy.commit_strategy_choice(choices, None) {
    Ok(@strategy.Selected(_)) => ()
    Ok(_) => raise InvalidInstallation
    Err(issue) => raise Search(issue)
  }
  match
    @builtin.open_configured_compute_host(
      modules, registry, capacity, max_entries, max_work, 1,
    ) {
    Ok(value) => value
    Err(issue) => raise Host(issue)
  }
}
