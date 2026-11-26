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
  terminal_output : ClientSerializationOutputDemand?
  whole_plan : ClientInstalledManagedCapturePlan?
  upstream : Array[ClientSerializationUpstream]
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
  terminal_output : ClientSerializationOutputDemand?,
  whole_plan? : ClientInstalledManagedCapturePlan? = None,
  model? : @publication_host.ClientInferPlanGraph? = None,
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
) -> Result[
  ClientInstalledManagedSerializationPreparation,
  ClientInstalledManagedRunIssue,
] {
  let (whole_inputs, retained_inputs) = match whole_plan {
    None => (0, 0)
    Some(plan) => {
      guard model is None &&
        physical_equal(plan.prepared, prepared) &&
        physical_equal(plan.request, request) &&
        plan.serialization is Some(selected) &&
        physical_equal(selected, component) else {
        return Err(ForeignOriginal)
      }
      let whole = plan.whole_sources.length()
      if whole > 0 {
        guard plan.captures.is_empty() &&
          @publication_host.client_serialization_plan_direct_occurrences(
            component, prepared,
          )
          is Some(occurrences) &&
          @publication_host.client_direct_acquisition_occurrence_count(
            occurrences,
          ) ==
          whole else {
          return Err(ForeignOriginal)
        }
        (whole, whole)
      } else {
        guard plan.captures.length() == 1 &&
          @publication_host.client_serialization_plan_direct_occurrences(
            component, prepared,
          )
          is None else {
          return Err(ForeignOriginal)
        }
        (0, plan.captures.length())
      }
    }
  }
  guard physical_equal(component.owner, prepared) &&
    @publication_host.client_task_compilation_serialization(compilation)
    is Some(original_component) &&
    physical_equal(original_component, component) &&
    @publication_host.client_compiled_run_matches_tasks(
      compiled, prepared, compilation,
    ) &&
    (
      @publication_host.prepared_client_acquisition_count(prepared) ==
      retained_inputs ||
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
      acquired=@publication_host.prepared_client_acquisition_count(prepared) > 0,
      whole=whole_inputs > 0,
      query_time=query_time.map(original => (original, request)),
    )
    is Some((sequence, provider, prefix_capacity)) else {
    return Err(Unsupported)
  }
  let upstream = []
  if whole_inputs > 0 {
    guard whole_plan is Some(plan) && plan.direct_occurrences is Some(direct) else {
      return Err(ForeignOriginal)
    }
    for index in 0..<whole_inputs {
      guard @publication_host.client_direct_acquisition_occurrence_at(
          direct, index,
        )
        is Some((_, _, source_task)) &&
        @strategy.graph_task_owner(plan.graph, source_task)
        is Some(source_owner) else {
        return Err(ForeignOriginal)
      }
      if !physical_equal(
          source_owner,
          @execution.generated_sequence_owner(sequence),
        ) {
        guard prepare_terminal_serialization_upstream(
            prepared,
            component.task,
            source_task,
            contracts,
          )
          is Some(source) else {
          return Err(Unsupported)
        }
        upstream.push(source)
      }
    }
    guard upstream.is_empty() || upstream.length() == whole_inputs else {
      return Err(Unsupported)
    }
  }
  let capacity = match workspace {
    None => prefix_capacity
    Some(workspace) =>
      match @execution.add_execution_capacity(prefix_capacity, workspace) {
        None => return Err(InsufficientCapacity)
        Some(capacity) => capacity
      }
  }
  let capacity = if whole_inputs == 0 {
    capacity
  } else {
    guard @row_source_host.row_captured_inputs_construction_inventory(
        whole_inputs,
      )
      is Some(inventory) &&
      @execution.preparation_representation_cost(inventory) is Some(borrowed) &&
      @execution.preparation_representation_cost({
        record_headers: 4L + 3L * whole_inputs.to_int64(),
        reference_slots: 14L * whole_inputs.to_int64(),
        scalar_words: 4L * whole_inputs.to_int64() +
        @execution.generated_sequence_step_count(sequence).to_int64(),
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(bindings) &&
      @execution.checked_preparation_add_product(borrowed, bindings, 1L)
      is Some(bytes) &&
      @execution.execution_capacity(bytes, bytes) is Some(extra) &&
      @execution.add_execution_capacity(capacity, extra) is Some(combined) else {
      return Err(InsufficientCapacity)
    }
    combined
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
    terminal_output,
    whole_plan,
    upstream,
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
/// Start the selected terminal prefix with the exact output demand previously
/// funded on this Run's Request. The Host receives the original limits and
/// cleanup handle together; it cannot replace the compiled plan or resize it.
pub fn start_installed_managed_terminal_serialization(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[
  (
    ClientInstalledManagedSerializationPreparation,
    ClientSerializationPrefix,
    ClientSerializationOutputDemand,
  ),
  ClientInstalledManagedRunIssue,
] {
  guard owner.content is SerializationContent(selected) &&
    selected.terminal_output is Some(demand) &&
    physical_equal(selected.request, request) &&
    physical_equal(selected._observed_compiled, compiled) &&
    physical_equal(selected._observed_definition, definition) else {
    return Err(ForeignOriginal)
  }
  start_installed_managed_serialization_prefix(
    owner,
    selected.prepared,
    selected,
  ).map(prefix => (selected, prefix, demand))
}

///|
fn installed_managed_query_serialization_capture_matches(
  owner : ClientInstalledManagedRun,
  selected : ClientInstalledManagedSerializationPreparation,
  capture : @row_source_host.RowSourceCapture,
  ledger : @resources.Ledger,
) -> Bool {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.content is SerializationContent(current) &&
    physical_equal(current, selected) &&
    owner.captured_preparation is Some(plan) &&
    selected.whole_plan is Some(expected) &&
    physical_equal(plan, expected) &&
    physical_equal(plan.prepared, selected.prepared) &&
    physical_equal(plan.request, selected.request) &&
    physical_equal(owner.request, selected.request) &&
    plan.whole_sources.is_empty() &&
    plan.captures is [capacity] &&
    owner.reads is [Some(read)] &&
    owner.ledger is Some(current_ledger) &&
    physical_equal(current_ledger, ledger) &&
    read.ledger is Some(read_ledger) &&
    physical_equal(read_ledger, ledger) &&
    read.requirement is Some(observed) &&
    physical_equal(observed, capacity.requirement) &&
    read.acquisition is Some(acquisition) &&
    capacity.acquisition is Some(expected_acquisition) &&
    physical_equal(acquisition, expected_acquisition) &&
    read.run is Some(run) else {
    return false
  }
  @row_source_host.check_row_query_capture_run(capture, run)
}

///|
/// Borrow only the exact captured Query on this original terminal Run.
/// The previously admitted acquisition recipe and capture stay live.
pub fn installed_managed_query_serialization_capture_ledger(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedSerializationPreparation,
  capture : @row_source_host.RowSourceCapture,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard physical_equal(selected.prepared, prepared) &&
    selected.whole_plan is Some(plan) &&
    plan.captures is [capacity] &&
    owner.ledger is Some(ledger) &&
    installed_managed_query_serialization_capture_matches(
      owner, selected, capture, ledger,
    ) else {
    return Err(ForeignOriginal)
  }
  match require_installed_managed_run(owner) {
    Err(issue) => return Err(issue)
    Ok(current) if !physical_equal(current, ledger) =>
      return Err(ForeignOriginal)
    Ok(_) => ()
  }
  guard @row_source_host.row_capture_original_borrowed_requirement(
      capture, ledger,
    )
    is Some(requirement) &&
    physical_equal(requirement, capacity.requirement) &&
    installed_managed_query_serialization_capture_matches(
      owner, selected, capture, ledger,
    ) else {
    return Err(ForeignOriginal)
  }
  Ok(ledger)
}

///|
fn installed_managed_serialization_whole_batch_matches(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedSerializationPreparation,
  captures : Array[@row_source_host.RowSourceCapture],
) -> ClientInstalledManagedCapturePlan? {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.content is SerializationContent(current) &&
    physical_equal(current, selected) &&
    physical_equal(selected.prepared, prepared) &&
    physical_equal(selected.request, owner.request) &&
    owner.captured_preparation is Some(plan) &&
    selected.whole_plan is Some(expected) &&
    physical_equal(plan, expected) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, selected.request) &&
    plan.captures.is_empty() &&
    captures.length() == plan.whole_sources.length() else {
    return None
  }
  for index, capture in captures {
    if !whole_source_publication_capture_matches(owner, plan, capture, index~) {
      return None
    }
  }
  Some(plan)
}

///|
/// The trusted Content evidence bridge borrows only this current owned Run's
/// ledger. The ordered captures must be this Plan's exact settled RowRuns.
pub fn installed_managed_whole_serialization_capture_ledger(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedSerializationPreparation,
  captures : Array[@row_source_host.RowSourceCapture],
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard installed_managed_serialization_whole_batch_matches(
      owner, prepared, selected, captures,
    )
    is Some(plan) else {
    return Err(ForeignOriginal)
  }
  let ledger = match require_installed_managed_run(owner) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard installed_managed_serialization_whole_batch_matches(
      owner, prepared, selected, captures,
    )
    is Some(current) &&
    physical_equal(current, plan) else {
    return Err(ForeignOriginal)
  }
  Ok(ledger)
}

///|
/// The installed Node Content owner has already priced its exact output
/// demand; the prefix borrows only the original ordered Whole captures.
pub fn start_installed_managed_whole_serialization_prefix(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedSerializationPreparation,
  captures : Array[@row_source_host.RowSourceCapture],
) -> Result[ClientSerializationPrefix, ClientInstalledManagedRunIssue] {
  guard selected.whole_plan is Some(plan) &&
    plan.whole_sources.length() == captures.length() else {
    return Err(ForeignOriginal)
  }
  start_installed_managed_serialization_prefix_owned(
    owner,
    prepared,
    selected,
    None,
    whole=Some(captures),
  )
}

///|
/// Borrow the selected execution allowance from the existing prefix Plan.
pub fn terminal_serialization_execution_work(
  selected : ClientInstalledManagedSerializationPreparation,
) -> Int {
  selected.execution.max_work
}

///|
/// The Run retained this plan even if prefix start failed before returning.
pub fn cleanup_installed_managed_terminal_serialization(
  owner : ClientInstalledManagedRun,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  guard owner.content is SerializationContent(selected) &&
    selected.terminal_output is Some(_) else {
    return Err(ForeignOriginal)
  }
  cleanup_installed_managed_serialization_prefix(owner, selected)
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
  whole? : Array[@row_source_host.RowSourceCapture]? = None,
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
      let whole_plan = match whole {
        None => None
        Some(captures) => {
          guard capture is None &&
            installed_managed_serialization_whole_batch_matches(
              owner, prepared, selected, captures,
            )
            is Some(plan) else {
            return Err(ForeignOriginal)
          }
          Some(plan)
        }
      }
      let original_capture = match capture {
        None => {
          guard (
              selected.whole_plan is None &&
              @publication_host.prepared_client_acquisition_count(prepared) == 0
            ) ||
            (selected.whole_plan is Some(_) && whole_plan is Some(_)) else {
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
          let requirement = if selected.whole_plan is Some(_) {
            guard installed_managed_query_serialization_capture_matches(
              owner, selected, capture, ledger,
            ) else {
              return Err(ForeignOriginal)
            }
            @row_source_host.row_capture_original_borrowed_requirement(
              capture, ledger,
            )
          } else {
            @row_source_host.row_capture_original_prefix_requirement(
              capture, ledger,
            )
          }
          guard requirement is Some(requirement) &&
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
        @resources.reserve_prepared_run_attempt(
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
          let mut whole_originals = None
          let inputs = match original_capture {
            None =>
              match (whole_plan, whole) {
                (Some(plan), Some(captures)) => {
                  guard borrow_serialization_whole_captures(
                      captures,
                      ledger,
                      selected.execution.max_work,
                    )
                    is Some(originals) else {
                    return Err(ForeignOriginal)
                  }
                  for index, capacity in plan.whole_sources {
                    guard @row_source_host.row_captured_inputs_source_original_at(
                        originals, index,
                      )
                      is Some(actual) &&
                      physical_equal(actual, capacity.original) else {
                      return Err(ForeignOriginal)
                    }
                  }
                  whole_originals = Some(originals)
                  if selected.upstream.is_empty() {
                    match
                      prepare_whole_serialization_prefix_inputs(
                        prepared,
                        selected.sequence,
                        originals,
                        ledger,
                      ) {
                      Err(issue) => return Err(SerializationPrefix(issue))
                      Ok(value) => value
                    }
                  } else {
                    let inputs = []
                    for index, upstream in selected.upstream {
                      match
                        prepare_whole_serialization_prefix_inputs(
                          prepared,
                          upstream.sequence,
                          originals,
                          ledger,
                          occurrence=Some(index),
                        ) {
                        Ok([input]) => inputs.push(input)
                        Ok(_) => return Err(ForeignOriginal)
                        Err(issue) => return Err(SerializationPrefix(issue))
                      }
                    }
                    inputs
                  }
                }
                _ => []
              }
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
              let current_requirement = if selected.whole_plan is Some(_) {
                @row_source_host.row_capture_original_borrowed_requirement(
                  capture, ledger,
                )
              } else {
                @row_source_host.row_capture_original_prefix_requirement(
                  capture,
                  ledger,
                  prefix=Some(reservation),
                )
              }
              guard current_requirement is Some(current_requirement) &&
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
          // Acquired input/liveness callbacks crossed a new boundary. Observe
          // the SAME physical Run current once after them, then fence every
          // retained original without another callback. Empty-input startup
          // keeps its existing callback-free post-construction fence.
          let priced = if selected.upstream.is_empty() {
            []
          } else {
            guard price_terminal_serialization_upstreams(
                selected.upstream,
                inputs,
                selected.capacity,
                selected.execution,
                selected.measurement,
              )
              is Some((providers, peak)) else {
              return Err(InsufficientCapacity)
            }
            match
              @resources.grow_execution_reservation_capacity(
                ledger,
                reservation,
                @execution.execution_capacity_retained_bytes(peak),
                @execution.execution_capacity_execution_bytes(peak),
              ) {
              Err(issue) => return Err(SerializationPrefix(Physical(issue)))
              Ok(_) => ()
            }
            providers
          }
          let current_ledger = match (original_capture, whole_originals) {
            (None, None) =>
              check_installed_managed_run_original(owner, ledger, preparation)
            _ => require_installed_managed_run(owner)
          }
          match current_ledger {
            Err(issue) => return Err(issue)
            Ok(current) if physical_equal(current, ledger) => ()
            Ok(_) => return Err(ForeignOriginal)
          }
          guard owner.content is SerializationContent(original) &&
            physical_equal(original, selected) &&
            owner.serialization_prefix is Some(original_prefix) &&
            physical_equal(original_prefix, prefix) else {
            return Err(ForeignOriginal)
          }
          if original_capture is Some((_, plan, capacity, _)) {
            guard owner.captured_preparation is Some(current) &&
              physical_equal(current, plan) &&
              plan.captures.length() == 1 &&
              physical_equal(plan.captures[0], capacity) else {
              return Err(ForeignOriginal)
            }
          }
          if selected.whole_plan is Some(_) &&
            original_capture is Some((capture, _, capacity, _)) {
            guard @row_source_host.row_capture_original_borrowed_requirement(
                capture, ledger,
              )
              is Some(requirement) &&
              physical_equal(requirement, capacity.requirement) &&
              check_installed_managed_run_original(owner, ledger, preparation)
              is Ok(_) &&
              installed_managed_query_serialization_capture_matches(
                owner, selected, capture, ledger,
              ) &&
              owner.serialization_prefix is Some(current) &&
              physical_equal(current, prefix) &&
              @resources.reservation_open(reservation) &&
              !@resources.reservation_pending(reservation) else {
              return Err(ForeignOriginal)
            }
          }
          if whole_plan is Some(plan) {
            guard whole_originals is Some(originals) &&
              @row_source_host.row_captured_inputs_borrowed_available(
                originals, ledger,
              ) &&
              check_installed_managed_run_original(owner, ledger, preparation)
              is Ok(_) &&
              owner.content is SerializationContent(current_selected) &&
              physical_equal(current_selected, selected) &&
              owner.serialization_prefix is Some(current_prefix) &&
              physical_equal(current_prefix, prefix) &&
              owner.captured_preparation is Some(current_plan) &&
              physical_equal(current_plan, plan) &&
              @resources.reservation_open(reservation) &&
              !@resources.reservation_pending(reservation) else {
              return Err(ForeignOriginal)
            }
            for index in 0..<plan.whole_sources.length() {
              guard @row_source_host.row_captured_input_at(originals, index)
                is Some(capture) &&
                whole_source_publication_capture_matches(
                  owner,
                  plan,
                  capture,
                  index~,
                ) else {
                return Err(ForeignOriginal)
              }
            }
          }
          provider_entered.val = true
          let started = if selected.upstream.is_empty() {
            start_retained_serialization_prefix_provider(
              prefix,
              selected.sequence,
              selected.provider,
              inputs,
              selected.execution,
              selected.measurement,
            ).map(_ => ())
          } else {
            start_retained_serialization_upstream(
              prefix,
              priced,
              selected.sequence,
              selected.provider,
              inputs,
              selected.execution,
              selected.measurement,
            )
          }
          match started {
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

///|
/// Pure nominal admission for the Native first-start boundary.
pub fn terminal_serialization_run_matches(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  owner.original is Some(original) &&
  physical_equal(owner, original) &&
  owner.preparation is Some(PreparationContentManaged(_, current)) &&
  physical_equal(prepared, current) &&
  physical_equal(owner.request, request) &&
  owner.content is SerializationContent(plan) &&
  plan.terminal_output is Some(demand) &&
  demand.result_limits is Some(_) &&
  physical_equal(plan.prepared, prepared) &&
  physical_equal(plan.request, request) &&
  physical_equal(plan._observed_compiled, compiled) &&
  physical_equal(plan._observed_definition, definition)
}

///|
/// The existing prefix reservation backs the coheld Content Store
/// construction before the trusted Native caller receives the child.
pub fn fund_terminal_serialization_store(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  units : @execution.PreparationRepresentationUnits,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.content is SerializationContent(plan) &&
    terminal_serialization_run_matches(
      owner,
      request,
      plan.prepared,
      compiled,
      definition,
    ) &&
    owner.serialization_prefix is Some(prefix) &&
    !prefix.released else {
    return Err(ForeignOriginal)
  }
  let ledger = match require_installed_managed_run(owner) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard physical_equal(ledger, prefix.ledger) &&
    @execution.preparation_representation_cost(units) is Some(bytes) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_retained_bytes(plan.capacity),
      bytes,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(plan.capacity),
      bytes,
      1L,
    )
    is Some(execution) else {
    return Err(InsufficientCapacity)
  }
  @resources.grow_execution_reservation_capacity(
    ledger,
    prefix.reservation,
    retained,
    execution,
  ).map_err(issue => Ledger(issue))
}

///|
/// Receipt readback uses the selected prefix's existing evidence limit.
pub fn terminal_serialization_evidence_entries(
  owner : ClientInstalledManagedRun,
) -> Int? {
  guard owner.content is SerializationContent(plan) &&
    plan.terminal_output is Some(_) else {
    return None
  }
  Some(plan.execution.rows.retained_entries)
}
