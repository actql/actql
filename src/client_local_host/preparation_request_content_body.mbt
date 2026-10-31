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
    // Selected Plan and original Request links:2H2R2W. Fields are prepaid at entry.
    guard @execution.preparation_representation_cost({
        record_headers: 2L,
        reference_slots: 2L,
        scalar_words: 2L,
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
  guard owner.phase == ContentPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    physical_equal(component.owner, prepared) &&
    owner.program_compilation is None &&
    owner.program_content is NoContent &&
    !owner.program_body_attempted &&
    owner.program_artifact_work is None &&
    owner.program_artifact_work_issue is None else {
    return Err(Preparation(ForeignOriginal))
  }
  guard @publication_host.prepared_client_acquisition_count(prepared) == 0 &&
    @publication_host.prepared_client_composed_infer_occurrences(prepared)
    is Some(infers) &&
    infers.is_empty() &&
    @publication_host.prepared_client_serialization_occurrences(prepared) ==
    [(component.task, component.step)] else {
    return Err(Installed(Unsupported))
  }
  match owner.program_domain_compilation_inputs {
    Some(
      RequestSerializationCompilation(
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
    }
    Some(_) => return Err(Preparation(ForeignOriginal))
    None =>
      owner.program_domain_compilation_inputs = Some(
        RequestSerializationCompilation(
          manifests, compilation_limits, contracts, component,
        ),
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
    owner.program_content is NoContent else {
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
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  owner.phase = Selecting
  owner.program_content = KeyedContent(selected)
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
  guard owner.phase == ContentPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_content is NoContent &&
    owner.program_compilation is Some(@publication_host.Tasks(compilation)) &&
    owner.program_domain_compilation_inputs
    is Some(RequestSerializationCompilation(_, _, contracts, component)) &&
    !owner.program_body_attempted else {
    return Err(ForeignOriginal)
  }
  let selected = match
    prepare_installed_managed_serialization(
      prepared, request, compiled, definition, component, compilation, contracts,
      execution, measurement, workspace,
    ) {
    Err(issue) => return Err(issue)
    Ok(selected) => selected
  }
  // This constructor is closed Local DATA and invokes no current/I/O port.
  // Retain its original before any later completion callback can fail.
  owner.program_content = SerializationContent(selected)
  owner.program_content_request = Some(request)
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
    KeyedContent(selected) =>
      begin_preparation_owned_installed_content_run(
        owner.initial,
        input,
        capacity,
        prepared,
        request,
        selected,
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
