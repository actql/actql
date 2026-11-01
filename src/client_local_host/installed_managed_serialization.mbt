///|
// The same resident Content slot formerly held Option[KeyedPreparation].
// These are the two existing concrete Content purposes, not a generic mode or
// another cleanup owner. Each live case retains one original preparation.
priv enum ClientInstalledContentPreparation {
  NoContent
  KeyedContent(
    ClientInstalledManagedKeyedPreparation,
    @publication_host.ClientRunCompilation?
  )
  SerializationContent(ClientInstalledManagedSerializationPreparation)
}

///|
/// The actual Content prefix and its original compilation. The
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
  model? : @publication_host.ClientInferPlanGraph? = None,
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
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
    (
      @publication_host.prepared_client_acquisition_count(prepared) == 0 ||
      (
        model is Some(_) &&
        @publication_host.prepared_client_acquisition_count(prepared) == 1
      )
    ) &&
    @publication_host.prepared_client_composed_infer_occurrences(prepared)
    is Some(infers) &&
    (match model {
      None => infers.is_empty()
      Some(graph) =>
        infers.length() == 1 &&
        physical_equal(graph.owner, prepared) &&
        compilation.infers.length() == 1 &&
        physical_equal(compilation.infers[0], graph) &&
        graph.serialization is Some(original) &&
        physical_equal(original, component)
    }) &&
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
  if query_time is Some(original) {
    match
      @publication_host.client_query_time_preparation_context_for_run(
        original, prepared, compiled, definition, request,
      ) {
      Err(_) => return Err(ForeignOriginal)
      Ok(_) => ()
    }
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
      acquired=@publication_host.prepared_client_acquisition_count(prepared) ==
        1,
      query_time=query_time.map(original => (original, request)),
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
      guard owner.ledger is Some(ledger) &&
        owner.preparation is Some(preparation) &&
        owner.content is SerializationContent(current) &&
        physical_equal(current, selected) else {
        return Err(Retired)
      }
      // Both purposes retain the same Content prefix on this exact adopted
      // Run. A bare Pure preparation without that original cannot enter.
      let admission = match preparation {
        PreparationContentManaged(admission, original)
        | PureManaged(admission, original) => {
          guard physical_equal(original, prepared) else {
            return Err(ForeignOriginal)
          }
          admission
        }
        _ => return Err(ForeignOriginal)
      }
      let reservation = match
        @resources.reserve_node_managed_run_attempt(
          admission,
          prepared,
          ledger,
          0L,
          @execution.execution_capacity_retained_bytes(selected.capacity),
          @execution.execution_capacity_execution_bytes(selected.capacity),
          // This selected Content prefix consumes no Model quantities. The
          // SAME configured Ledger and ordinary reservation validate this DATA.
          quantities=@resources.quantity_neutral_amounts(ledger),
        ) {
        Err(@resources.Resource(issue)) =>
          return Err(SerializationPrefix(Physical(issue)))
        Err(issue) => return Err(Resource(issue))
        Ok(original) => original
      }
      let prefix = serialization_prefix_reservation(ledger, reservation)
      owner.serialization_prefix = Some(prefix)
      match check_installed_managed_run_original(owner, ledger, preparation) {
        Err(issue) => {
          // No provider has started. Keep the original here if settlement
          // refuses, so later cleanup cannot lose this reservation.
          prefix.child_cleaned = true
          ignore(cleanup_client_serialization_prefix(prefix))
          return Err(issue)
        }
        Ok(_) => ()
      }
      guard owner.content is SerializationContent(original) &&
        physical_equal(original, selected) &&
        owner.serialization_prefix is Some(original_prefix) &&
        physical_equal(original_prefix, prefix) else {
        prefix.child_cleaned = true
        ignore(cleanup_client_serialization_prefix(prefix))
        return Err(ForeignOriginal)
      }
      match
        start_retained_serialization_prefix_provider(
          prefix,
          selected.sequence,
          selected.provider,
          [],
          selected.execution,
          selected.measurement,
        ) {
        Err(issue) => return Err(SerializationPrefix(issue))
        Ok(_) => ()
      }
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
