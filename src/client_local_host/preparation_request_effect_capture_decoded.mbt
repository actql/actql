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
  mut decoded_nodes : Int?
  mut decoded_key_units : Int?
  mut decoded_key_total : Int?
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
  // The aggregate includes punctuation in decoded embedded contract Strings.
  // It funds the decoded
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
// Only memory geometry is refined. Each decoded String may later be admitted
// as a separate contract, including Strings outside captured_run. Keep their
// complete punctuation bounds without counting the outer JSON escape layer
// as another forest. No inner String is parsed or given a semantic allowance.
fn request_effect_capture_decoded_string_nodes(
  value : @identity.CanonicalValue,
  work : @resources.PreparationPhaseWorkContinuation64,
) -> Result[(Int, Int, Int), ClientRequestPreparationIssue] {
  match @resources.spend_preparation_phase_work_continuation64(work, 1L) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  match value {
    @identity.String(text) => {
      match
        @resources.spend_preparation_phase_work_continuation64(
          work,
          text.length().to_int64(),
        ) {
        Err(issue) => return Err(Work(issue))
        Ok(_) => ()
      }
      match effect_capture_wire_nodes(text) {
        Some(nodes) => Ok((nodes, 0, 0))
        None => Err(Policy)
      }
    }
    @identity.Array(items) => {
      let mut nodes = 0L
      let mut key_units = 0
      let mut key_total = 0L
      for index in 0..<@identity.array_count(items) {
        guard @identity.array_at(items, index) is Some(item) else {
          return Err(Policy)
        }
        let (amount, longest, total) = match
          request_effect_capture_decoded_string_nodes(item, work) {
          Err(issue) => return Err(issue)
          Ok(value) => value
        }
        nodes += amount.to_int64()
        key_units = Int::max(key_units, longest)
        key_total += total.to_int64()
        if nodes > 2147483647L || key_total > 2147483647L {
          return Err(Policy)
        }
      }
      Ok((nodes.to_int(), key_units, key_total.to_int()))
    }
    @identity.Object(fields) => {
      let mut nodes = 0L
      let mut key_units = 0
      let mut key_total = 0L
      for index in 0..<@identity.array_count(fields) {
        guard @identity.array_at(fields, index) is Some((key, item)) else {
          return Err(Policy)
        }
        // Keys are normally fixed metadata names. Include even their decoded
        // punctuation so an unrecognized key cannot underprice a failed prefix.
        match
          @resources.spend_preparation_phase_work_continuation64(
            work,
            key.length().to_int64(),
          ) {
          Err(issue) => return Err(Work(issue))
          Ok(_) => ()
        }
        guard effect_capture_wire_nodes(key) is Some(key_nodes) else {
          return Err(Policy)
        }
        let (amount, longest, total) = match
          request_effect_capture_decoded_string_nodes(item, work) {
          Err(issue) => return Err(issue)
          Ok(value) => value
        }
        nodes += key_nodes.to_int64() + amount.to_int64()
        key_units = Int::max(key_units, Int::max(key.length(), longest))
        key_total += key.length().to_int64() + total.to_int64()
        if nodes > 2147483647L || key_total > 2147483647L {
          return Err(Policy)
        }
      }
      Ok((nodes.to_int(), key_units, key_total.to_int()))
    }
    _ => Ok((0, 0, 0))
  }
}

///|
// The real admission still normalizes keys. Its one sequential NFC/LF
// workspace is bounded by the longest DECODED key, while all returned key
// text remains live. Values never select this key-only constructor budget.
fn request_effect_capture_decoded_key_capacity(
  nodes : Int,
  key_units : Int,
  key_total : Int,
) -> @execution.ExecutionCapacity? {
  guard nodes > 0 &&
    key_units >= 0 &&
    key_total >= key_units &&
    @canonical.nfc_lf_construction_scratch_extent(key_units) is Some(scratch) &&
    @canonical.nfc_lf_retained_output_units(key_total.to_int64())
    is Some(output) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: nodes.to_int64(),
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: output,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: scratch.record_headers,
      reference_slots: scratch.reference_slots,
      scalar_words: scratch.scalar_words,
      owned_utf16_units: scratch.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// Both stages resize this SAME original Read. Selecting fences the current
// callback; a refused grow retains its old backing and attempted quote.
fn[I] grow_request_effect_capture_decoded_capacity(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  material : ClientRequestEffectCaptureMaterial,
  required : @execution.ExecutionCapacity,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs
    is Some(
      RequestEffectCaptureRecovery(same_request, same_definition, Some(same))
    ) &&
    physical_equal(same_request, request) &&
    physical_equal(same_definition, definition) &&
    physical_equal(same, material) &&
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
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  guard owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs
    is Some(
      RequestEffectCaptureRecovery(same_request, same_definition, Some(same))
    ) &&
    physical_equal(same_request, request) &&
    physical_equal(same_definition, definition) &&
    physical_equal(same, material) else {
    return Err(ForeignOriginal)
  }
  result.map_err(issue => Capacity(issue))
}

///|
fn[I] refine_request_effect_capture_decoded_nodes(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  material : ClientRequestEffectCaptureMaterial,
  wire : String,
  read : @execution.ExecutionCapacity,
) -> Result[(Int, Int, Int), ClientRequestPreparationIssue] {
  guard material.work is Some(work) &&
    material.encrypted_bytes is Some(bytes) &&
    material.nodes is Some(coarse_nodes) else {
    return Err(WrongPhase)
  }
  match @resources.resume_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  let mut active = true
  defer (if active {
    ignore(@resources.return_preparation_phase_work_continuation64(work))
  })
  // The existing Read's lexical/depth controls fund this allocation-free
  // preflight and its Work sink. Keep the coarse original semantic bound.
  let refused : Ref[@resources.PreparationWorkIssue?] = Ref(None)
  let geometry = installed_effect_dependency_wire_geometry(
    wire,
    bytes,
    coarse_nodes,
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
  guard geometry is Some(geometry) else {
    return Err(
      match refused.val {
        Some(issue) => Work(issue)
        None => Policy
      },
    )
  }
  // Working capacity cannot resize while Work executes. Return, then resume
  // this SAME spent continuation after the original grow; never refill it.
  let returned = @resources.return_preparation_phase_work_continuation64(work)
  active = false
  match returned {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  // Fund the SAME data-key parser and data-key Canonical conversion
  // before either forest exists. No body emission or hash writer runs in
  // this census. Both existing constructor inventories include their failed
  // prefixes, duplicate maps, sort and active recursive contexts.
  guard @source.json_shaped_construction_extent(
      geometry.input_bytes,
      geometry.node_upper,
      material.max_depth,
      // A pending key already belongs to the parser Map before its colon.
      // The preflight node prefix includes it; completed fields alone do not.
      geometry.node_upper,
      geometry.objects + geometry.arrays,
      geometry.objects,
      geometry.node_upper,
      Int::min(geometry.quoted_tokens, geometry.node_upper),
      normalize_keys=false,
    )
    is Some(source_layout) &&
    compilation_canonical_layout({
      nodes: geometry.node_upper,
      arrays: geometry.arrays,
      objects: geometry.objects,
      fields: geometry.fields,
      depth: geometry.depth_upper,
      largest_object: geometry.fields,
    })
    is Some(canonical) &&
    @execution.compose_preparation_representation([
      {
        record_headers: source_layout.record_headers,
        reference_slots: source_layout.reference_slots,
        scalar_words: source_layout.scalar_words,
        owned_utf16_units: source_layout.owned_utf16_units,
        owned_wire_bytes: geometry.input_bytes.to_int64(),
      },
      canonical.tree,
      canonical.temporary,
    ])
    is Some(workspace) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      workspace,
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(construction) &&
    request_effect_capture_decoded_capacity(wire.length(), geometry.node_upper)
    is Some(outer) &&
    standard_create_sum_capacities([read, outer, construction])
    is Some(required) else {
    return Err(Policy)
  }
  match
    grow_request_effect_capture_decoded_capacity(
      owner, input, request, definition, material, required,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @resources.resume_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => active = true
  }
  match
    @resources.spend_preparation_phase_work_continuation64(
      work,
      wire.length().to_int64() * 4L,
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  let parser = match
    @source.start_json_parse(
      wire,
      {
        max_input_bytes: bytes,
        max_nodes: geometry.node_upper,
        max_depth: material.max_depth,
      },
      data_keys=true,
    ) {
    Err(_) => return Err(Policy)
    Ok(value) => value
  }
  defer @source.cancel_json_parse(parser)
  let source = while true {
    match @source.advance_json_parse(parser, 4096) {
      Ok(@source.JsonParseContinue(..)) => ()
      Ok(@source.JsonParseComplete(parsed, ..)) => break parsed.node
      _ => return Err(Policy)
    }
  } nobreak {
    return Err(Policy)
  }
  let record = @identity.from_source(
    source,
    geometry.node_upper,
    material.max_depth,
    bytes,
    data_keys=true,
  ) catch {
    _ => return Err(Policy)
  }
  let (inner, key_units, key_total) = match
    request_effect_capture_decoded_string_nodes(record, work) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let nodes = geometry.node_upper.to_int64() + inner.to_int64()
  if nodes > 2147483647L {
    return Err(Policy)
  }
  let returned = @resources.return_preparation_phase_work_continuation64(work)
  active = false
  match returned {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  Ok((nodes.to_int(), key_units, key_total))
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
      (if material.staged_envelope && material.nodes is None { 3L } else { 1L }),
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
  guard material.nodes is Some(_) &&
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
    is Some(read) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  defer (if owner.phase == Selecting { owner.phase = EffectCaptureRecovery })
  let (nodes, key_units, key_total) = match
    (
      material.decoded_nodes,
      material.decoded_key_units,
      material.decoded_key_total,
    ) {
    (Some(nodes), Some(key_units), Some(key_total)) =>
      (nodes, key_units, key_total)
    _ => {
      let (nodes, key_units, key_total) = match
        refine_request_effect_capture_decoded_nodes(
          owner, input, request, definition, material, wire, read,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      // Immutable same-wire memory DATA only. Currentness, admission and Work
      // still run on their original owners; this value buys no extra phase.
      material.decoded_nodes = Some(nodes)
      material.decoded_key_units = Some(key_units)
      material.decoded_key_total = Some(key_total)
      (nodes, key_units, key_total)
    }
  }
  guard request_effect_capture_decoded_capacity(wire.length(), nodes)
    is Some(decoded) &&
    request_effect_capture_decoded_key_capacity(nodes, key_units, key_total)
    is Some(keys) &&
    standard_create_sum_capacities([read, decoded, keys]) is Some(required) else {
    return Err(Policy)
  }
  match
    grow_request_effect_capture_decoded_capacity(
      owner, input, request, definition, material, required,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
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
