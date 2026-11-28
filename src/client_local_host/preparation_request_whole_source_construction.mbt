///|
/// Retain the selected complete-input originals only after this SAME Request
/// backs their constructor and Native locator/transport overlap. This entry
/// never selects Query fallback, starts a physical read or issues a Run. The
/// caller must use these exact originals in the existing Whole Source Plan.
pub fn[I] reserve_request_whole_source_construction(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  (
    @publication_host.ClientDirectAcquisitionOccurrences,
    Array[@sourceviews.SourceAcquisition],
  ),
  ClientRequestProgramPlanIssue,
] {
  preparation_module_call(
    () => {
      let (direct, sources) = match
        reserve_request_whole_source_routes(owner, input, request) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      match
        reserve_request_selected_whole_source_inputs(owner, input, sources) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      Ok((direct, sources))
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
fn[I] reserve_request_selected_whole_source_inputs(
  owner : ClientRequestPreparation[I],
  input : I,
  sources : Array[@sourceviews.SourceAcquisition],
  phase? : ClientRequestPreparationPhase = ProgramPlanReserved,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  guard owner.phase == Selecting && owner.compiled_program is Some(prepared) else {
    return Err(Preparation(ForeignOriginal))
  }
  let mut bytes = 0L
  for source in sources {
    guard request_whole_source_input_construction_bytes(source)
      is Some(input_bytes) &&
      @execution.checked_preparation_add_product(bytes, input_bytes, 1L)
      is Some(next) else {
      return Err(Preparation(Policy))
    }
    bytes = next
  }
  match
    reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Keep the successful extent after the checked grow. Earlier construction
  // backing and pending physical cleanup remain with the same parent.
  owner.program_domain_quote = None
  owner.phase = phase
  Ok(())
}

///|
/// The checked construction choice for this original Project File Request. The same
/// original occurrence inventory reaches the selected constructor.
pub enum ClientRequestFileSourceInputs[I] {
  SingleWholeFileInput(ClientRequestWholeFileInput[I])
  WholeSourceInputs(
    @publication_host.ClientDirectAcquisitionOccurrences,
    Array[@sourceviews.SourceAcquisition]
  )
  QuerySourceInputs(
    @planning.QueryEvidenceContracts,
    @publication_host.ClientDirectAcquisitionOccurrences
  )
  MissingQueryContracts
}

///|
/// The singleton File Source selected and funded on this exact Request.
struct ClientRequestWholeFileInput[I] {
  owner : ClientRequestPreparation[I]
  request : @publication_host.ClientRequestIdentity
  source : @sourceviews.SourceAcquisition
}

///|
pub enum ClientRequestFileSourceIssue {
  FileSourceSelection(ClientRequestProgramPlanIssue)
  FileWholeConstruction(ClientRequestProgramPlanIssue)
  FileQueryContracts(ClientRequestProgramPlanIssue)
}

///|
/// Fund and inspect the exact checked occurrence inventory before choosing
/// a Project File constructor. A failed Query is terminal. Whole requires
/// complete-input selection for each original, even when several share a task.
pub fn[I] prepare_request_file_source_inputs(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  bodies : (String, String)?,
) -> Result[ClientRequestFileSourceInputs[I], ClientRequestFileSourceIssue] {
  preparation_module_call(
    () => {
      let (direct, sources) = match
        reserve_request_whole_source_routes(
          owner,
          input,
          request,
          select_query=true,
        ) {
        Err(issue) => return Err(FileSourceSelection(issue))
        Ok(value) => value
      }
      if !sources.is_empty() {
        match
          reserve_request_selected_whole_source_inputs(owner, input, sources) {
          Err(issue) => return Err(FileWholeConstruction(issue))
          Ok(_) => ()
        }
        if sources is [source] &&
          @environment.source_request_file_listing(
            @sourceviews.selected_contract(
              @sourceviews.mode_input(
                @sourceviews.source_acquisition_mode(source),
              ),
            ),
          )
          is None {
          return Ok(SingleWholeFileInput({ owner, request, source, }))
        }
        return Ok(WholeSourceInputs(direct, sources))
      }
      // The selector requires at least one original and refuses mixed routes.
      // No Whole Source original here therefore means every route was Query.
      guard owner.phase == Selecting && owner.compiled_program is Some(prepared) else {
        return Err(FileSourceSelection(Preparation(ForeignOriginal)))
      }
      owner.program_domain_quote = None
      owner.phase = ProgramPlanReserved
      guard bodies is Some((query, evidence)) else {
        return Ok(MissingQueryContracts)
      }
      admit_request_query_acquisition_contracts_for_original(
        owner, input, prepared, direct, query, evidence,
      )
      .map(value => {
        ClientRequestFileSourceInputs::QuerySourceInputs(value.0, value.1)
      })
      .map_err(issue => FileQueryContracts(issue))
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
/// Count checked direct responses while the Pure body still belongs to this
/// Request. The funded selector still resolves their nominal correspondence.
pub fn[I] request_checked_pure_direct_source_count(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Int64? {
  guard owner.phase == ProgramCompiled &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) else {
    return None
  }
  let checked = @strategy.graph_program(
    @publication_host.prepared_client_graph(prepared),
  )
  let mut direct = 0L
  for index in 0..<@checked.source_execution_count(checked) {
    guard @checked.source_execution_at(checked, index) is Some(execution) else {
      return None
    }
    if @checked.source_execution_kind(execution) is @checked.CarrierResponse &&
      @checked.source_execution_subject(execution).request
      is @sourceviews.Direct(_, _) {
      direct += 1L
    }
  }
  Some(direct)
}

///|
/// Inspect the already funded Whole File admission originals synchronously.
/// The parent retains every alias. This does not sample currentness, issue a
/// Run, select a Model or Content plan, or transfer cleanup to the inspector.
pub fn[I, A] inspect_request_whole_file_plan_original(
  owner : ClientRequestPreparation[I],
  input : I,
  inspect : (
    @publication_host.ClientRequestIdentity,
    @publication_host.PreparedClientProgram,
    @publication_host.ClientTaskCompilation,
  ) -> A,
) -> A? {
  guard owner.phase == ProgramBodyReady &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_captured is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    plan.whole_sources.length() == 1 &&
    plan.captures.is_empty() &&
    plan.compilation is Some(@publication_host.Tasks(compilation)) &&
    physical_equal(compilation.owner, prepared) &&
    compilation.infers.is_empty() &&
    compilation.serialization is None else {
    return None
  }
  Some(inspect(plan.request, prepared, compilation))
}

///|
/// Fund this finished captured Plan on the same backed execution ticket.
/// The caller still owns the original Store and authorization. No Run is
/// adopted, no source attempt is reserved, and no physical response is read.
pub fn[P, C, I] fund_platform_vm_request_whole_file_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  access : @resources.BackedExecutionLiveAccess[P, C, I],
) -> Result[Unit, @resources.BackedExecutionIssue] {
  guard inspect_request_whole_file_plan_original(owner, input, (original, _, _) => {
      physical_equal(original, request)
    })
    is Some(true) &&
    owner.initial is BackedRequestInitial(initial) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_captured is Some(plan) &&
    plan.transport_bytes is [source_transfer] else {
    return Err(ForeignOriginal)
  }
  let limits = plan.limits
  owner.phase = Selecting
  let funded = @resources.fund_platform_vm_prepared_run(
    access,
    initial,
    input,
    capacity,
    prepared,
    limits.attempts,
    limits.holdings,
    limits.transfer_bytes,
    initial_transfer_bytes=Some(source_transfer),
  )
  owner.phase = ProgramBodyReady
  funded
}

///|
fn[I] request_whole_file_materials_current(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
) -> Bool {
  owner.native_parameters_ready &&
  inspect_request_whole_file_plan_original(owner, input, (
    original,
    prepared,
    tasks,
  ) => {
    physical_equal(original, request) &&
    @publication_host.client_compiled_run_matches_tasks(
      compiled, prepared, tasks,
    )
  })
  is Some(true)
}

///|
/// Stage the existing Task Run material wire for this same completed File
/// Plan. The caller funds each constructor and keeps the physical journal and
/// current Submit. No Source read, Run adoption, write or acknowledgement runs.
pub fn[I] issue_request_whole_file_run_materials(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  fund : (String, Int, Int, Int) -> Bool,
) -> Result[
  @publication_host.ClientCapturedTaskRunMaterials,
  @publication_host.ClientTaskRunMaterialsIssue,
] {
  fn current() -> Bool {
    request_whole_file_materials_current(owner, input, request, compiled)
  }
  guard current() else { return Err(RunMismatch) }
  let mut lost_original = false
  let result = @publication_host.issue_original_client_captured_task_run_materials(
    request,
    compiled,
    definition,
    owner.native_parameters,
    (purpose, bytes, nodes, depth) => {
      if !current() {
        lost_original = true
        false
      } else if !fund(purpose, bytes, nodes, depth) {
        false
      } else if !current() {
        lost_original = true
        false
      } else {
        true
      }
    },
  )
  if lost_original || (result is Ok(_) && !current()) {
    Err(RunMismatch)
  } else {
    result
  }
}

///|
/// Stage the original first Run rows from the still-held File Plan. The
/// caller owns the current Store transaction and funds the constructor and
/// material capture. Optional transport staging funds only the existing wire
/// encoder. No callback can turn this candidate into a physical write or ACK.
pub fn[I, E] prepare_request_whole_file_first_journal_rows(
  owner : ClientRequestPreparation[I],
  input : I,
  snapshot : @publication_host.ClientSavedSubmissionSnapshot,
  materials : @publication_host.ClientCapturedTaskRunMaterials,
  policy : @publication_host.ClientLocalRunPolicyOriginal,
  now : Double,
  max_records : Int,
  scan : (String, String) -> Result[
    @publication_host.ClientJournalPhysicalRow?,
    E,
  ],
  read : (String, String) -> Result[
    @publication_host.ClientJournalPhysicalRow?,
    E,
  ],
  validate_run : (@publication_host.ClientJournalPhysicalRow) -> Result[
    @publication_host.ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  before_task_materials : (Int64, Int64) -> Result[Unit, E],
  policy_collection : @publication_host.ClientRunPolicyCollectionFunding,
  before_policy_packet : (Int64, Int64) -> Result[Unit, E],
  fund_task_indexes : (Int64) -> Result[Unit, E],
  fund_task_read : (Int64) -> Result[Unit, E],
  fund_rows : (Int64, Int64) -> Result[Unit, E],
  stage_wire? : ((Int64) -> Result[Unit, E], (String) -> Result[Unit, E])? = None,
  definition_presence? : ((String) -> Result[Bool?, E])? = None,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
  indexed_store? : Bool = false,
) -> Result[
  @publication_host.ClientCapturedTaskFirstRunRows,
  @publication_host.ClientRunJournalAppendIssue[E],
] {
  guard request_submitted_intent_original(owner, input) is Some(intent) else {
    return Err(@publication_host.InvalidOriginal)
  }
  fn current() -> Bool {
    request_whole_file_materials_current(
      owner,
      input,
      materials.request,
      materials.compiled,
    ) &&
    request_submitted_intent_original(owner, input) is Some(actual) &&
    physical_equal(actual, intent)
  }
  fn fund_current(
    fund : (Int64, Int64) -> Result[Unit, E],
    retained : Int64,
    scratch : Int64,
  ) -> Result[Unit, E] {
    if !current() {
      return Err(custody_lost)
    }
    fund(retained, scratch).bind(_ => {
      if current() {
        Ok(())
      } else {
        Err(custody_lost)
      }
    })
  }
  guard current() else { return Err(@publication_host.InvalidOriginal) }
  let candidate = match
    @publication_host.prepare_client_captured_task_first_run_rows(
      snapshot,
      intent,
      materials,
      policy,
      now,
      max_records,
      scan,
      read,
      validate_run,
      confirm_cancellation,
      custody_lost,
      (retained, scratch) => {
        fund_current(before_task_materials, retained, scratch)
      },
      {
        ..policy_collection,
        current: () => current() && (policy_collection.current)(),
      },
      (retained, scratch) => {
        fund_current(before_policy_packet, retained, scratch)
      },
      bytes => {
        fund_current((_, scratch) => fund_task_indexes(scratch), 0L, bytes)
      },
      bytes => fund_current((_, scratch) => fund_task_read(scratch), 0L, bytes),
      (retained, scratch) => fund_current(fund_rows, retained, scratch),
      definition_presence~,
      task_material_count~,
      indexed_store~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard current() else { return Err(@publication_host.InvalidOriginal) }
  if stage_wire is Some((fund, stage)) {
    guard @publication_host.client_captured_task_first_run_rows_wire_workspace(
        candidate,
      )
      is Some(workspace) else {
      return Err(@publication_host.CapacityExceeded)
    }
    match fund(workspace) {
      Err(issue) => return Err(@publication_host.Observation(issue))
      Ok(_) => ()
    }
    guard current() else { return Err(@publication_host.InvalidOriginal) }
    let wire = match
      @publication_host.client_captured_task_first_run_rows_wire(candidate) {
      Ok(value) => value
      Err(issue) => return Err(@publication_host.Encoding(issue))
    }
    match stage(wire) {
      Err(issue) => return Err(@publication_host.Observation(issue))
      Ok(_) => ()
    }
    guard current() else { return Err(@publication_host.InvalidOriginal) }
  }
  Ok(candidate)
}

///|
pub enum ClientRequestRetainedWholeFileIssue {
  ForeignFileSubmission
  UnsupportedFileRoute
  RetainedFileIdentity(@publication_host.ClientRequestIdentityIssue)
  RetainedFileSelection(ClientRequestFileSourceIssue)
}

///|
/// Issue the Request identity from the preparing Submission checked on this
/// owner, then select its singleton Whole input. The Host retains the same
/// Journal Read and performs its independent authorization and current fences.
/// No Run, physical acquisition or durable submission is started here.
pub fn[I] select_request_retained_whole_file(
  owner : ClientRequestPreparation[I],
  input : I,
  snapshot : @publication_host.ClientSavedSubmissionSnapshot,
  authority_scope_cid : String,
) -> Result[
  (@publication_host.ClientRequestIdentity, ClientRequestWholeFileInput[I]),
  ClientRequestRetainedWholeFileIssue,
] {
  let saved = @publication_host.client_saved_submission_record(snapshot)
  let reference = saved.reference
  let epoch = @publication_host.client_submission_reference_record_epoch(
    reference,
  )
  guard owner.phase == ProgramPlanReserved &&
    owner.compiled_program is Some(prepared) &&
    owner.program_capacity is Some(capacity) &&
    request_submitted_intent_original(owner, input) is Some(intent) &&
    physical_equal(intent, saved.intent) &&
    saved.run_admission is None &&
    saved.preparation_problem is None &&
    saved.run_state_original is None &&
    saved.run_state_observation is None &&
    @publication_host.client_saved_submission_run_row(snapshot) is None &&
    authority_scope_cid ==
    @publication_host.client_submission_epoch_token_authority_scope_cid(epoch) else {
    return Err(ForeignFileSubmission)
  }
  let request = match
    fund_request_retained_whole_file_identity(
      owner,
      input,
      capacity,
      prepared,
      authority_scope_cid,
      @publication_host.client_submission_reference_record_request_id(reference),
      @publication_host.client_submitted_intent_cid(intent),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match prepare_request_file_source_inputs(owner, input, request, None) {
    Ok(SingleWholeFileInput(selected)) => Ok((request, selected))
    Ok(_) => Err(UnsupportedFileRoute)
    Err(issue) => Err(RetainedFileSelection(issue))
  }
}

///|
fn[I] fund_request_retained_whole_file_identity(
  owner : ClientRequestPreparation[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  authority_scope_cid : String,
  request_id : String,
  intent_cid : String,
) -> Result[
  @publication_host.ClientRequestIdentity,
  ClientRequestRetainedWholeFileIssue,
] {
  fn selection_issue(
    issue : ClientRequestPreparationIssue,
  ) -> ClientRequestRetainedWholeFileIssue {
    RetainedFileSelection(FileSourceSelection(Preparation(issue)))
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(selection_issue(Capacity(issue)))
    Ok(value) => value
  }
  guard @publication_host.client_request_identity_construction_inventory()
    is Some((retained, scratch)) &&
    // The new return pair lives with the issued identity. All other domain
    // constructor and selection frames remain on their existing quotes.
    @execution.preparation_representation_cost({
      ..retained,
      record_headers: retained.record_headers + 1L,
      reference_slots: retained.reference_slots + 2L,
    })
    is Some(retained_bytes) &&
    @execution.preparation_representation_cost(scratch) is Some(workspace_bytes) &&
    @execution.checked_preparation_add_product(r, retained_bytes, 1L)
    is Some(done_r) &&
    @execution.checked_preparation_add_product(e, retained_bytes, 1L)
    is Some(done_e) &&
    @execution.checked_preparation_add_product(done_e, workspace_bytes, 1L)
    is Some(peak_e) else {
    return Err(selection_issue(Policy))
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        @resources.reserve_working_preparation_phase(
          capacity, input, done_r, peak_e,
        ) {
        Err(issue) => {
          owner.phase = ProgramPlanReserved
          return Err(selection_issue(Capacity(issue)))
        }
        Ok(_) => ()
      }
      let request = match
        @publication_host.prepare_client_request_identity(
          prepared, authority_scope_cid, request_id, intent_cid,
        ) {
        Err(issue) => {
          owner.phase = ProgramBodyFailed
          return Err(RetainedFileIdentity(issue))
        }
        Ok(value) => value
      }
      match
        @resources.reconcile_working_preparation_phase(
          capacity, input, done_r, done_e,
        ) {
        Err(issue) => {
          owner.phase = ProgramBodyFailed
          Err(selection_issue(Capacity(issue)))
        }
        Ok(_) => {
          owner.phase = ProgramPlanReserved
          Ok(request)
        }
      }
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
pub fn[I] client_request_whole_file_source(
  selected : ClientRequestWholeFileInput[I],
) -> @sourceviews.SourceAcquisition {
  selected.source
}

///|
/// Select the physical Source from the same issued Portable Model Request.
/// The checked occurrence is retained for the existing Whole acquisition.
pub fn[I] reserve_request_portable_model_whole_file(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientRequestWholeFileInput[I], ClientRequestProgramPlanIssue] {
  let phase = owner.phase
  guard phase is PortableModelMetadataIssued(issued) &&
    physical_equal(issued.request, request) &&
    issued.materials is Some(_) &&
    owner.program_compilation is Some(@publication_host.Tasks(_)) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelCompilation(_, _, _, _)) &&
    owner.program_source_free is None &&
    owner.program_captured is None &&
    owner.program_model is None else {
    return Err(Preparation(ForeignOriginal))
  }
  preparation_module_call(
    () => {
      let sources = match
        reserve_request_whole_source_routes(owner, input, request, phase~) {
        Err(issue) => return Err(issue)
        Ok((_, sources)) => sources
      }
      guard sources is [source] &&
        @environment.source_request_file_listing(
          @sourceviews.selected_contract(
            @sourceviews.mode_input(
              @sourceviews.source_acquisition_mode(source),
            ),
          ),
        )
        is None else {
        return Err(Installed(Unsupported))
      }
      reserve_request_selected_whole_source_inputs(
        owner,
        input,
        sources,
        phase~,
      ).map(_ => { owner, request, source, })
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
/// Prove that a Portable Whole Source borrow still belongs to its issued
/// Request. No Source body or permission is granted by this predicate.
fn[I] request_portable_model_whole_file_current(
  owner : ClientRequestPreparation[I],
  selected : ClientRequestWholeFileInput[I],
) -> Bool {
  owner.phase is PortableModelMetadataIssued(issued) &&
  physical_equal(issued.request, selected.request) &&
  issued.materials is Some(_) &&
  owner.program_model is None &&
  owner.program_captured is None &&
  owner.program_source_free is None
}

///|
/// Prepare the same paid row-input capacity for the selected Portable Model
/// Source. The File Model module will consume it under that Request.
pub fn[I] prepare_request_portable_model_whole_source_capacity(
  owner : ClientRequestPreparation[I],
  input : I,
  selected : ClientRequestWholeFileInput[I],
  declaration : @row_source_host.RowDeclaration,
  contracts : ClientInstalledSequenceContracts,
  limits : @row_source_host.RowInputLimits,
) -> Result[ClientInstalledWholeSourceCapacity, ClientInstalledManagedRunIssue] {
  guard physical_equal(selected.owner, owner) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    !owner.program_body_attempted &&
    owner.program_domain_quote is None &&
    request_portable_model_whole_file_current(owner, selected) &&
    owner.compiled_program is Some(prepared) else {
    return Err(ForeignOriginal)
  }
  match
    reserve_request_whole_file_provider_selection(owner, input, selected, {
      // An empty checked input sequence, its array/option, and lowerer controls.
      record_headers: 9L,
      reference_slots: 15L,
      scalar_words: 16L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }) {
    Ok(_) => ()
    Err(Preparation(Capacity(issue))) => return Err(Preparation(issue))
    Err(_) => return Err(ForeignOriginal)
  }
  prepare_installed_whole_source_capacity_original(
    prepared,
    selected.source,
    Some(declaration),
    contracts,
    limits,
    None,
    input_only=true,
  )
}

///|
/// Fund a provider's retained choice on this exact selected Whole Request.
/// The owner must still be in the pre-module phase on the same input.
pub fn[I] reserve_request_whole_file_provider_selection(
  owner : ClientRequestPreparation[I],
  input : I,
  selected : ClientRequestWholeFileInput[I],
  units : @execution.PreparationRepresentationUnits,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  guard physical_equal(selected.owner, owner) &&
    (
      owner.phase == ProgramPlanReserved ||
      request_portable_model_whole_file_current(owner, selected)
    ) &&
    !owner.program_body_attempted &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) else {
    return Err(Preparation(ForeignOriginal))
  }
  guard @execution.preparation_representation_cost(units) is Some(bytes) else {
    return Err(Preparation(Policy))
  }
  let phase = owner.phase
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => Err(issue)
        Ok(_) => {
          owner.program_domain_quote = None
          owner.phase = phase
          Ok(())
        }
      }
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
pub enum ClientRequestWholeFileModuleIssue {
  WholeFileCapacity(ClientInstalledManagedRunIssue)
  WholeFilePlan(ClientInstalledManagedRunIssue)
  WholeFileCompilerLimits(ClientRequestProgramPlanIssue)
  WholeFileModule(ClientRequestProgramPlanIssue)
}

///|
/// Construct the existing singleton Whole Plan and captured module on the
/// same owner that reserved this File Source. The caller still owns provider
/// admission, Source I/O and adoption of the finished Request as a Run.
pub fn[I] prepare_request_whole_file_module(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  selected : ClientRequestWholeFileInput[I],
  declaration : @row_source_host.RowDeclaration,
  contracts : ClientInstalledSequenceContracts,
  input_limits : @row_source_host.RowInputLimits,
  provider : @execution.ExecutionCapacity?,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  manifests~ : @publication_host.ClientCompilationManifests,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[
  ClientInstalledWholeSourceCapacity,
  ClientRequestWholeFileModuleIssue,
] {
  guard physical_equal(selected.owner, owner) &&
    physical_equal(selected.request, request) &&
    owner.phase == ProgramPlanReserved &&
    !owner.program_body_attempted &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) else {
    return Err(WholeFileModule(Preparation(ForeignOriginal)))
  }
  let capacity = match
    prepare_installed_whole_source_capacity(
      prepared,
      selected.source,
      declaration,
      contracts,
      input_limits,
      provider,
    ) {
    Err(issue) => return Err(WholeFileCapacity(issue))
    Ok(value) => value
  }
  let plan = match
    prepare_installed_managed_whole_source_plan(
      prepared,
      request,
      capacity,
      transport_bytes,
      transport_execution_bytes,
      contracts,
      contracts.original.values_body,
      contracts.original.fragment_body,
      contracts.original.ordered_body,
      retained_output~,
      provider_factory~,
      runtime_admission=true,
    ) {
    Err(issue) => return Err(WholeFilePlan(issue))
    Ok(value) => value
  }
  let compilation_limits = match
    request_program_compilation_limits(owner, input) {
    Err(issue) => return Err(WholeFileCompilerLimits(issue))
    Ok(value) => value
  }
  prepare_request_capture_module_body(
    owner,
    input,
    plan,
    manifests~,
    compilation_limits~,
    provider_factory~,
  )
  .map(_ => capacity)
  .map_err(issue => WholeFileModule(issue))
}

///|
/// The checked construction choice for this Native file Request. The same
/// original occurrence inventory reaches the selected constructor.
pub enum ClientRequestNativeFileSourceInputs {
  WholeSourceInputs(
    @publication_host.ClientDirectAcquisitionOccurrences,
    Array[@sourceviews.SourceAcquisition]
  )
  QuerySourceInputs(
    @planning.QueryEvidenceContracts,
    @publication_host.ClientDirectAcquisitionOccurrences
  )
  MissingQueryContracts
}

///|
pub enum ClientRequestNativeFileSourceIssue {
  NativeFileSourceSelection(ClientRequestProgramPlanIssue)
  NativeFileWholeConstruction(ClientRequestProgramPlanIssue)
  NativeFileQueryContracts(ClientRequestProgramPlanIssue)
}

///|
/// Select the same funded Native File inputs while a compiled Model Request
/// still owns its Plan preparation. An empty Whole list selects Query; its
/// protocol documents are admitted by the Model module constructor.
pub fn[I] reserve_request_model_file_source_inputs(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  (
    @publication_host.ClientDirectAcquisitionOccurrences,
    Array[@sourceviews.SourceAcquisition],
  ),
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_compilation is Some(@publication_host.Tasks(_)) &&
    (match owner.program_domain_compilation_inputs {
      Some(RequestModelCompilation(_, _, _, _))
      | Some(RequestModelsCompilation(_, _, _, _)) => true
      _ => false
    }) &&
    owner.program_source_free is None &&
    owner.program_captured is None &&
    owner.program_model is None else {
    return Err(Preparation(ForeignOriginal))
  }
  preparation_module_call(
    () => {
      let (direct, sources) = match
        reserve_request_whole_source_routes(
          owner,
          input,
          request,
          select_query=true,
          phase=ModelPlanReserved,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      if !sources.is_empty() {
        return reserve_request_selected_whole_source_inputs(
          owner,
          input,
          sources,
          phase=ModelPlanReserved,
        ).map(_ => (direct, sources))
      }
      // File Query retains declarations, rows, provider capacities and the
      // shared transport vector while the module makes its acquisitions.
      // The existing five-vector quote also covers the final locators. Count
      // the separate empty Whole array and these original capacity carriers.
      let count = @publication_host.client_direct_acquisition_occurrence_count(
        direct,
      ).to_int64()
      guard owner.compiled_program is Some(prepared) &&
        @execution.preparation_array_representation(1L, 0L, true) is Some(empty) &&
        @execution.preparation_representation_cost({
          ..empty,
          record_headers: empty.record_headers + count + 1L,
          reference_slots: empty.reference_slots + count + 1L,
          scalar_words: empty.scalar_words + count + 1L,
        })
        is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      owner.program_domain_quote = None
      owner.phase = ModelPlanReserved
      Ok((direct, sources))
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
/// Fund and inspect the exact checked occurrence inventory before choosing
/// a Native file constructor. A failed Query is terminal. Whole requires
/// complete-input selection for each original, even when several share a task.
pub fn[I] prepare_request_native_file_source_inputs(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  bodies : (String, String)?,
) -> Result[
  ClientRequestNativeFileSourceInputs,
  ClientRequestNativeFileSourceIssue,
] {
  preparation_module_call(
    () => {
      let (direct, sources) = match
        reserve_request_whole_source_routes(
          owner,
          input,
          request,
          select_query=true,
        ) {
        Err(issue) => return Err(NativeFileSourceSelection(issue))
        Ok(value) => value
      }
      if !sources.is_empty() {
        return reserve_request_selected_whole_source_inputs(
            owner, input, sources,
          )
          .map(_ => {
            ClientRequestNativeFileSourceInputs::WholeSourceInputs(
              direct, sources,
            )
          })
          .map_err(issue => NativeFileWholeConstruction(issue))
      }
      // The selector requires at least one original and refuses mixed routes.
      // No Whole Source original here therefore means every route was Query.
      guard owner.phase == Selecting && owner.compiled_program is Some(prepared) else {
        return Err(NativeFileSourceSelection(Preparation(ForeignOriginal)))
      }
      owner.program_domain_quote = None
      owner.phase = ProgramPlanReserved
      guard bodies is Some((query, evidence)) else {
        return Ok(MissingQueryContracts)
      }
      admit_request_query_acquisition_contracts_for_original(
        owner, input, prepared, direct, query, evidence,
      )
      .map(value => {
        ClientRequestNativeFileSourceInputs::QuerySourceInputs(value.0, value.1)
      })
      .map_err(issue => NativeFileQueryContracts(issue))
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}
