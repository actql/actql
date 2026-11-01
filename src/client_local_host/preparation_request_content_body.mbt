///|
/// Select the Content constructor before allocating its Plan. The same
/// original compiler is borrowed through the existing capacity engine; only
/// the two selected Plan/Request link carriers are added to the retained extent.
/// Subsequent borrows preserve actual domain growth without adding it again.
/// Selected provider/keyed/serialization backing remains separately required
/// on this SAME parent, never a second Root or a successful DATA quote.
pub fn[I] borrow_request_content_plan_input(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  ClientRequestPreparationIssue,
] {
  if owner.phase == ModelPlanReserved ||
    owner.program_source_free is Some(_) ||
    owner.program_captured is Some(_) ||
    owner.program_artifact_inputs is Some(_) ||
    owner.program_domain_compilation_inputs is Some(_) ||
    owner.program_body_attempted {
    return Err(WrongPhase)
  }
  let reserved = owner.phase == ContentPlanReserved
  let (r, e) = match request_program_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let previous_phase = owner.phase
  let capacity = owner.program_capacity.unwrap()
  let prepared = owner.compiled_program.unwrap()
  // A Program inventory borrower may already retain domain growth. Selecting
  // Content changes neither that original borrower nor its occupied backing.
  let (r, e) = if reserved || previous_phase == ProgramPlanReserved {
    match @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
  } else {
    (r, e)
  }
  let (r, e) = if reserved {
    (r, e)
  } else {
    // Plan, Request and optional compiler links:3H4R3W. Fields are prepaid at entry.
    guard @execution.preparation_representation_cost({
        record_headers: 3L,
        reference_slots: 4L,
        scalar_words: 3L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(bytes) &&
      @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(Policy)
    }
    (r, e)
  }
  owner.phase = Selecting
  let result = @resources.reserve_preparation_construction_input(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) {
    ContentPlanReserved
  } else {
    previous_phase
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Compile the existing source-free terminal serialization purpose on this
/// Request. The same checked component, contracts, artifact and work receipt
/// survive a declined grow. The caller retains its Content construction borrow
/// and funds the complete component/output frame before this constructor.
pub fn[I] prepare_request_serialization_compilation(
  owner : ClientRequestPreparation[I],
  input : I,
  component : @publication_host.ClientSerializationPlanGraph,
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramPlanIssue,
] {
  prepare_request_serialization_compilation_owned(
    owner,
    input,
    component,
    contracts,
    None,
    manifests,
    compilation_limits,
  )
}

///|
/// Compile the acquired Serialization component selected by this original
/// keyed Content Plan. The Plan already retains the checked Source/transport
/// requirements; its exact task, step and contracts are not inferred from a
/// count or reconstructed from a legacy Node admission.
pub fn[I] prepare_request_keyed_serialization_compilation(
  owner : ClientRequestPreparation[I],
  input : I,
  selected : ClientInstalledManagedKeyedPreparation,
  component : @publication_host.ClientSerializationPlanGraph,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramPlanIssue,
] {
  prepare_request_serialization_compilation_owned(
    owner,
    input,
    component,
    selected.installed_contracts,
    Some(selected),
    manifests,
    compilation_limits,
  )
}

///|
fn[I] prepare_request_serialization_compilation_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  component : @publication_host.ClientSerializationPlanGraph,
  contracts : ClientInstalledSequenceContracts,
  keyed : ClientInstalledManagedKeyedPreparation?,
  manifests : @publication_host.ClientCompilationManifests,
  compilation_limits : @publication_host.ClientPureCompilationLimits,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == ContentPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    physical_equal(component.owner, prepared) &&
    owner.program_compilation is None &&
    (
      owner.program_content is NoContent ||
      (
        keyed is Some(selected) &&
        owner.program_content is KeyedContent(original, None) &&
        physical_equal(original, selected)
      )
    ) &&
    !owner.program_body_attempted &&
    owner.program_artifact_work is None &&
    owner.program_artifact_work_issue is None else {
    return Err(Preparation(ForeignOriginal))
  }
  match keyed {
    None => {
      guard @publication_host.prepared_client_acquisition_count(prepared) == 0 &&
        @publication_host.prepared_client_composed_infer_occurrences(prepared)
        is Some(infers) &&
        infers.is_empty() &&
        @publication_host.prepared_client_serialization_occurrences(prepared) ==
        [(component.task, component.step)] else {
        return Err(Installed(Unsupported))
      }
    }
    Some(selected) => {
      guard physical_equal(selected.prepared, prepared) &&
        component.task == selected.serialization_task &&
        component.step == selected.serialization_step &&
        (
          selected.prefix is None ||
          (
            owner.program_content is KeyedContent(original, None) &&
            physical_equal(original, selected)
          )
        ) else {
        return Err(Preparation(ForeignOriginal))
      }
    }
  }
  match owner.program_domain_compilation_inputs {
    Some(
      RequestSerializationGraph(
        old_manifests,
        old_limits,
        old_contracts,
        old_component
      )
    ) => {
      guard physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) &&
        physical_equal(old_component, component) else {
        return Err(Preparation(ForeignOriginal))
      }
      owner.program_domain_compilation_inputs = Some(
        match keyed {
          None =>
            RequestSerializationCompilation(
              manifests, compilation_limits, contracts, component,
            )
          Some(selected) =>
            RequestKeyedSerializationCompilation(
              manifests, compilation_limits, selected, component,
            )
        },
      )
    }
    Some(
      RequestSerializationCompilation(
        old_manifests,
        old_limits,
        old_contracts,
        old_component
      )
    ) => {
      guard keyed is None &&
        physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_contracts, contracts) &&
        physical_equal(old_component, component) else {
        return Err(Preparation(ForeignOriginal))
      }
    }
    Some(
      RequestKeyedSerializationCompilation(
        old_manifests,
        old_limits,
        old_keyed,
        old_component
      )
    ) => {
      guard keyed is Some(selected) &&
        physical_equal(old_keyed, selected) &&
        physical_equal(old_manifests, manifests) &&
        old_limits == compilation_limits &&
        physical_equal(old_component, component) else {
        return Err(Preparation(ForeignOriginal))
      }
    }
    Some(_) => return Err(Preparation(ForeignOriginal))
    None =>
      owner.program_domain_compilation_inputs = Some(
        match keyed {
          None =>
            RequestSerializationCompilation(
              manifests, compilation_limits, contracts, component,
            )
          Some(selected) =>
            RequestKeyedSerializationCompilation(
              manifests, compilation_limits, selected, component,
            )
        },
      )
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        @publication_host.bind_prepared_client_compiler_contracts(
          prepared,
          contracts.original.value.ordered_contract,
        ) {
        Err(_) => return Err(Preparation(ForeignOriginal))
        Ok(_) => ()
      }
      match
        prepare_request_compilation_owned(
          owner, input, prepared, manifests, compilation_limits,
        ) {
        Ok(@publication_host.Tasks(compilation)) => {
          owner.phase = ContentPlanReserved
          Ok(compilation)
        }
        Err(issue) => Err(issue)
        _ => Err(Preparation(ForeignOriginal))
      }
    },
    () => {
      ignore(finish_request_program_artifact_work(owner))
      if owner.phase == Selecting {
        owner.phase = ProgramBodyFailed
      }
    },
  )
}

///|
/// Complete the actual selected keyed Content preparation on the original
/// compiled Program capacity. The caller retains its construction borrow and
/// all external domain material until this synchronous handoff has unwound.
/// The retained link carriers were funded before construction; no quote repeats.
pub fn[I] complete_request_content_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  selected : ClientInstalledManagedKeyedPreparation,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ContentPlanReserved &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_source_free is None &&
    owner.program_captured is None &&
    (
      (owner.program_content is NoContent && selected.prefix is None) ||
      (
        owner.program_content is KeyedContent(original, None) &&
        physical_equal(original, selected) &&
        owner.program_content_request is Some(original_request) &&
        physical_equal(original_request, request)
      )
    ) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    physical_equal(selected.prepared, prepared) else {
    return Err(ForeignOriginal)
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  let compilation = match owner.program_domain_compilation_inputs {
    None => None
    Some(RequestKeyedSerializationCompilation(_, _, original, component)) => {
      guard physical_equal(original, selected) &&
        owner.program_compilation is Some(@publication_host.Tasks(compilation)) &&
        @publication_host.client_task_compilation_serialization(compilation)
        is Some(compiled_component) &&
        physical_equal(compiled_component, component) else {
        return Err(ForeignOriginal)
      }
      owner.program_compilation
    }
    Some(_) => return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  owner.phase = Selecting
  owner.program_content = KeyedContent(selected, compilation)
  owner.program_content_request = Some(request)
  owner.program_body_attempted = true
  let result = @resources.complete_preparation_capacity(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) {
    ProgramBodyReady
  } else {
    ProgramBodyFailed
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Retain the actual prefix provider and its original Task compilation before
/// completing this Content body. No second compilation or capacity selection
/// occurs at execution. Full constructor and output backing is caller-owned.
pub fn[I] prepare_request_serialization_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : @execution.ExecutionCapacity?,
) -> Result[
  ClientInstalledManagedSerializationPreparation,
  ClientInstalledManagedRunIssue,
] {
  prepare_request_serialization_plan_owned(
    owner,
    input,
    request,
    compiled,
    definition,
    execution,
    measurement,
    workspace,
    None,
    None,
  )
}

///|
/// Construct this Model input prefix under the SAME Request before module,
/// Scope or physical generation. The actual compiler retains the component.
pub fn[I] prepare_request_model_serialization_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : @execution.ExecutionCapacity?,
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  ClientInstalledManagedSerializationPreparation,
  ClientInstalledManagedRunIssue,
] {
  let graph = match owner.program_domain_compilation_inputs {
    Some(RequestModelCompilation(_, _, _, graph)) => graph
    _ => return Err(ForeignOriginal)
  }
  prepare_request_serialization_plan_owned(
    owner,
    input,
    request,
    compiled,
    definition,
    execution,
    measurement,
    workspace,
    Some(graph),
    query_time,
  )
}

///|
fn[I] prepare_request_serialization_plan_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : @execution.ExecutionCapacity?,
  model : @publication_host.ClientInferPlanGraph?,
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  ClientInstalledManagedSerializationPreparation,
  ClientInstalledManagedRunIssue,
] {
  let previous = if model is Some(_) {
    ModelPlanReserved
  } else {
    ContentPlanReserved
  }
  guard owner.phase == previous &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_content is NoContent &&
    owner.program_compilation is Some(@publication_host.Tasks(compilation)) &&
    owner.program_data is Some(data) &&
    owner.program_capacity is Some(capacity) &&
    !owner.program_body_attempted else {
    return Err(ForeignOriginal)
  }
  let (contracts, component) = match
    (model, owner.program_domain_compilation_inputs) {
    (None, Some(RequestSerializationCompilation(_, _, contracts, component))) =>
      (contracts, component)
    (Some(selected), Some(RequestModelCompilation(_, _, contracts, original))) => {
      guard physical_equal(selected, original) &&
        physical_equal(selected.owner, prepared) &&
        selected.serialization is Some(component) else {
        return Err(ForeignOriginal)
      }
      (contracts, component)
    }
    _ => return Err(ForeignOriginal)
  }
  // The selected record owns ten original references; its LedgerLimits owns
  // six scalar words. Plan/Request/compiler link carriers were admitted at
  // the Content input borrow. Compiler, sequence/provider and output backing
  // are separate domains: do not count them as supplied by this fixed packet.
  // Reuse the existing sequential construction quote slot. The completed
  // Model and Content originals coexist in their separate retained fields.
  // Keep the absolute target across a refused grow.
  if owner.program_domain_quote is None {
    guard @execution.preparation_representation_cost({
        record_headers: if model is Some(_) {
          5L
        } else {
          2L
        },
        reference_slots: if model is Some(_) {
          14L
        } else {
          10L
        },
        scalar_words: if model is Some(_) {
          9L
        } else {
          6L
        },
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(records) else {
      return Err(InsufficientCapacity)
    }
    let bytes = match model {
      None => records
      Some(_) => {
        // This additional prefix constructs a second original sequence view
        // while the Model Graph/compiler remain retained. Reuse their actual
        // parsed input extent, not a declared codec ceiling or new tariff.
        guard program_check_data_extent_cost(data) is Some(prefix_inputs) &&
          @execution.checked_preparation_add_product(records, prefix_inputs, 1L)
          is Some(bytes) else {
          return Err(InsufficientCapacity)
        }
        bytes
      }
    }
    let (r, e) = match
      @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Preparation(issue))
      Ok(extents) => extents
    }
    guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(InsufficientCapacity)
    }
    owner.program_domain_quote = Some((r, e))
  }
  let (r, e) = owner.program_domain_quote.unwrap()
  owner.phase = Selecting
  let grown = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  )
  if grown is Err(issue) {
    if owner.phase == Selecting {
      owner.phase = previous
    }
    return Err(Preparation(issue))
  }
  guard owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is Some(original_capacity) &&
    physical_equal(original_capacity, capacity) &&
    owner.compiled_program is Some(original_prepared) &&
    physical_equal(original_prepared, prepared) &&
    owner.program_content is NoContent &&
    owner.program_compilation
    is Some(@publication_host.Tasks(original_compilation)) &&
    physical_equal(original_compilation, compilation) &&
    (match (model, owner.program_domain_compilation_inputs) {
      (
        None,
        Some(
          RequestSerializationCompilation(
            _,
            _,
            current_contracts,
            current_component
          )
        ),
      ) =>
        physical_equal(current_contracts, contracts) &&
        physical_equal(current_component, component)
      (
        Some(selected),
        Some(RequestModelCompilation(_, _, current_contracts, current_graph)),
      ) =>
        physical_equal(current_contracts, contracts) &&
        physical_equal(current_graph, selected) &&
        current_graph.serialization is Some(current_component) &&
        physical_equal(current_component, component)
      _ => false
    }) &&
    owner.program_domain_quote == Some((r, e)) else {
    if owner.phase == Selecting {
      owner.phase = previous
    }
    return Err(ForeignOriginal)
  }
  let selected = match
    prepare_installed_managed_serialization(
      prepared,
      request,
      compiled,
      definition,
      component,
      compilation,
      contracts,
      execution,
      measurement,
      workspace,
      model~,
      query_time~,
    ) {
    Err(issue) => {
      // A foreign tuple is refused before prefix construction. Once the
      // original constructor has run, a failed body cannot select replacement
      // limits/provider on this same Request. Keep its reservation for Abort;
      // a successful pre-construction grow is neither a body nor cleanup ACK.
      owner.phase = if issue is ForeignOriginal {
        previous
      } else {
        ProgramBodyFailed
      }
      return Err(issue)
    }
    Ok(selected) => selected
  }
  // This constructor is closed Local DATA and invokes no current/I/O port.
  // Retain its original before any later completion callback can fail.
  owner.program_content = SerializationContent(selected)
  owner.program_content_request = Some(request)
  owner.program_domain_quote = None
  owner.phase = previous
  Ok(selected)
}

///|
/// Complete only the source-free preparation selected by this SAME Request.
/// Keyed Content keeps its own typed entry, with neither purpose cast to Pure.
pub fn[I] complete_request_serialization_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  selected : ClientInstalledManagedSerializationPreparation,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ContentPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    physical_equal(prepared, selected.prepared) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_content is SerializationContent(plan) &&
    physical_equal(plan, selected) &&
    owner.program_content_request is Some(request) &&
    physical_equal(request, selected.request) &&
    !owner.program_body_attempted else {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  owner.phase = Selecting
  owner.program_body_attempted = true
  let result = @resources.complete_preparation_capacity(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) {
    ProgramBodyReady
  } else {
    ProgramBodyFailed
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Same-parent adoption retains the original Content Plan through currentness
/// and generic preparation retirement. The legacy Content purpose is neither
/// selected nor widened. No Source read or provider operation begins here.
pub fn[I] begin_request_content_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == ProgramBodyReady &&
    owner.input is Some(input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    !(owner.program_content is NoContent) &&
    owner.program_content_request is Some(original_request) &&
    physical_equal(original_request, request) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = match owner.program_content {
    KeyedContent(selected, _) =>
      adopt_preparation_owned_content_original(
        owner.initial,
        input,
        capacity,
        prepared,
        request,
        owner.program_content,
        selected.limits,
      )
    SerializationContent(selected) =>
      begin_preparation_owned_installed_serialization_run(
        owner.initial,
        input,
        capacity,
        prepared,
        request,
        selected,
      )
    NoContent => Err(ForeignOriginal)
  }
  match result {
    Err(issue) => {
      owner.phase = ProgramBodyReady
      Err(issue)
    }
    Ok(run) => {
      owner.program_capacity = None
      owner.compiled_program = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.program_content = NoContent
      owner.program_content_request = None
      owner.program_compilation = None
      owner.program_domain_compilation_inputs = None
      owner.program_artifact_geometry = None
      owner.program_artifact_quote = None
      owner.program_measurement_quote = None
      owner.program_invocation_quote = None
      owner.native_parameters = None
      owner.native_query_declarations = None
      owner.native_parameters_ready = false
      owner.held_program = None
      owner.submitted_intent = None
      owner.intent_base = None
      owner.intent_peak_live = false
      owner.input = None
      owner.query_syntax = None
      owner.phase = Selected
      Ok(run)
    }
  }
}
