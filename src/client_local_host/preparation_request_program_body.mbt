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
  clear_request_parameter_source(owner)
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
      owner.phase == ProgramPlanReserved ||
      owner.phase == ProgramPlanReserved ||
      owner.phase == ModelPlanReserved ||
      owner.phase == ContentPlanReserved
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
/// Back the existing timed Host constructor before it issues the first Run,
/// Definition or QueryTime. The compiler original and all prior growth stay on
/// this same Request. The cached absolute target permits a declined grow to
/// resume without another compiler, quote, constructor or reservation owner.
pub fn[I] reserve_request_query_time_invocation(
  owner : ClientRequestPreparation[I],
  input : I,
  compilation : @publication_host.ClientRunCompilation,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  guard owner.phase == ProgramPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(_) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_compilation is Some(artifact) &&
    physical_equal(artifact, compilation) &&
    !owner.program_body_attempted else {
    return Err(Preparation(ForeignOriginal))
  }
  let target = match owner.program_invocation_quote {
    Some(target) => target
    None => {
      guard owner.program_artifact_geometry is Some(geometry) &&
        request_query_time_invocation_extent(geometry)
        is Some((retained, execution)) else {
        return Err(Preparation(Policy))
      }
      let (r, e) = match
        @resources.preparation_capacity_working_extents(capacity, input) {
        Err(issue) => return Err(Preparation(Capacity(issue)))
        Ok(value) => value
      }
      guard @execution.checked_preparation_add_product(r, retained, 1L)
        is Some(r) &&
        @execution.checked_preparation_add_product(e, execution, 1L) is Some(e) else {
        return Err(Preparation(Policy))
      }
      let target = (r, e)
      owner.program_invocation_quote = Some(target)
      target
    }
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      let result = @resources.reserve_working_preparation_phase(
        capacity,
        input,
        target.0,
        target.1,
      )
      owner.phase = ProgramPlanReserved
      result.map_err(issue => Preparation(Capacity(issue)))
    },
    (
    // A foreign current throw cannot leave the constructor open for replay.
    // Original input/quote and occupied capacity remain for existing cleanup.
    ) => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
// One bounded invocation group: checked views of the original emitted Plan and
// material plus prepared/auth/Definition metadata. The three metadata codecs are
// the existing100000-byte/10000-node/100-depth issuers, never multiplied by tasks.
// The shared trusted control group is prepaid by the initial Request entrance.
fn request_query_time_invocation_extent(
  original : @publication_host.ClientPureCompilationConstruction,
) -> (Int64, Int64)? {
  let mut retained = 0L
  let mut scratch = 0L
  for
    geometry in [
      original.executable_plan,
      original.material,
      (100000, 10000, 100),
      (100000, 10000, 100),
      (100000, 10000, 100),
    ] {
    guard program_artifact_parse_layout(geometry) is Some(parse) &&
      @execution.preparation_representation_cost(parse.value) is Some(value) &&
      @execution.preparation_representation_cost(parse.temporary)
      is Some(temporary) &&
      @execution.checked_preparation_add_product(retained, value, 1L)
      is Some(next) &&
      compilation_writer_ancestry_layout(
        geometry.1,
        geometry.2,
        geometry.1,
        1,
        1,
        geometry.0,
      )
      is Some(writer) &&
      @execution.preparation_representation_cost(writer) is Some(writer) &&
      @execution.checked_preparation_add_product(
        next,
        geometry.0.to_int64(),
        4L,
      )
      is Some(next) else {
      return None
    }
    retained = next
    scratch = Int64::max(scratch, Int64::max(temporary, writer))
  }
  // A restored original Definition is JSON-parsed by the same JS constructor
  // before native admission. Its input is fenced at100000 UTF16units there;
  // every value needs at least one unit. The existing logical value-node tariff
  // bounds that one live parse, separately from native successful-codec nodes.
  guard @execution.checked_preparation_add_product(
      200000L,
      100000L,
      @execution.execution_capacity_node_bytes(),
    )
    is Some(restored_parse) &&
    @execution.checked_preparation_add_product(
      retained,
      Int64::max(scratch, restored_parse),
      1L,
    )
    is Some(execution) else {
    return None
  }
  Some((retained, execution))
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
  if owner.phase == ModelPlanReserved || owner.phase == ContentPlanReserved {
    return Err(WrongPhase)
  }

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
  guard owner.program_model is None &&
    plan.owner is Pure(prepared) &&
    installed_managed_run_purpose_supported(prepared) else {
    return Err(WrongPhase)
  }
  complete_request_program_preparation_owned(owner, input, plan)
}

///|
// Fixed ordinary/Model callers selected their original purpose and Plan.
// Share only the exact same body completion and peak reservation handoff.
fn[I] complete_request_program_preparation_owned(
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
  CapacityExceeded(ClientPreparationCapacityRefusal)
  Preparation(ClientRequestPreparationIssue)
  Installed(ClientInstalledManagedRunIssue)
  Construction(@publication_host.ClientValuesExecutablePlanIssue)
  ValuesCompilation(@publication_host.ClientValuesCompilationIssue)
  TaskCompilation(@publication_host.ClientTaskCompilationIssue)
  QueryTime(@publication_host.ClientQueryTimeIssue)
  SerializationGraph(@publication_host.ClientSerializationPlanGraphIssue)
  ModelGraph(@publication_host.ClientInferPlanGraphIssue)
  ModelBinding(@publication.RunEvidenceValueIssue)
  ModelQuery(ClientLocalQueryIssue)
  ModelSource(@row_source_host.RowHostIssue)
  ContentQuery(ClientLocalQueryIssue)
  ContentSource(@row_source_host.RowHostIssue)
}

///|
/// Emit and retain the original execution compilation before its module when
/// the invocation must bind QueryTime to an admitted Run first. The same input,
/// contracts, factory identity and existing measured writer receipt are retained.
/// This is neither a ready module nor another Root or compiler implementation.
pub fn[I] prepare_request_program_compilation(
  owner : ClientRequestPreparation[I],
  input : I,
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[
  @publication_host.ClientRunCompilation,
  ClientRequestProgramPlanIssue,
] {
  if owner.program_compilation is Some(_) {
    return Err(Preparation(WrongPhase))
  }
  let prepared = match
    retain_request_program_module_inputs(
      owner,
      input,
      contracts,
      None,
      manifests~,
      compilation_limits~,
      retained_output~,
      provider_factory~,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
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
        Err(issue) => Err(issue)
        Ok(artifact) => {
          owner.phase = ProgramPlanReserved
          Ok(artifact)
        }
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
  invocation? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
  )? = None,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  prepare_request_program_module_body_owned(
    owner,
    input,
    contracts,
    None,
    manifests~,
    compilation_limits~,
    retained_output~,
    provider_factory~,
    invocation~,
  )
}

///|
/// Preserve the captured Plan's actual original compilation under the SAME
/// artifact measurement/work and Request capacity as the source-free path.
/// Plan construction and its supplied domain must already be backed.
pub fn[I] prepare_request_capture_module_body(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedCapturePlan,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  invocation? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
  )? = None,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  prepare_request_program_module_body_owned(
    owner,
    input,
    plan.installed_contracts,
    Some(plan),
    manifests~,
    compilation_limits~,
    retained_output=plan.configuration.retained_output,
    provider_factory~,
    invocation~,
  )
}

///|
fn[I] retain_request_program_module_inputs(
  owner : ClientRequestPreparation[I],
  input : I,
  contracts : ClientInstalledSequenceContracts,
  captured : ClientInstalledManagedCapturePlan?,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientRequestProgramPlanIssue,
] {
  if owner.program_model is Some(_) ||
    owner.program_domain_compilation_inputs is Some(_) ||
    owner.program_body_attempted ||
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
  if !installed_managed_run_purpose_supported(prepared) {
    return Err(Installed(Unsupported))
  }
  match (owner.program_captured, captured) {
    (Some(original), Some(plan)) if !physical_equal(original, plan) =>
      return Err(Preparation(ForeignOriginal))
    (Some(_), None) => return Err(Preparation(ForeignOriginal))
    _ => ()
  }
  if captured is Some(plan) {
    if !physical_equal(plan.prepared, prepared) ||
      !physical_equal(plan.installed_contracts, contracts) ||
      plan.values_body != contracts.original.values_body ||
      plan.fragment_body != contracts.original.fragment_body ||
      plan.ordered_body != contracts.original.ordered_body ||
      plan.configuration.retained_output != retained_output ||
      owner.program_source_free is Some(_) {
      return Err(Preparation(ForeignOriginal))
    }
    // Retain the original selected Plan before any callback/measurement can
    // fail. This adds no second compilation or cleanup owner.
    owner.program_captured = Some(plan)
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
  Ok(prepared)
}

///|
fn[I] prepare_request_program_module_body_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  contracts : ClientInstalledSequenceContracts,
  captured : ClientInstalledManagedCapturePlan?,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  invocation? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
  )? = None,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  let prepared = match
    retain_request_program_module_inputs(
      owner,
      input,
      contracts,
      captured,
      manifests~,
      compilation_limits~,
      retained_output~,
      provider_factory~,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      let installed = contracts.original
      // These are the original invocation objects, not a clock value or a
      // caller-supplied proof. Bind only the compiler retained by this parent.
      let query_time = match invocation {
        Some((original, request, compiled, definition)) => {
          guard owner.program_compilation is Some(artifact) else {
            return Err(Preparation(WrongPhase))
          }
          if !@publication_host.client_compiled_run_matches_pure_compilation(
              compiled, prepared, artifact,
            ) {
            return Err(Preparation(ForeignOriginal))
          }
          if captured is Some(plan) &&
            (
              !physical_equal(plan.request, request) ||
              !(plan._observed_query_time is Some(selected) &&
              physical_equal(selected, original))
            ) {
            return Err(Preparation(ForeignOriginal))
          }
          match
            @publication_host.client_query_time_preparation_context_for_run(
              original, prepared, compiled, definition, request,
            ) {
            Err(issue) => return Err(QueryTime(issue))
            Ok(_) => ()
          }
          Some((original, request))
        }
        None => {
          if captured is Some(plan) && plan._observed_query_time is Some(_) {
            return Err(Preparation(WrongPhase))
          }
          None
        }
      }
      // Forward the exact already-admitted immutable catalogue before any
      // module callback, measurement or retained compiler emission exists.
      if owner.program_compilation is None {
        match
          @publication_host.bind_prepared_client_compiler_contracts(
            prepared,
            installed.value.ordered_contract,
          ) {
          Err(_) => return Err(Preparation(ForeignOriginal))
          Ok(_) => ()
        }
      }
      let plan = if captured is Some(_) {
        None
      } else {
        Some(
          match owner.program_source_free {
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
                  query_time~,
                ) {
                Err(issue) => return Err(Installed(issue))
                Ok(value) => {
                  owner.program_source_free = Some(value)
                  value
                }
              }
          },
        )
      }
      // This exact configured Plan is already retained by the Request. Check
      // the same initial admission before completing its body or adopting a Run.
      // These immutable quantities neither grant bytes nor establish currentness.
      if plan is Some(original) {
        let available = match
          @resources.node_local_preparation_limits(owner.initial, input) {
          Err(issue) => return Err(Installed(Resource(issue)))
          Ok(value) => value
        }
        let required = original.limits
        if required.retained_bytes > available.retained_bytes ||
          required.execution_bytes > available.execution_bytes {
          return Err(
            CapacityExceeded({
              phase: "source_free_plan",
              dimension: if required.retained_bytes > available.retained_bytes {
                "retention"
              } else {
                "execution"
              },
              required_retention: required.retained_bytes,
              required_execution: required.execution_bytes,
              available_retention: available.retained_bytes,
              available_execution: available.execution_bytes,
            }),
          )
        }
        if !installed_effect_limits_fit(required, available) {
          return Err(Installed(InsufficientCapacity))
        }
      }
      let artifact = match
        prepare_request_compilation_owned(
          owner, input, prepared, manifests, compilation_limits,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      owner.phase = ProgramPlanReserved
      let completed = match captured {
        Some(original) => {
          original.compilation = Some(artifact)
          complete_request_capture_preparation(owner, input, original)
        }
        None => {
          let original = plan.unwrap()
          original.compilation = Some(artifact)
          complete_request_program_preparation(owner, input, original)
        }
      }
      if completed is Ok(_) {
        // The actual Plan now owns its compilation. Measurement/retry DATA
        // has no subsequent consumer; do not retain another per-task graph
        // inventory through the SDK body borrower or the eventual Run.
        // Keep the peak reservation until this constructor has unwound.
        owner.program_measurement_quote = None
        owner.program_artifact_geometry = None
        owner.program_artifact_quote = None
        owner.program_artifact_inputs = None
        owner.program_compilation = None
        owner.program_domain_compilation_inputs = None
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
// SAME measure/absolute grow/work receipt for ordinary and selected Model
// compilers. Callers retain their original module or Graph before entry.
fn[I] prepare_request_compilation_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  manifests : @publication_host.ClientCompilationManifests,
  compilation_limits : @publication_host.ClientPureCompilationLimits,
) -> Result[
  @publication_host.ClientRunCompilation,
  ClientRequestProgramPlanIssue,
] {
  if owner.program_compilation is Some(original) {
    return Ok(original)
  }
  let limits = compilation_limits
  let domain = owner.program_domain_compilation_inputs
  let continuation_phase = match domain {
    Some(RequestEffectCaptureRecovery(_, _))
    | Some(RequestSerializationGraph(_, _, _, _))
    | Some(RequestModelGraphConstruction(_, _, _, _))
    | Some(RequestModelGraph(_, _, _, _)) => return Err(Preparation(WrongPhase))
    Some(RequestModelCompilation(_, _, _, _)) => ModelPlanReserved
    Some(RequestSerializationCompilation(_, _, _, _))
    | Some(RequestKeyedSerializationCompilation(_, _, _, _)) =>
      ContentPlanReserved
    None => ProgramPlanReserved
  }
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
            (match domain {
              Some(RequestEffectCaptureRecovery(_, _))
              | Some(RequestSerializationGraph(_, _, _, _))
              | Some(RequestModelGraphConstruction(_, _, _, _))
              | Some(RequestModelGraph(_, _, _, _)) =>
                return Err(Preparation(WrongPhase))
              Some(RequestModelCompilation(_, _, _, graph)) =>
                @publication_host.prepared_client_model_measurement_storage(
                  prepared,
                  [graph],
                  limits,
                )
              Some(RequestSerializationCompilation(_, _, _, component))
              | Some(RequestKeyedSerializationCompilation(_, _, _, component)) =>
                @publication_host.prepared_client_serialization_measurement_storage(
                  prepared, component, limits,
                )
              None =>
                @publication_host.prepared_client_pure_measurement_storage(
                  prepared, limits,
                )
            }) {
            Err(issue) => return Err(Construction(issue))
            Ok(value) => value
          }
          guard @execution.preparation_representation_cost(units) is Some(bytes) else {
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
          owner.program_measurement_quote = Some((r, e))
          (r, e)
        }
      }
      match
        @resources.reserve_working_preparation_phase(capacity, input, r, e) {
        Err(issue) => {
          owner.phase = continuation_phase
          return Err(Preparation(Capacity(issue)))
        }
        Ok(_) => ()
      }
      match
        (match domain {
          Some(RequestEffectCaptureRecovery(_, _))
          | Some(RequestSerializationGraph(_, _, _, _))
          | Some(RequestModelGraphConstruction(_, _, _, _))
          | Some(RequestModelGraph(_, _, _, _)) =>
            return Err(Preparation(WrongPhase))
          Some(RequestModelCompilation(_, _, _, graph)) =>
            @publication_host.measure_prepared_client_model_compilation_construction(
              prepared,
              [graph],
              manifests,
              sequence,
              limits.max_facts,
              limits.max_witnesses,
              limits.max_wire_bytes,
              limits.max_nodes,
              limits.max_depth,
            )
          Some(RequestSerializationCompilation(_, _, _, component))
          | Some(RequestKeyedSerializationCompilation(_, _, _, component)) =>
            @publication_host.measure_prepared_client_serialization_compilation_construction(
              prepared, component, manifests, limits,
            )
          None =>
            @publication_host.measure_prepared_client_pure_compilation_construction(
              prepared,
              manifests,
              sequence,
              limits.max_facts,
              limits.max_witnesses,
              limits.max_wire_bytes,
              limits.max_nodes,
              limits.max_depth,
            )
        }) {
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
      guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
        @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
        return Err(Preparation(Policy))
      }
      owner.program_artifact_quote = Some((r, e))
      (r, e)
    }
  }
  match @resources.reserve_working_preparation_phase(capacity, input, r, e) {
    Err(issue) => {
      // The original module, immutable measurement and absolute quote
      // survive a declined grow. Never repeat its factory on continuation.
      owner.phase = continuation_phase
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
  ] = match domain {
    Some(RequestEffectCaptureRecovery(_, _))
    | Some(RequestSerializationGraph(_, _, _, _))
    | Some(RequestModelGraphConstruction(_, _, _, _))
    | Some(RequestModelGraph(_, _, _, _)) => Err(Preparation(WrongPhase))
    Some(RequestModelCompilation(_, _, _, graph)) =>
      @publication_host.observe_prepared_client_multi_infer_plan_encoding(
        prepared,
        [graph],
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
    Some(RequestSerializationCompilation(_, _, _, component))
    | Some(RequestKeyedSerializationCompilation(_, _, _, component)) =>
      @publication_host.observe_prepared_client_serialization_plan_encoding(
        prepared,
        component,
        manifests,
        limits.max_facts,
        limits.max_witnesses,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
        nodes_out=owner.program_artifact_plan_encoding_nodes,
      )
      .map(value => @publication_host.ClientRunCompilation::Tasks(value))
      .map_err(issue => TaskCompilation(issue))
    None =>
      if geometry.tasks {
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
  }
  match finish_request_program_artifact_work(owner) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  if attempted is Ok(artifact) {
    owner.program_compilation = Some(artifact)
    if domain is Some(RequestModelCompilation(_, _, _, _)) ||
      domain is Some(RequestSerializationCompilation(_, _, _, _)) ||
      domain is Some(RequestKeyedSerializationCompilation(_, _, _, _)) {
      // These actual callers issue their first compiled Run/Definition just
      // after receiving this artifact. Back that co-held metadata NOW, rather
      // than treating a raw TaskCompilation as constructor funding.
      match
        reserve_request_domain_run_metadata(owner, input, prepared, artifact) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
  }
  attempted
}

///|
// Same existing bounded compiled/admission/Definition packet as the timed
// ordinary constructor, once for the actual Model/Content Run. No invocation
// is issued here and no QueryTime is sampled. The original compiler/Graph,
// material and all earlier grows coexist with these native/JS representations.
fn[I] reserve_request_domain_run_metadata(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  artifact : @publication_host.ClientRunCompilation,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  guard owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(original_prepared) &&
    physical_equal(original_prepared, prepared) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_artifact_geometry is Some(geometry) &&
    owner.program_compilation is Some(original_artifact) &&
    physical_equal(original_artifact, artifact) &&
    owner.program_invocation_quote is None &&
    request_query_time_invocation_extent(geometry)
    is Some((retained, execution)) else {
    return Err(Preparation(ForeignOriginal))
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, retained, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, execution, 1L) is Some(e) else {
    return Err(Preparation(Policy))
  }
  owner.program_invocation_quote = Some((r, e))
  let result = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  )
  guard owner.phase == Selecting &&
    owner.input is Some(same_input) &&
    physical_equal(same_input, input) &&
    owner.compiled_program is Some(same_prepared) &&
    physical_equal(same_prepared, prepared) &&
    owner.program_capacity is Some(same_capacity) &&
    physical_equal(same_capacity, capacity) &&
    owner.program_compilation is Some(same_artifact) &&
    physical_equal(same_artifact, artifact) &&
    owner.program_invocation_quote == Some((r, e)) else {
    return Err(Preparation(ForeignOriginal))
  }
  result.map_err(issue => Preparation(Capacity(issue)))
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
      owner.program_invocation_quote = None
      owner.program_artifact_inputs = None
      owner.program_compilation = None
      owner.program_domain_compilation_inputs = None
      owner.program_source_free = None
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

///|
// One shared original sequence/Plan data envelope for both typed body choices.
// This prices DATA only; the caller retains the same capacity and phase guard.
fn[I, P] original_request_plan_construction_quote(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  data : @checked.ParsedCheckDataEstimate,
) -> Result[(Int64, Int64), ClientRequestPreparationIssue] {
  guard program_check_data_extent_cost(data) is Some(bytes) &&
    client_local_value_node_proof_retained_bytes() is Some(proof_retained) &&
    client_local_value_node_proof_scratch_bytes() is Some(proof_scratch) else {
    return Err(Policy)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(bytes, proof_retained, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(retained, proof_scratch, 1L)
    is Some(execution) &&
    @execution.checked_preparation_add_product(r, retained, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, execution, 1L) is Some(e) else {
    return Err(Policy)
  }
  Ok((r, e))
}
