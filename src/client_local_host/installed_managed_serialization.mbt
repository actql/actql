///|
// The same resident Content slot formerly held Option[KeyedPreparation].
// These are the two existing concrete Content purposes, not a generic mode or
// another cleanup owner. Each live case retains one original preparation.
priv enum ClientInstalledContentPreparation {
  NoContent
  KeyedContent(ClientInstalledManagedKeyedPreparation)
  SerializationContent(ClientInstalledManagedSerializationPreparation)
}

///|
/// The actual source-free Content prefix and its original compilation. The
/// caller backs constructor/output coexistence before entry. Keeping these
/// originals eliminates the former capacity/start provider reconstruction;
/// neither the record nor its requirements projection is physical admission.
struct ClientInstalledManagedSerializationPreparation {
  prepared : @publication_host.PreparedClientProgram
  request : @publication_host.ClientRequestIdentity
  // The compiled original already retains its Task compiler and component.
  _observed_compiled : @publication_host.ClientCompiledRun
  _observed_definition : @publication.PublicationContract
  sequence : @execution.GeneratedSequence
  provider : @local.ManagedProvider
  capacity : @execution.ExecutionCapacity
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  limits : @resources.LedgerLimits
}

///|
fn prepare_installed_managed_serialization(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  component : @publication_host.ClientSerializationPlanGraph,
  compilation : @publication_host.ClientTaskCompilation,
  contracts : ClientInstalledSequenceContracts,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : @execution.ExecutionCapacity?,
) -> Result[
  ClientInstalledManagedSerializationPreparation,
  ClientInstalledManagedRunIssue,
] {
  guard physical_equal(component.owner, prepared) &&
    @publication_host.client_task_compilation_serialization(compilation)
    is Some(original_component) &&
    physical_equal(original_component, component) &&
    @publication_host.client_compiled_run_matches_tasks(
      compiled, prepared, compilation,
    ) &&
    @publication_host.prepared_client_acquisition_count(prepared) == 0 &&
    @publication_host.prepared_client_composed_infer_occurrences(prepared)
    is Some(infers) &&
    infers.is_empty() &&
    @publication_host.prepared_client_serialization_occurrences(prepared) ==
    [(component.task, component.step)] else {
    return Err(ForeignOriginal)
  }
  match
    @publication_host.validate_client_run_binding(
      request, prepared, compiled, definition,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  let installed = contracts.original
  guard serialization_prefix_provider(
      prepared,
      component.task,
      component.step,
      contracts,
      installed.values_body,
      installed.fragment_body,
      installed.ordered_body,
      execution,
      measurement,
    )
    is Some((sequence, provider, prefix_capacity)) else {
    return Err(Unsupported)
  }
  let capacity = match workspace {
    None => prefix_capacity
    Some(workspace) =>
      match @execution.add_execution_capacity(prefix_capacity, workspace) {
        None => return Err(InsufficientCapacity)
        Some(capacity) => capacity
      }
  }
  // Preserve the existing prefix's one attempt and its actual selected byte
  // envelope. This is not the total Host/Store/Request quote. Logical Content
  // work keeps its original execution owner; consumed parent work is not reset.
  let limits : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: @execution.execution_capacity_retained_bytes(capacity),
    execution_bytes: @execution.execution_capacity_execution_bytes(capacity),
  }
  Ok({
    prepared,
    request,
    _observed_compiled: compiled,
    _observed_definition: definition,
    sequence,
    provider,
    capacity,
    execution,
    measurement,
    limits,
  })
}

///|
/// Read the selected prefix envelope only. Other live Host/Store/output
/// obligations still have to be backed on this same original parent.
pub fn prepared_installed_managed_serialization_prefix_requirements(
  selected : ClientInstalledManagedSerializationPreparation,
) -> Array[Int64] {
  installed_effect_requirements(selected.limits)
}

///|
/// Start this original retained prefix once. The managed Run holds the child
/// before a post-callback refusal can escape; cleanup can retrieve that same
/// original without acquiring another prefix or creating a Ledger.
pub fn start_installed_managed_serialization_prefix(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedSerializationPreparation,
) -> Result[ClientSerializationPrefix, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.content is SerializationContent(plan) &&
    physical_equal(plan, selected) &&
    physical_equal(selected.prepared, prepared) &&
    physical_equal(selected.request, owner.request) else {
    return Err(ForeignOriginal)
  }
  if owner.source_free_opening || owner.serialization_prefix is Some(_) {
    return Err(AlreadyBound)
  }
  owner.source_free_opening = true
  preparation_module_call(
    () => {
      let ledger = match require_installed_managed_run(owner) {
        Err(issue) => return Err(issue)
        Ok(ledger) => ledger
      }
      guard owner.preparation is Some(preparation) &&
        owner.content is SerializationContent(current) &&
        physical_equal(current, selected) else {
        return Err(Retired)
      }
      let prefix = match
        start_serialization_prefix_provider(
          selected.sequence,
          selected.provider,
          selected.capacity,
          [],
          selected.execution,
          selected.measurement,
          ledger,
          None,
          retain=Some(prefix => owner.serialization_prefix = Some(prefix)),
        ) {
        Err(issue) => return Err(SerializationPrefix(issue))
        Ok(prefix) => prefix
      }
      owner.serialization_prefix = Some(prefix)
      match check_installed_managed_run_original(owner, ledger, preparation) {
        Err(issue) => return Err(issue)
        Ok(original_ledger) if physical_equal(original_ledger, ledger) =>
          Ok(prefix)
        Ok(_) => Err(ForeignOriginal)
      }
    },
    () => owner.source_free_opening = false,
  )
}

///|
/// Clean only this same retained prefix, including after a failed constructor
/// or current callback. No Option/tuple ABI or bare Ledger leaves the owner.
/// Other Host/Store children keep their separate actual cleanup obligations.
pub fn cleanup_installed_managed_serialization_prefix(
  owner : ClientInstalledManagedRun,
  selected : ClientInstalledManagedSerializationPreparation,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.content is SerializationContent(plan) &&
    physical_equal(plan, selected) else {
    return Err(ForeignOriginal)
  }
  if owner.source_free_opening {
    return Ok(false)
  }
  match owner.serialization_prefix {
    // The sole original prefix slot was never issued. This result does not
    // acknowledge physical cleanup of any other domain or original child.
    None => Ok(true)
    Some(prefix) => {
      ignore(cancel_client_serialization_prefix(prefix))
      cleanup_client_serialization_prefix(prefix).map_err(issue => {
        SerializationPrefix(issue)
      })
    }
  }
}
