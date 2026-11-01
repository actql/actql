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
  start_installed_managed_serialization_prefix_owned(
    owner,
    prepared,
    selected,
    None,
  )
}

///|
/// Borrow this SAME adopted Model Run's original accounted capture. Its
/// retained Query is the only input-binding source; no query/provider/Source
/// or Ledger is reconstructed. The capture remains alive until prefix cleanup.
pub fn start_installed_managed_acquired_serialization_prefix(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedSerializationPreparation,
  capture : @row_source_host.RowSourceCapture,
) -> Result[ClientSerializationPrefix, ClientInstalledManagedRunIssue] {
  start_installed_managed_serialization_prefix_owned(
    owner,
    prepared,
    selected,
    Some(capture),
  )
}

///|
fn start_installed_managed_serialization_prefix_owned(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedSerializationPreparation,
  capture : @row_source_host.RowSourceCapture?,
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
      let original_capture = match capture {
        None => {
          guard @publication_host.prepared_client_acquisition_count(prepared) ==
            0 else {
            return Err(ForeignOriginal)
          }
          None
        }
        Some(capture) => {
          guard owner.captured_preparation is Some(plan) &&
            physical_equal(plan.prepared, prepared) &&
            physical_equal(plan.request, selected.request) &&
            plan.captures.length() == 1 else {
            return Err(ForeignOriginal)
          }
          let capacity = plan.captures[0]
          guard @row_source_host.row_capture_original_prefix_requirement(
              capture, ledger,
            )
            is Some(requirement) &&
            physical_equal(requirement, capacity.requirement) else {
            return Err(ForeignOriginal)
          }
          let source = match @row_source_host.row_capture_source(capture) {
            Ok(value) => value
            Err(issue) => return Err(SerializationPrefix(Capture(issue)))
          }
          // Capture liveness invokes the transport verifier. Keep and check
          // the same original Plan/capacity after those callbacks, before the
          // prefix reservation or any producer-read/input allocation.
          match
            check_installed_managed_run_original(owner, ledger, preparation) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          guard owner.captured_preparation is Some(current) &&
            physical_equal(current, plan) &&
            plan.captures.length() == 1 &&
            physical_equal(plan.captures[0], capacity) else {
            return Err(ForeignOriginal)
          }
          Some((capture, plan, capacity, source))
        }
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
      let provider_entered = Ref(false)
      preparation_module_call(
        () => {
          match
            check_installed_managed_run_original(owner, ledger, preparation) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          let inputs = match original_capture {
            None => []
            Some((capture, plan, capacity, source)) => {
              let requirement = capacity.requirement
              let query = @query.query_sequence_requirement(
                @planning.query_material_owner(
                  @planning.query_requirement_material(requirement),
                ),
              )
              guard @publication_host.client_compiled_run_serialization(
                  selected._observed_compiled,
                )
                is Some(component) else {
                return Err(ForeignOriginal)
              }
              let inputs = match
                prepare_acquired_serialization_prefix_inputs(
                  prepared,
                  component.task,
                  source,
                  selected.sequence,
                  query,
                  selected.execution,
                  selected.measurement,
                  ledger,
                  None,
                ) {
                Err(issue) => return Err(SerializationPrefix(issue))
                Ok(value) => value
              }
              // Bindings can reenter the original capture verifier. This
              // reservation-specific check keeps Source and prefix on the
              // same Ledger; a failed callback never permits a replacement.
              guard @row_source_host.row_capture_original_prefix_requirement(
                  capture,
                  ledger,
                  prefix=Some(reservation),
                )
                is Some(current_requirement) &&
                physical_equal(current_requirement, requirement) &&
                owner.captured_preparation is Some(current) &&
                physical_equal(current, plan) &&
                plan.captures.length() == 1 &&
                physical_equal(plan.captures[0], capacity) else {
                return Err(ForeignOriginal)
              }
              inputs
            }
          }
          match
            check_installed_managed_run_original(owner, ledger, preparation) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          guard owner.content is SerializationContent(original) &&
            physical_equal(original, selected) &&
            owner.serialization_prefix is Some(original_prefix) &&
            physical_equal(original_prefix, prefix) else {
            return Err(ForeignOriginal)
          }
          provider_entered.val = true
          match
            start_retained_serialization_prefix_provider(
              prefix,
              selected.sequence,
              selected.provider,
              inputs,
              selected.execution,
              selected.measurement,
            ) {
            Err(issue) => return Err(SerializationPrefix(issue))
            Ok(_) => ()
          }
          match
            check_installed_managed_run_original(owner, ledger, preparation) {
            Err(issue) => return Err(issue)
            Ok(original_ledger) if physical_equal(original_ledger, ledger) =>
              Ok(prefix)
            Ok(_) => Err(ForeignOriginal)
          }
        },
        () => {
          // Before provider entry, only closed borrowed inputs exist. A throw
          // after entry keeps the same retained child/Unknown for its cleanup.
          if !provider_entered.val {
            prefix.child_cleaned = true
            ignore(cleanup_client_serialization_prefix(prefix))
          }
        },
      )
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
