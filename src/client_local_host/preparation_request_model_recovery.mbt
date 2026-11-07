///|
// Saved material admission uses the existing bounded readers. The outer
// material, nested Program/Environment, typed contracts and compiler output
// coexist; source text and retained wire are distinct from active parse work.
// These are existing managed execution units, not an RSS/GC guarantee.
fn request_model_recovery_capacity(
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
