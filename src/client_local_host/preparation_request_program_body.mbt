///|
/// Select the actual completed compiler output on the SAME Request parent.
/// The original initial admission, input, reservation and work history survive.
/// Only fixed continuation controls are constructed; no wrapper census or new
/// allowance is introduced. The capacity never escapes as a mutable Ledger.
pub fn[I] continue_request_program_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientRequestPreparationIssue,
] {
  guard owner.phase == ProgramCheck &&
    owner.program_capacity is None &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == CompilationComplete &&
    child.compiled_program is Some(prepared) &&
    child.check_data is Some(data) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  match clear_request_parameter_source(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Return the already transferred Source controller's local aliases before
  // selecting the final body. Its output is retained by this exact compiler.
  if owner.program_json is Some(source) {
    match clear_program_json_preparation(source) {
      Err(issue) => return Err(ProgramJson(issue))
      Ok(_) => ()
    }
  }
  owner.phase = Selecting
  child.busy = true
  let next : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ] = match @resources.continue_preparation_capacity(owner.capacity, input) {
    Err(issue) => {
      child.busy = false
      owner.phase = ProgramCheck
      return Err(Capacity(issue))
    }
    Ok(value) => value
  }
  // Retain the same successor before cutting the original child aliases.
  owner.program_capacity = Some(next)
  owner.compiled_program = Some(prepared)
  owner.program_data = Some(data)
  transfer_program_check_input(child)
  child.busy = false
  owner.program_check = None
  owner.computation_limits = None
  owner.program_json = None
  owner.phase = ProgramCompiled
  Ok(prepared)
}

///|
/// Fund the selected Plan/module constructor before the existing caller enters
/// it. These new arrays/sequence/Plan data coexist with the retained compiler;
/// reuse its original dimensions once, not another parse/check or Plan quote.
fn[I] request_program_plan_quote(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[(Int64, Int64), ClientRequestPreparationIssue] {
  guard (
      owner.phase == ProgramCompiled ||
      owner.phase == ProgramPlanQuoted ||
      owner.phase == ProgramPlanReserved
    ) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_data is Some(data) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if owner.phase == ProgramCompiled {
    let (r, e) = match
      original_request_plan_construction_quote(capacity, input, data) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    owner.program_plan_quote = Some((r, e))
    owner.phase = ProgramPlanQuoted
  }
  Ok(owner.program_plan_quote.unwrap())
}

///|
pub fn[I] reserve_request_program_plan(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.phase != ProgramCompiled && owner.phase != ProgramPlanQuoted {
    return Err(WrongPhase)
  }
  let (r, e) = match request_program_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capacity = owner.program_capacity.unwrap()
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  )
  owner.phase = if result is Ok(_) {
    ProgramPlanReserved
  } else {
    ProgramPlanQuoted
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Original immutable constructor input on the SAME reservation, not a ready
/// Plan/body or Run permission. Existing borrowers keep it live during awaits,
/// failed construction and actual retirement, using the common return engine.
pub fn[I] borrow_request_program_plan_input(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  ClientRequestPreparationIssue,
] {
  let (r, e) = match request_program_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capacity = owner.program_capacity.unwrap()
  let prepared = owner.compiled_program.unwrap()
  let reserved = owner.phase == ProgramPlanReserved
  // An already reserved phase may contain later domain growth. Preserve its
  // current extent; never reapply an earlier, smaller quote or recalculate it.
  let (r, e) = if reserved {
    match @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
  } else {
    (r, e)
  }
  owner.phase = Selecting
  let result = @resources.reserve_preparation_construction_input(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) || reserved {
    ProgramPlanReserved
  } else {
    ProgramPlanQuoted
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Bind the actual same-owner installed Plan/configuration after its funded
/// constructor returns. No body or Plan is reconstructed. Retain the full peak
/// across this handoff; retired scratch is not guessed from a returned value.
pub fn[I] complete_request_program_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedSourceFreePreparation,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ProgramPlanReserved &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    plan.owner is Pure(original_prepared) &&
    physical_equal(original_prepared, prepared) &&
    plan.configuration is Some(_) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  owner.program_source_free = Some(plan)
  owner.program_body_attempted = true
  owner.phase = Selecting
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
pub suberror ClientRequestProgramPlanIssue {
  Preparation(ClientRequestPreparationIssue)
  Installed(ClientInstalledManagedRunIssue)
  Construction(@publication_host.ClientValuesExecutablePlanIssue)
  ValuesCompilation(@publication_host.ClientValuesCompilationIssue)
  TaskCompilation(@publication_host.ClientTaskCompilationIssue)
}

///|
/// Construct the selected installed Plan/module from the SAME completed
/// compiler output. Variable sequence/Plan data uses the existing retained
/// estimate once, before construction. Fixed provider/control wrappers remain
/// trusted Host overhead; no closed-Values census or second checker is used.
/// No raw Prepared leaves this call: the next original body borrower reads it
/// only after the Plan/configuration and capacity completion are retained.
pub fn[I] prepare_request_program_module_body(
  owner : ClientRequestPreparation[I],
  input : I,
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  if owner.program_body_attempted ||
    owner.program_artifact_work is Some(_) ||
    owner.program_artifact_work_issue is Some(_) {
    return Err(Preparation(WrongPhase))
  }
  if owner.phase != ProgramPlanReserved {
    match reserve_request_program_plan(owner, input) {
      Err(issue) => return Err(Preparation(issue))
      Ok(_) => ()
    }
  }
  guard owner.phase == ProgramPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) else {
    return Err(Preparation(ForeignOriginal))
  }
  if owner.program_artifact_inputs
    is Some(
      (
        original_manifests,
        original_limits,
        original_contracts,
        original_output,
        original_factory,
      )
    ) {
    if !physical_equal(original_manifests, manifests) ||
      original_limits != compilation_limits ||
      !physical_equal(original_contracts, contracts) ||
      original_output != retained_output ||
      !physical_equal(original_factory, provider_factory) {
      return Err(Preparation(ForeignOriginal))
    }
  } else {
    owner.program_artifact_inputs = Some(
      (
        manifests, compilation_limits, contracts, retained_output, provider_factory,
      ),
    )
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      let installed = contracts.original
      let plan = match owner.program_source_free {
        Some(original) => original
        None =>
          match
            prepare_installed_managed_source_free_with_contracts(
              prepared,
              contracts,
              installed.values_body,
              installed.fragment_body,
              installed.ordered_body,
              retained_output~,
              provider_factory~,
            ) {
            Err(issue) => return Err(Installed(issue))
            Ok(value) => {
              owner.program_source_free = Some(value)
              value
            }
          }
      }
      let limits = compilation_limits
      let sequence = @publication_host.prepared_client_values_sequence_limits(
        prepared,
      )
      let geometry = match owner.program_artifact_geometry {
        Some(original) => original
        None => {
          let capacity = owner.program_capacity.unwrap()
          let (r, e) = match owner.program_measurement_quote {
            Some(original) => original
            None => {
              // This is the actual measurement's variable returned storage,
              // not codec headroom, fixed call wrappers or its nested helpers.
              let units = match
                @publication_host.prepared_client_pure_measurement_storage(
                  prepared, limits,
                ) {
                Err(issue) => return Err(Construction(issue))
                Ok(value) => value
              }
              guard @execution.preparation_representation_cost(units)
                is Some(bytes) else {
                return Err(Preparation(Policy))
              }
              let (r, e) = match
                @resources.preparation_capacity_working_extents(capacity, input) {
                Err(issue) => return Err(Preparation(Capacity(issue)))
                Ok(value) => value
              }
              guard @execution.checked_preparation_add_product(r, bytes, 1L)
                is Some(r) &&
                @execution.checked_preparation_add_product(e, bytes, 1L)
                is Some(e) else {
                return Err(Preparation(Policy))
              }
              owner.program_measurement_quote = Some((r, e))
              (r, e)
            }
          }
          match
            @resources.reserve_working_preparation_phase(capacity, input, r, e) {
            Err(issue) => {
              owner.phase = ProgramPlanReserved
              return Err(Preparation(Capacity(issue)))
            }
            Ok(_) => ()
          }
          match
            @publication_host.measure_prepared_client_pure_compilation_construction(
              prepared,
              manifests,
              sequence,
              limits.max_facts,
              limits.max_witnesses,
              limits.max_wire_bytes,
              limits.max_nodes,
              limits.max_depth,
            ) {
            Err(issue) => return Err(Construction(issue))
            Ok(value) => {
              owner.program_artifact_geometry = Some(value)
              value
            }
          }
        }
      }
      let capacity = owner.program_capacity.unwrap()
      let (r, e) = match owner.program_artifact_quote {
        Some(original) => original
        None => {
          guard program_artifact_construction_cost(geometry) is Some(bytes) else {
            return Err(Preparation(Policy))
          }
          let (r, e) = match
            @resources.preparation_capacity_working_extents(capacity, input) {
            Err(issue) => return Err(Preparation(Capacity(issue)))
            Ok(value) => value
          }
          guard @execution.checked_preparation_add_product(r, bytes, 1L)
            is Some(r) &&
            @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
            return Err(Preparation(Policy))
          }
          owner.program_artifact_quote = Some((r, e))
          (r, e)
        }
      }
      match
        @resources.reserve_working_preparation_phase(capacity, input, r, e) {
        Err(issue) => {
          // The original module, immutable measurement and absolute quote
          // survive a declined grow. Never repeat its factory on continuation.
          owner.phase = ProgramPlanReserved
          return Err(Preparation(Capacity(issue)))
        }
        Ok(_) => ()
      }
      // The original hash and text writers each visit at most the quoted
      // complete Plan value nodes. This bounds only this known dimension;
      // string, parser, contract and other compiler work is not inferred here.
      let work = match
        @resources.begin_preparation_phase_work64(
          capacity,
          input,
          @resources.ExecutionPlan,
          2L * geometry.executable_plan.1.to_int64(),
        ) {
        Err(issue) => return Err(Preparation(Work(issue)))
        Ok(value) => value
      }
      owner.program_artifact_work = Some(work)
      let attempted : Result[
        @publication_host.ClientRunCompilation,
        ClientRequestProgramPlanIssue,
      ] = if geometry.tasks {
        @publication_host.observe_prepared_client_task_plan_encoding(
          prepared,
          manifests,
          sequence,
          limits.max_facts,
          limits.max_witnesses,
          limits.max_wire_bytes,
          limits.max_nodes,
          limits.max_depth,
          nodes_out=owner.program_artifact_plan_encoding_nodes,
        )
        .map(value => @publication_host.ClientRunCompilation::Tasks(value))
        .map_err(issue => TaskCompilation(issue))
      } else {
        @publication_host.observe_prepared_client_values_plan_encoding(
          prepared,
          manifests,
          sequence,
          limits.max_facts,
          limits.max_witnesses,
          limits.max_wire_bytes,
          limits.max_nodes,
          limits.max_depth,
          nodes_out=owner.program_artifact_plan_encoding_nodes,
        )
        .map(value => @publication_host.ClientRunCompilation::Values(value))
        .map_err(issue => ValuesCompilation(issue))
      }
      match finish_request_program_artifact_work(owner) {
        Err(issue) => return Err(Preparation(issue))
        Ok(_) => ()
      }
      let artifact = match attempted {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      plan.compilation = Some(artifact)
      owner.phase = ProgramPlanReserved
      let completed = complete_request_program_preparation(owner, input, plan)
      if completed is Ok(_) {
        // The actual Plan now owns its compilation. Measurement/retry DATA
        // has no subsequent consumer; do not retain another per-task graph
        // inventory through the SDK body borrower or the eventual Run.
        // Keep the peak reservation until this constructor has unwound.
        owner.program_measurement_quote = None
        owner.program_artifact_geometry = None
        owner.program_artifact_quote = None
        owner.program_artifact_inputs = None
      }
      completed.map_err(issue => Preparation(issue))
    },
    () => {
      // This SAME scope runs after synchronous foreign unwind as well. The
      // original output cell was retained before entry; no replay is needed
      // to close its existing work receipt or preserve an observed prefix.
      ignore(finish_request_program_artifact_work(owner))
      if owner.phase == Selecting {
        owner.phase = ProgramBodyFailed
      }
    },
  )
}

///|
// Work closure is separate from physical/body retirement. The observed
// per-invocation count remains in its original cell after receipt completion,
// body transfer and cleanup; it never becomes current occupancy or a refill.
fn[I] finish_request_program_artifact_work(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.program_artifact_work is Some(work) {
    if !owner.program_artifact_work_charged {
      // A declined finish keeps the original receipt, but must not spend
      // this already returned constructor's observation a second time.
      owner.program_artifact_work_charged = true
      match
        @resources.spend_preparation_phase_work64(
          work,
          owner.program_artifact_plan_encoding_nodes.val,
        ) {
        Err(issue) => owner.program_artifact_work_issue = Some(issue)
        Ok(_) => ()
      }
    }
    match @resources.finish_preparation_phase_work64(work) {
      Err(issue) => {
        owner.program_artifact_work_issue = Some(issue)
        return Err(Work(issue))
      }
      Ok(spent) => {
        owner.program_artifact_work_spent = spent
        owner.program_artifact_work = None
      }
    }
    if owner.program_artifact_work_issue is None &&
      owner.program_artifact_work_spent !=
      owner.program_artifact_plan_encoding_nodes.val {
      owner.program_artifact_work_issue = Some(@resources.InvalidWork)
    }
    if owner.program_artifact_work_issue is Some(issue) {
      return Err(Work(issue))
    }
  }
  Ok(())
}

///|
/// Existing original body token for the fixed manager. Live borrowers keep the
/// reservation during retirement. This neither admits a Run nor proves stop.
pub fn[I] borrow_request_program_preparation(
  owner : ClientRequestPreparation[I],
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  ClientRequestPreparationIssue,
] {
  guard owner.phase == ProgramBodyReady &&
    owner.program_capacity is Some(capacity) else {
    return Err(WrongPhase)
  }
  owner.phase = Selecting
  let result = @resources.borrow_preparation_body(capacity)
  owner.phase = ProgramBodyReady
  result.map_err(issue => Capacity(issue))
}

///|
/// Adopt this SAME initial admission/capacity/installed Plan into the existing
/// preparation-owned source-free Run. Captured Source and Effect consumers
/// retain their separate original Plan contracts; there is no None fallback.
pub fn[I] begin_request_program_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == ProgramBodyReady &&
    owner.input is Some(input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_source_free is Some(plan) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = begin_preparation_owned_installed_managed_run(
    owner.initial,
    input,
    capacity,
    prepared,
    request,
    plan,
  )
  match result {
    Err(issue) => {
      owner.phase = ProgramBodyReady
      Err(issue)
    }
    Ok(run) => {
      // The Run has retained its original cleanup custody and body holders.
      // No callback occurs while cutting this consumed parent's heavy aliases.
      owner.program_capacity = None
      owner.compiled_program = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.program_measurement_quote = None
      owner.program_artifact_geometry = None
      owner.program_artifact_quote = None
      owner.program_artifact_inputs = None
      owner.program_source_free = None
      owner.native_parameters = None
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

///|
// One shared original sequence/Plan data envelope for both typed body choices.
// This prices DATA only; the caller retains the same capacity and phase guard.
fn[I, P] original_request_plan_construction_quote(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  data : @checked.ParsedCheckDataEstimate,
) -> Result[(Int64, Int64), ClientRequestPreparationIssue] {
  guard program_check_data_extent_cost(data) is Some(bytes) else {
    return Err(Policy)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(Policy)
  }
  Ok((r, e))
}
