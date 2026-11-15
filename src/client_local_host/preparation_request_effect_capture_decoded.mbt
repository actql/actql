///|
// DATA on the existing RequestEffectCaptureRecovery resident slot. No Ledger,
// Owner, permission or transferable Read is created by this residue.
priv struct ClientRequestEffectCaptureMaterial {
  mut encrypted_bytes : Int?
  mut plaintext_bytes : Int?
  mut wire : String?
  staged_envelope : Bool
  mut envelope_wire : String?
  mut envelope_nodes : Int?
  mut observed_wire : String?
  mut nodes : Int?
  mut captured : @publication.PreparedCapturedEffectRun?
  mut work : @resources.PreparationPhaseWorkContinuation64?
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
// One closed recipe, selected only on the nominal Request's already admitted
// original encrypted/plaintext span. The same Host policy admits this body;
// neither a supplied count, Work callback nor a larger unrelated wire enters.
fn[I] request_effect_capture_phase_work_bound(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  wire : String,
) -> Int64? {
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(material) &&
    material.encrypted_bytes is Some(bytes) &&
    wire.length() <= bytes &&
    client_local_preparation_initial_limits(client_local_resource_policy())
    is Some(policy) &&
    preparation_initial_limits(owner.initial, input) is Ok(selected) &&
    selected.retained_bytes <= policy.retained_bytes &&
    selected.execution_bytes <= policy.execution_bytes else {
    return None
  }
  // Four record source/canonical passes; six body admission/hash/codec passes;
  // two inventory encoders; reference/key indexes and memoized graph traversal
  // with its existing depth64. 128 covers these named finite passes, UTF-16
  // key comparisons and their scalar/control steps. It buys no second phase.
  // Before the allocation-free lexical walk, punctuation contributes at most
  // two nodes per observed unit plus the root. The actual walk narrows memory
  // geometry only; its result is never a semantic entry/work allowance.
  guard @execution.checked_preparation_add_product(1L, bytes.to_int64(), 2L)
    is Some(nodes) &&
    @execution.checked_preparation_add_product(nodes, bytes.to_int64(), 1L)
    is Some(span) else {
    return None
  }
  @execution.checked_preparation_add_product(256L, span, 128L)
}

///|
fn[I] request_effect_capture_material(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> ClientRequestEffectCaptureMaterial? {
  guard owner.phase == EffectCaptureRecovery &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs
    is Some(
      RequestEffectCaptureRecovery(old_request, old_definition, Some(material))
    ) &&
    physical_equal(old_request, request) &&
    physical_equal(old_definition, definition) else {
    return None
  }
  Some(material)
}

///|
fn request_effect_capture_decoded_capacity(
  units : Int,
  nodes : Int,
) -> @execution.ExecutionCapacity? {
  if units < 0 || nodes < 1 {
    return None
  }
  let n = nodes.to_int64()
  // Punctuation includes embedded contract strings. It funds the decoded
  // containers AND their typed bodies/index vectors; it never selects an
  // admitted entry allowance. That allowance uses the actual parsed array.
  @execution.execution_capacity_inventory(
    [
      { unit: ValueNodeSlots, count: n, copies: 4, },
      { unit: DecodedTextBytes, count: units.to_int64(), copies: 2, },
      { unit: CursorRootSlots, count: n, copies: 4, },
    ],
    [
      { unit: ValueNodeSlots, count: n, copies: 2, },
      { unit: CanonicalWireBytes, count: units.to_int64(), copies: 2, },
    ],
    RetainedAlongsideExecution,
  )
}

///|
/// Existing bounded lexical census on the exact selected encrypted String.
/// Initial byte/String backings precede toString; this original grow precedes
/// JSON.parse, including malformed/failed envelope construction.
pub fn[I] reserve_request_effect_capture_envelope(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(material) &&
    material.staged_envelope &&
    material.encrypted_bytes is Some(bytes) &&
    wire.length() <= bytes else {
    return Err(ForeignOriginal)
  }
  if material.envelope_wire is Some(original) && original != wire {
    return Err(ForeignOriginal)
  }
  match
    @resources.check_working_preparation_capacity_current(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(still) &&
    physical_equal(still, material) else {
    return Err(ForeignOriginal)
  }
  material.envelope_wire = Some(wire)
  let work = match material.work {
    Some(work) => {
      match @resources.resume_preparation_phase_work_continuation64(work) {
        Err(issue) => return Err(Work(issue))
        Ok(_) => ()
      }
      work
    }
    None => {
      guard request_effect_capture_phase_work_bound(
          owner, input, request, definition, wire,
        )
        is Some(maximum) else {
        return Err(Policy)
      }
      let work = match
        @resources.begin_preparation_phase_work_continuation64(
          owner.capacity,
          input,
          @resources.PublicationProof,
          maximum,
        ) {
        Err(issue) => return Err(Work(issue))
        Ok(value) => value
      }
      material.work = Some(work)
      work
    }
  }
  let refused : Ref[@resources.PreparationWorkIssue?] = Ref(None)
  let geometry = installed_effect_dependency_wire_geometry(
    wire,
    bytes,
    material.max_nodes,
    material.max_depth,
    units => {
      match
        @resources.spend_preparation_phase_work_continuation64(
          work,
          units.to_int64(),
        ) {
        Ok(_) => true
        Err(issue) => {
          refused.val = Some(issue)
          false
        }
      }
    },
  )
  match @resources.return_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  guard geometry is Some(geometry) else {
    return Err(
      match refused.val {
        Some(issue) => Work(issue)
        None => Policy
      },
    )
  }
  guard request_effect_capture_recovery_capacity(
      bytes,
      @publication.publication_contract_json(definition).length(),
      material.max_wire_bytes,
      material.max_nodes,
      material.max_depth,
      staged_envelope=true,
      envelope_nodes=Some(geometry.node_upper),
    )
    is Some(required) &&
    owner.program_plan_quote is Some((base_r, base_e)) &&
    @execution.checked_preparation_add_product(
      base_r,
      @execution.execution_capacity_retained_bytes(required),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_e,
      @execution.execution_capacity_execution_bytes(required),
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  let (r, e) = match owner.program_domain_quote {
    Some((old_r, old_e)) => (Int64::max(r, old_r), Int64::max(e, old_e))
    None => (r, e)
  }
  owner.program_domain_quote = Some((r, e))
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  guard owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  owner.phase = EffectCaptureRecovery
  match result {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(still) &&
    physical_equal(still, material) else {
    return Err(ForeignOriginal)
  }
  material.envelope_wire = Some(wire)
  material.envelope_nodes = Some(geometry.node_upper)
  Ok(())
}

///|
/// After the SAME authenticated extent and before JSON.parse. Actual backing
/// remains held on success and failure until that Read's physical cleanup.
pub fn[I] reserve_request_effect_capture_decoded(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(material) &&
    material.encrypted_bytes is Some(bytes) &&
    wire.length() <= bytes &&
    (!material.staged_envelope || material.envelope_nodes is Some(_)) else {
    return Err(ForeignOriginal)
  }
  if material.wire is Some(original) && original != wire {
    return Err(ForeignOriginal)
  }
  match
    @resources.check_working_preparation_capacity_current(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(still) &&
    physical_equal(still, material) else {
    return Err(ForeignOriginal)
  }
  if material.observed_wire is Some(original) && original != wire {
    return Err(ForeignOriginal)
  }
  if material.nodes is None || material.staged_envelope {
    guard request_effect_capture_phase_work_bound(
        owner, input, request, definition, wire,
      )
      is Some(maximum) else {
      return Err(Policy)
    }
    let work = match material.work {
      Some(work) => {
        match @resources.resume_preparation_phase_work_continuation64(work) {
          Err(issue) => return Err(Work(issue))
          Ok(_) => ()
        }
        work
      }
      None => {
        let work = match
          @resources.begin_preparation_phase_work_continuation64(
            owner.capacity,
            input,
            @resources.PublicationProof,
            maximum,
          ) {
          Err(issue) => return Err(Work(issue))
          Ok(value) => value
        }
        material.work = Some(work)
        work
      }
    }
    let charged = @resources.spend_preparation_phase_work_continuation64(
      work,
      wire.length().to_int64() *
      (if material.staged_envelope { 3L } else { 1L }),
    )
    let nodes = match charged {
      Err(_) => None
      Ok(_) =>
        match material.nodes {
          Some(nodes) => Some(nodes)
          None => effect_capture_wire_nodes(wire)
        }
    }
    let plaintext_bytes = if material.plaintext_bytes is Some(_) {
      material.plaintext_bytes
    } else if material.staged_envelope && charged is Ok(_) {
      @scalar.admit_utf8_length(wire, bytes).to_option()
    } else {
      None
    }
    let returned = @resources.return_preparation_phase_work_continuation64(work)
    match charged {
      Err(issue) => return Err(Work(issue))
      Ok(_) => ()
    }
    match returned {
      Err(issue) => return Err(Work(issue))
      Ok(_) => ()
    }
    guard nodes is Some(nodes) &&
      (!material.staged_envelope || plaintext_bytes is Some(_)) else {
      return Err(Policy)
    }
    material.plaintext_bytes = plaintext_bytes
    material.observed_wire = Some(wire)
    material.nodes = Some(nodes)
  }
  guard material.nodes is Some(nodes) &&
    request_effect_capture_decoded_capacity(wire.length(), nodes)
    is Some(decoded) &&
    request_effect_capture_recovery_capacity(
      bytes,
      @publication.publication_contract_json(definition).length(),
      material.max_wire_bytes,
      material.max_nodes,
      material.max_depth,
      staged_envelope=material.staged_envelope,
      envelope_nodes=material.envelope_nodes,
      plaintext_bytes=material.plaintext_bytes,
      envelope_units=material.envelope_wire.map(String::length).unwrap_or(0),
    )
    is Some(read) &&
    standard_create_sum_capacities([read, decoded], sequential_workspace=false)
    is Some(required) &&
    owner.program_plan_quote is Some((base_r, base_e)) &&
    @execution.checked_preparation_add_product(
      base_r,
      @execution.execution_capacity_retained_bytes(required),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_e,
      @execution.execution_capacity_execution_bytes(required),
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  let (r, e) = match owner.program_domain_quote {
    Some((old_r, old_e)) => (Int64::max(r, old_r), Int64::max(e, old_e))
    None => (r, e)
  }
  owner.program_domain_quote = Some((r, e))
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  guard owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  owner.phase = EffectCaptureRecovery
  match result {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(still) &&
    physical_equal(still, material) else {
    return Err(ForeignOriginal)
  }
  material.wire = Some(wire)
  Ok(())
}

///|
/// The saved record selects the exact contract; caller text is only compared
/// with that original. All JSON/body/index construction is already backed.
pub fn[I] admit_request_effect_captured_run(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  captured_wire : String,
) -> Result[
  @publication.PreparedCapturedEffectRun,
  ClientRequestPreparationIssue,
] {
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(material) &&
    material.wire is Some(wire) &&
    material.encrypted_bytes is Some(encrypted_bytes) else {
    return Err(ForeignOriginal)
  }
  let bytes = material.plaintext_bytes.unwrap_or(encrypted_bytes)
  match
    @resources.check_working_preparation_capacity_current(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard request_effect_capture_material(owner, input, request, definition)
    is Some(still) &&
    physical_equal(still, material) else {
    return Err(ForeignOriginal)
  }
  if material.captured is Some(original) {
    return if @publication.publication_contract_json(
        @publication.prepared_captured_effect_run_contract(original),
      ) ==
      captured_wire {
      Ok(original)
    } else {
      Err(ForeignOriginal)
    }
  }
  guard material.nodes is Some(nodes) else { return Err(Policy) }
  let work = match material.work {
    Some(work) => {
      match @resources.resume_preparation_phase_work_continuation64(work) {
        Err(issue) => return Err(Work(issue))
        Ok(_) => ()
      }
      work
    }
    None => return Err(WrongPhase)
  }
  owner.phase = Selecting
  defer {
    let _ = @resources.return_preparation_phase_work_continuation64(work)
    if owner.phase == Selecting {
      owner.phase = EffectCaptureRecovery
    }
  }
  let refused : Ref[@resources.PreparationWorkIssue?] = Ref(None)
  let spend = fn(units : Int) -> Bool {
    match
      @resources.spend_preparation_phase_work_continuation64(
        work,
        units.to_int64(),
      ) {
      Ok(_) => true
      Err(issue) => {
        refused.val = Some(issue)
        false
      }
    }
  }
  for _ in 0..<4 {
    if !spend(wire.length()) {
      return Err(Work(refused.val.unwrap()))
    }
  }
  let node = match
    @source.parse_json(wire, {
      max_input_bytes: bytes,
      max_nodes: nodes,
      max_depth: material.max_depth,
    }) {
    Err(_) => return Err(Policy)
    Ok(value) => value
  }
  let record = @identity.from_source(
    node,
    nodes,
    material.max_depth,
    bytes,
    data_keys=true,
  ) catch {
    _ => return Err(Policy)
  }
  guard @identity.object_field(record, "run_definition")
    is Some(@identity.String(run_wire)) &&
    run_wire == @publication.publication_contract_json(definition) &&
    @identity.object_field(record, "captured_run")
    is Some(@identity.String(original_wire)) &&
    original_wire == captured_wire else {
    return Err(ForeignOriginal)
  }
  // The actual authenticated capture extent selects aggregate parser limits;
  // each dependency body keeps its original family codec/depth policy.
  let captured = match
    @publication.admit_publication_contract(
      "captured_run",
      original_wire,
      bytes,
      nodes,
      material.max_depth,
    ) {
    Err(_) => return Err(Policy)
    Ok(value) => value
  }
  let prepared = match
    @publication.prepare_recovered_captured_effect_run(
      captured,
      bytes,
      nodes,
      material.max_depth,
      spend,
    ) {
    Err(_) =>
      return Err(
        match refused.val {
          Some(issue) => Work(issue)
          None => Policy
        },
      )
    Ok(value) => value
  }
  material.captured = Some(prepared)
  Ok(prepared)
}

///|
fn[I] finish_request_effect_capture_work(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.program_domain_compilation_inputs
    is Some(RequestEffectCaptureRecovery(_, _, Some(material))) &&
    material.work is Some(work) {
    match @resources.finish_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => material.work = None
    }
  }
  Ok(())
}
