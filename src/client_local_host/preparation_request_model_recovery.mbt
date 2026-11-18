///|
// Saved material admission uses the existing bounded readers. The outer
// material, nested Program/Environment, typed contracts and compiler output
// coexist; source text and retained wire are distinct from active parse work.
// These are existing managed execution units, not an RSS/GC guarantee.
pub fn request_model_recovery_capacity(
  units : Int64,
  containers : Int,
) -> @execution.ExecutionCapacity? {
  if units < 0L || units > 2147483647L || containers < 0 {
    return None
  }
  @execution.execution_capacity_inventory(
    [
      { unit: ValueNodeSlots, count: units, copies: 6, },
      { unit: DecodedTextBytes, count: units, copies: 6, },
      { unit: CanonicalWireBytes, count: units, copies: 4, },
      { unit: ValueNodeSlots, count: containers.to_int64(), copies: 8, },
    ],
    [
      { unit: ValueNodeSlots, count: units, copies: 2, },
      { unit: CanonicalWireBytes, count: units, copies: 4, },
      { unit: CursorRootSlots, count: Int64::min(units, 100L), copies: 2, },
    ],
    RetainedAlongsideExecution,
  )
}

///|
/// Reserve each saved-material/dependency/binding constructor on the SAME
/// physical restoration Request. The Journal's original Request/Definition
/// pair stays nominal; no checked owner, compiler or Model permission is
/// issued. Completed constructor retention accumulates while scratch is a
/// sequential peak. Failure leaves all prior capacity and cleanup intact.
pub fn[I] reserve_request_model_recovery_materials(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  count : Int,
  wire_at : (Int) -> String,
  containers : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard (owner.phase == Open || owner.phase == ModelRecovery) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None &&
    @publication.publication_contract_name(definition) == "run_definition" &&
    count >= 0 &&
    containers >= 0 else {
    return Err(ForeignOriginal)
  }
  match owner.program_domain_compilation_inputs {
    None => {
      if owner.phase != Open ||
        owner.snapshot_base is Some(_) ||
        owner.submitted_intent is Some(_) ||
        owner.program_check is Some(_) ||
        owner.program_json is Some(_) {
        return Err(WrongPhase)
      }
      owner.program_domain_compilation_inputs = Some(
        RequestModelRecovery(request, definition),
      )
    }
    Some(RequestModelRecovery(old_request, old_definition)) =>
      if !physical_equal(old_request, request) ||
        !physical_equal(old_definition, definition) {
        return Err(ForeignOriginal)
      }
    _ => return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      // Current/capacity admission precedes the original wire callback. The
      // callback only reads immutable already-owned Strings, once each.
      let (old_r, old_e) = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      match
        @resources.check_working_preparation_capacity_current(
          owner.capacity,
          input,
        ) {
        Err(issue) => return Err(Capacity(issue))
        Ok(_) => ()
      }
      let mut units = 0L
      for index in 0..<count {
        let wire = wire_at(index)
        guard @execution.checked_preparation_add_product(
            units,
            wire.length().to_int64(),
            3L,
          )
          is Some(next) else {
          return Err(Policy)
        }
        units = next
      }
      guard request_model_recovery_capacity(units, containers) is Some(required) &&
        @execution.checked_preparation_add_product(
          old_r,
          @execution.execution_capacity_retained_bytes(required),
          1L,
        )
        is Some(r) &&
        @execution.checked_preparation_add_product(
          old_r,
          @execution.execution_capacity_execution_bytes(required),
          1L,
        )
        is Some(e) else {
        return Err(Policy)
      }
      let result = @resources.reserve_working_preparation_phase(
        owner.capacity,
        input,
        r,
        Int64::max(old_e, e),
      )
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.program_domain_compilation_inputs
        is Some(RequestModelRecovery(old_request, old_definition)) &&
        physical_equal(old_request, request) &&
        physical_equal(old_definition, definition) else {
        return Err(ForeignOriginal)
      }
      owner.phase = ModelRecovery
      result.map_err(issue => Capacity(issue))
    },
    () => if owner.phase == Selecting { owner.phase = ModelRecovery },
  )
}

///|
/// Borrow the SAME physical recovery Request ledger. Identity and currentness
/// do not issue a Source read, Model permission or an independent Run.
pub fn[I] request_model_recovery_ledger(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> Result[@resources.Ledger, ClientRequestPreparationIssue] {
  guard owner.phase == ModelRecovery &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelRecovery(old_request, old_definition)) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition) else {
    return Err(ForeignOriginal)
  }
  match
    @resources.check_working_preparation_capacity_current(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard owner.phase == ModelRecovery &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelRecovery(old_request, old_definition)) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition) else {
    return Err(ForeignOriginal)
  }
  Ok(owner.ledger)
}

///|
/// Bind the journal-restored compiler's complete Model set to the original
/// recovery Request census. No module, compiler, ledger or Run is recreated.
/// The caller retains the complete returned Scope array before any callback.
pub fn[I] prepare_request_model_recovery_read_scopes(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  graphs : Array[@publication_host.ClientInferPlanGraph],
  model_limits : @resources.LedgerLimits,
  read_retained_bytes : Array[Int64],
  read_execution_bytes : Array[Int64],
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  quantity_limits? : @resources.QuantityAmounts? = None,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  ClientInstalledManagedRunIssue,
] {
  let count = graphs.length()
  let program = @publication_host.prepared_client_identity(prepared)
  guard owner.phase == ModelRecovery &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelRecovery(old_request, old_definition)) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None &&
    @publication_host.client_compiled_run_matches(compiled, prepared) &&
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Ok(_) &&
    program.program_definition_cid ==
    @publication_host.client_request_program_cid(request) &&
    program.parameter_values_cid ==
    @publication_host.client_request_parameters_cid(request) &&
    @publication_host.client_compiled_run_infer_originals_match(
      compiled, graphs,
    ) &&
    read_retained_bytes.length() == count &&
    read_execution_bytes.length() == count &&
    read_retained_bytes.all(value => value > 0L) &&
    read_execution_bytes.all(value => value > 0L) else {
    return Err(ForeignOriginal)
  }
  let available = match preparation_initial_limits(owner.initial, input) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  if !installed_effect_limits_fit(model_limits, available) {
    return Err(InsufficientCapacity)
  }
  let identity = match
    @resources.preparation_capacity_inventory_original(owner.capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  if !@resources.original_ledger_preparation_available(identity) {
    return Err(ForeignOriginal)
  }
  if owner.program_domain_quote is None {
    let (r, e) = match
      request_model_scope_construction_quote(
        owner.capacity,
        input,
        max_reservations,
        max_holdings,
        max_delegations,
        model_count=count,
      ) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    let array_bytes = if count == 1 {
      match
        @execution.preparation_array_representation(1L, 1L, true).bind(units => {
          @execution.preparation_representation_cost(units)
        }) {
        None => return Err(InsufficientCapacity)
        Some(value) => value
      }
    } else {
      0L
    }
    guard @execution.checked_preparation_add_product(r, array_bytes, 1L)
      is Some(r) &&
      @execution.checked_preparation_add_product(e, array_bytes, 1L) is Some(e) else {
      return Err(InsufficientCapacity)
    }
    owner.program_domain_quote = Some((r, e))
  }
  let (r, e) = owner.program_domain_quote.unwrap()
  owner.phase = Selecting
  let result : Result[
    Array[@publication_host.ClientModelReadScope],
    ClientInstalledManagedRunIssue,
  ] = preparation_module_call(
    () => {
      if quantity_limits is Some(installed) {
        let selected = match
          request_model_group_quantity_limits(
            graphs[0],
            None,
            installed,
            graphs=Some(graphs),
          ) {
          None => return Err(InsufficientCapacity)
          Some(value) => value
        }
        if !@resources.quantity_configuration_matches(
            owner.ledger,
            Some(selected),
          ) {
          match @resources.configure_quantities(owner.ledger, selected) {
            Err(issue) => return Err(Ledger(issue))
            Ok(_) => ()
          }
        }
      }
      match
        @resources.grow_preparation_capacity_inventory(
          owner.capacity,
          input,
          r,
          e,
          Int::max(request_preparation_borrow_limit, max_reservations),
          max_holdings,
          max_delegations,
        ) {
        Err(issue) => return Err(Preparation(issue))
        Ok(_) => ()
      }
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.program_domain_compilation_inputs
        is Some(RequestModelRecovery(old_request, old_definition)) &&
        physical_equal(old_request, request) &&
        physical_equal(old_definition, definition) &&
        @publication_host.client_compiled_run_infer_originals_match(
          compiled, graphs,
        ) &&
        read_retained_bytes.length() == count &&
        read_execution_bytes.length() == count &&
        read_retained_bytes.all(value => value > 0L) &&
        read_execution_bytes.all(value => value > 0L) else {
        return Err(ForeignOriginal)
      }
      if count == 1 {
        @publication_host.bind_client_model_read_scope(
          compiled,
          definition,
          graphs[0],
          owner.ledger,
          identity,
        )
        .map(scope => [scope])
        .map_err(issue => ModelRead(issue))
      } else {
        @publication_host.bind_client_model_read_scopes(
          compiled,
          definition,
          graphs,
          owner.ledger,
          identity,
          read_retained_bytes,
          read_execution_bytes,
        ).map_err(issue => ModelRead(issue))
      }
    },
    () => if owner.phase == Selecting { owner.phase = ModelRecovery },
  )
  if owner.phase == Selecting {
    owner.phase = ModelRecovery
  }
  if result is Ok(_) {
    owner.program_domain_quote = None
  }
  result
}

///|
/// The stopped Local host must use this recovery Request's original ledger.
/// Parent material retention remains charged; foreign live children do not.
pub fn[I] request_model_recovery_usage_isolated(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  captured : @strategy.CapturedDAG,
) -> Bool {
  match request_model_recovery_ledger(owner, input, request, definition) {
    Err(_) => false
    Ok(ledger) =>
      physical_equal(ledger, @strategy.captured_dag_ledger(captured)) &&
      @resources.preparation_capacity_working_usage_isolated(
        owner.capacity,
        input,
        ledger,
      )
  }
}

///|
/// Project the existing checked direct-source inventory for the retained
/// Program. The caller funds this metadata constructor before entry.
pub fn[I] request_model_recovery_direct_occurrences(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientDirectAcquisitionOccurrences,
  ClientInstalledManagedRunIssue,
] {
  let program = @publication_host.prepared_client_identity(prepared)
  guard program.program_definition_cid ==
    @publication_host.client_request_program_cid(request) &&
    program.parameter_values_cid ==
    @publication_host.client_request_parameters_cid(request) else {
    return Err(ForeignOriginal)
  }
  match request_model_recovery_ledger(owner, input, request, definition) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  installed_direct_occurrences_owned(Pure(prepared))
}

///|
/// Original Effect compiler construction DATA after its checker/Model graph
/// preparation and before artifact emission. This borrows the same geometry;
/// it never issues a Request, compiler, ledger, currentness or physical grant.
/// Native backing must project the wire/container facts separately, rather
/// than treating logical R/E bytes as raw allocation bytes.
pub fn request_model_recovery_effect_compiler_capacity(
  value : @publication_host.ClientEffectCompilationConstruction,
) -> @execution.ExecutionCapacity? {
  guard program_artifact_construction_extents(
      @publication_host.client_effect_compilation_construction_geometry(value),
    )
    is Some((retained, scratch)) else {
    return None
  }
  @execution.execution_capacity_inventory(
    [{ unit: QuotedBytes, count: retained, copies: 1, }],
    [{ unit: QuotedBytes, count: scratch, copies: 1, }],
    RetainedAlongsideExecution,
  )
}

///|
/// Geometry of an already admitted original material, not of compiled IR.
/// The caller retains the exact wire/index pair and supplies the SAME funded
/// decode.observe_subtree_construction_geometry result and admission depth.
/// Its work field remains with the existing caller's observation/work owner.
/// Unmeasured Program/SQL/AQL lowering still uses the existing conservative
/// recovery recipe; a JSON Text node never stands for a compiled syntax tree.
pub fn request_model_recovery_material_capacity(
  wire : String,
  geometry : @decode.SubtreeConstructionGeometry,
  depth : Int,
  containers : Int,
) -> @execution.ExecutionCapacity? {
  if depth < 0 ||
    geometry.nodes < 1 ||
    geometry.arrays < 0 ||
    geometry.objects < 0 ||
    geometry.fields < 0 ||
    geometry.texts < 0 ||
    geometry.total_utf16 < 0L ||
    geometry.arrays > geometry.nodes ||
    geometry.objects > geometry.nodes - geometry.arrays ||
    geometry.fields >= geometry.nodes ||
    geometry.texts > geometry.nodes ||
    containers < 0 {
    return None
  }
  // Keep the old simultaneous roles/multiplicities, substituting actual
  // admitted nodes only for Value slots, actual text only for decoded text.
  @execution.execution_capacity_inventory(
    [
      { unit: ValueNodeSlots, count: geometry.nodes.to_int64(), copies: 6, },
      { unit: DecodedTextBytes, count: geometry.total_utf16 * 3L, copies: 6, },
      {
        unit: CanonicalWireBytes,
        count: wire.length().to_int64() * 3L,
        copies: 4,
      },
      { unit: ValueNodeSlots, count: containers.to_int64(), copies: 8, },
    ],
    [
      { unit: ValueNodeSlots, count: geometry.nodes.to_int64(), copies: 2, },
      {
        unit: CanonicalWireBytes,
        count: wire.length().to_int64() * 3L,
        copies: 4,
      },
      { unit: CursorRootSlots, count: depth.to_int64(), copies: 2, },
    ],
    RetainedAlongsideExecution,
  )
}

///|
/// The structured Program decoder's existing original inventory, before its
/// typed constructor. SQL/AQL text without that inventory remains unmeasured;
/// no JSON envelope count is substituted for syntax/lowering nodes here.
/// Index ownership, observation work and later compiler roles remain separate.
pub fn request_model_recovery_program_capacity(
  inventory : @syntax.ProgramConstructorInventory,
  source_depth : Int,
) -> @execution.ExecutionCapacity? {
  guard program_structure_generic_inventories(inventory, source_depth)
    is Some(value) &&
    @execution.compose_preparation_representation([
      value.containers_peak,
      value.carriers_peak,
      value.failure_peak,
    ])
    is Some(peak) &&
    @execution.preparation_representation_cost(value.retained) is Some(retained) &&
    @execution.preparation_representation_cost(peak) is Some(execution) else {
    return None
  }
  // These same three roles coexist in the original structured decoder. Keep
  // their sum, exactly as program_structure_construction_quote does; only
  // its separately owned Source index/base/controller are excluded here.
  @execution.execution_capacity(retained, Int64::max(retained, execution))
}

///|
/// Construct authoring evidence from the exact source admitted by this material
/// Read. The saved full Run and original compiler owner must already match.
/// All collection/path/writer overlap is admitted on the SAME recovery Request,
/// and partial state remains in its existing authoring slot through failure.
pub fn[I] prepare_request_model_recovery_authoring_context(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  compiler : @publication_host.ClientProgramPreparationLimits,
) -> Result[
  @publication_host.ClientAuthoringContextPreparation,
  ClientRequestAuthoringIssue,
] {
  guard owner.phase == ModelRecovery &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelRecovery(old_request, old_definition)) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition) &&
    @publication_host.client_compiled_run_matches(compiled, prepared) &&
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Ok(_) &&
    @publication_host.client_request_program_cid(request) ==
    @publication_host.prepared_client_identity(prepared).program_definition_cid &&
    @publication_host.client_request_parameters_cid(request) ==
    @publication_host.prepared_client_identity(prepared).parameter_values_cid else {
    return Err(Preparation(ForeignOriginal))
  }
  prepare_request_authoring_in_capacity(
    owner,
    input,
    prepared,
    compiler,
    owner.capacity,
  )
}

///|
/// Admit the saved journal before the material compiler enters. The original
/// Request already owns raw/parsed material. Audit, measured saved evidence and
/// failed-child overlap use its existing normalization continuation and laws.
pub fn[I] prepare_request_model_recovery_normalization(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
  wire : String,
  compiler : @publication_host.ClientProgramPreparationLimits,
) -> Result[
  @publication_host.ClientLocalNormalization,
  ClientRequestNormalizationIssue,
] {
  guard owner.phase == ModelRecovery &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelRecovery(old_request, old_definition)) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition) &&
    @publication_host.client_request_program_cid(request) ==
    @publication_host.prepared_client_identity(prepared).program_definition_cid &&
    @publication_host.client_request_parameters_cid(request) ==
    @publication_host.prepared_client_identity(prepared).parameter_values_cid else {
    return Err(Preparation(ForeignOriginal))
  }
  prepare_request_model_recovery_normalization_owned(
    owner, input, prepared, wire, compiler,
  )
}

///|
// Only the fixed public entry above or the same material Read below enters.
// Keeping Selecting across the whole inverse fences every Resource callback.
fn[I] prepare_request_model_recovery_normalization_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  wire : String,
  compiler : @publication_host.ClientProgramPreparationLimits,
) -> Result[
  @publication_host.ClientLocalNormalization,
  ClientRequestNormalizationIssue,
] {
  let phase = owner.phase
  owner.phase = Selecting
  defer {
    owner.phase = phase
  }
  let capacity = owner.capacity
  if owner.program_normalization is None {
    let base = match
      @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Preparation(Capacity(issue)))
      Ok(value) => value
    }
    guard request_original_normalization_audit_extent_cost(prepared)
      is Some(bytes) &&
      @execution.checked_preparation_add_product(base.0, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(base.1, bytes, 1L) is Some(e) else {
      return Err(Preparation(Policy))
    }
    let codec = compiler.checking.compilation.artifacts
    owner.program_normalization = Some({
      original: prepared,
      compiler,
      limits: {
        max_work: compiler.checking.compilation.work,
        max_wire_bytes: codec.bytes,
        max_nodes: codec.nodes,
        max_depth: codec.depth,
      },
      baseline: base,
      audit_quote: (r, e),
      audit: None,
      retained: None,
      construction: None,
      publication_quote: None,
      work: None,
      returned: false,
      charged_work: 0L,
      spent_work: 0L,
      result: None,
    })
  }
  let state = owner.program_normalization.unwrap()
  if !physical_equal(state.original, prepared) ||
    !physical_equal(state.compiler, compiler) {
    return Err(Preparation(ForeignOriginal))
  }
  if state.result is Some(result) {
    match result {
      Err(_) => return result
      Ok(_) => {
        match
          @resources.check_working_preparation_capacity_current(capacity, input) {
          Err(issue) => return Err(Preparation(Capacity(issue)))
          Ok(_) => ()
        }
        // Exact saved bytes still matter on a cached constructor retry.
        return @publication_host.admit_measured_prepared_client_local_normalization(
          state.audit.unwrap(),
          wire,
          state.construction.unwrap(),
        ).map_err(issue => Normalization(issue))
      }
    }
  }
  prepare_request_program_normalization_owned(
    owner,
    input,
    state,
    capacity,
    restored_wire=Some(wire),
  )
}

///|
pub suberror ClientRequestModelRecoveryMaterialsIssue {
  Preparation(ClientRequestPreparationIssue)
  Normalization(ClientRequestNormalizationIssue)
  Authoring(ClientRequestAuthoringIssue)
  Materials(@publication_host.ClientTaskRunMaterialsIssue)
  Compilation(@publication_host.ClientCompiledRunIssue)
}

///|
/// One same-parent inverse, not a fresh preparation/Root or a second compiler.
/// The fixed callback retains typed normalization before the compiler; original
/// source annotations are constructed after the complete saved Run matches.
pub fn[I] admit_request_model_recovery_materials(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  wire : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : @publication_host.ClientCompilationManifests,
  limits : @publication_host.ClientValuesRunMaterialsLimits,
) -> Result[
  (
    @publication_host.ClientTaskRunMaterials,
    @publication_host.ClientAuthoringContextPreparation,
  ),
  ClientRequestModelRecoveryMaterialsIssue,
] {
  guard owner.phase == ModelRecovery &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelRecovery(old_request, old_definition)) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None else {
    return Err(Preparation(ForeignOriginal))
  }
  owner.phase = Selecting
  defer {
    owner.phase = ModelRecovery
  }
  match
    @resources.check_working_preparation_capacity_current(owner.capacity, input) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(_) => ()
  }
  let normalization_issue : Ref[ClientRequestNormalizationIssue?] = Ref(None)
  let material = @publication_host.admit_client_infer_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    expressions,
    operations,
    manifests,
    limits,
    restore_normalization=Some((prepared, journal) => {
      let identity = @publication_host.prepared_client_identity(prepared)
      if identity.program_definition_cid !=
        @publication_host.client_request_program_cid(request) ||
        identity.parameter_values_cid !=
        @publication_host.client_request_parameters_cid(request) {
        normalization_issue.val = Some(Preparation(ForeignOriginal))
        return false
      }
      match
        prepare_request_model_recovery_normalization_owned(
          owner,
          input,
          prepared,
          journal,
          limits.preparation,
        ) {
        Err(issue) => {
          normalization_issue.val = Some(issue)
          false
        }
        Ok(_) => true
      }
    }),
  )
  let material = match material {
    Err(issue) =>
      return match normalization_issue.val {
        Some(original) => Err(Normalization(original))
        None => Err(Materials(issue))
      }
    Ok(value) => value
  }
  let compiled = match
    @publication_host.client_task_run_materials_compiled_original(material) {
    Err(issue) => return Err(Compilation(issue))
    Ok(value) => value
  }
  if !@publication_host.client_compiled_run_matches(compiled, material.prepared) ||
    !(@publication_host.check_client_compiled_run_definition(
      compiled, definition,
    )
    is Ok(_)) {
    return Err(Preparation(ForeignOriginal))
  }
  let authoring = match
    prepare_request_authoring_in_capacity(
      owner,
      input,
      material.prepared,
      limits.preparation,
      owner.capacity,
    ) {
    Err(issue) => return Err(Authoring(issue))
    Ok(value) => value
  }
  Ok((material, authoring))
}

///|
/// Project the warm Model journal under the SAME original Request before its
/// serializer starts. Parameter DATA is borrowed from the retained checker
/// input; no caller wire, standalone capacity or current catalogue can replace it.
pub fn[I] issue_request_model_run_materials(
  owner : ClientRequestPreparation[I],
  input : I,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[String, ClientRequestProgramPlanIssue] {
  guard owner.phase == ModelPlanReserved &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_compilation is Some(original_compilation) &&
    @publication_host.client_compiled_run_matches_pure_compilation(
      compiled, prepared, original_compilation,
    ) &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  construct_request_original_materials_owned(
    owner,
    input,
    capacity,
    () => {
      owner.phase == Selecting &&
      owner.input is Some(original) &&
      physical_equal(original, input) &&
      owner.compiled_program is Some(current) &&
      physical_equal(current, prepared) &&
      owner.program_compilation is Some(current_compilation) &&
      @publication_host.client_compiled_run_matches_pure_compilation(
        compiled, current, current_compilation,
      )
    },
    fund => {
      @publication_host.issue_original_client_infer_run_materials(
        compiled,
        definition,
        owner.native_parameters,
        fund,
      ).map_err(issue => InferMaterials(issue))
    },
  )
}
