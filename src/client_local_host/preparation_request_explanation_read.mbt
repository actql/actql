///|
// This purpose uses the SAME read Request capacity, independently of its
// producing Run. No Result metadata slot, Root field or second Ledger exists.
// Entry/owned operation memo and callback frames, bounded SQL scalar-probe
// results, and one complete codec quotation coexist. Variable original wires,
// parsed values and the outgoing view are admitted separately below.
let request_explanation_read_entry_bytes : Int64 = client_static_plan_quote_construction_bytes() +
  @execution.preparation_representation_cost({
    // Plus the owned bounded request snapshot: one header, four borrowed
    // references (principal/connection/ref/signal) and three limit words.
    // The new private consumption boundary also holds its promise/executor,
    // completion/error/close/end closures and native listener wrappers. Count
    // their captured slots and settlement words before installing listeners.
    record_headers: 49L,
    reference_slots: 148L,
    scalar_words: 83L,
    // Four transient/retained SQL source copies can coexist across the two
    // reads. These fixed authored statements are each below 4096 UTF-16 units;
    // selected native statement/VM custody remains with the original Journal.
    owned_utf16_units: 4L * 4096L,
    owned_wire_bytes: 0L,
  }).unwrap()

///|
/// Admit the metadata gate/extent-probe controls BEFORE Account callbacks or
/// Journal access. This creates no authority and authorizes no stored bytes.
pub fn[I] begin_request_explanation_read(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open &&
    owner.result_read is None &&
    !result_read_metadata_active(owner) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let old = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(
      old.0,
      request_explanation_read_entry_bytes,
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      old.1,
      request_explanation_read_entry_bytes,
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  owner.phase = match result {
    Ok(_) => ExplanationRead
    Err(_) => Open
  }
  result.map_err(issue => Capacity(issue))
}

///|
// Cold records require the complete arbitrary-wire validator, not the fresh
// compiler's restricted item profile. Missing schema coverage is a refusal.
fn explanation_read_codec_cost(
  name : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Int64? {
  let codec = match explanation_read_codec_layout(name, bytes, nodes, depth) {
    Some(value) => value
    None => return None
  }
  guard @execution.preparation_representation_cost(codec.retained) is Some(r) &&
    @execution.preparation_representation_cost(codec.scratch) is Some(e) else {
    return None
  }
  @execution.checked_preparation_add_product(r, e, 1L)
}

///|
fn explanation_read_codec_layout(
  name : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> ClientStaticPlanCodecLayout? {
  if name == "compiled_plan" || name == "run_definition" {
    let validation = if name == "compiled_plan" {
      @publication.saved_compiled_plan_validation_construction(nodes)
    } else {
      @publication.saved_run_definition_validation_construction(nodes)
    }
    guard validation is Some(v) else { return None }
    return client_static_plan_codec_layout(
      (bytes, nodes, depth),
      {
        record_headers: v.record_headers,
        reference_slots: v.reference_slots,
        scalar_words: v.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      0L,
      Int64::max(nodes.to_int64(), 13L),
      0L,
    )
  }
  guard @publication.cold_static_plan_validation_construction(
      name,
      true,
      nodes,
      bytes.to_int64(),
      bytes,
      nodes,
      depth,
    )
    is Some(validation) &&
    client_static_plan_codec_layout(
      (bytes, nodes, depth),
      {
        record_headers: validation.owner.record_headers,
        reference_slots: validation.owner.reference_slots,
        scalar_words: validation.owner.scalar_words,
        owned_utf16_units: validation.owned_utf16_units,
        owned_wire_bytes: validation.owned_wire_bytes,
      },
      validation.owned_utf16_units,
      validation.pending_reference_items + validation.unique_reference_items,
      0L,
    )
    is Some(codec) else {
    return None
  }
  Some(codec)
}

///|
/// Grow ONCE after a native scalar-only extent probe, before the full original
/// row crosses into the Host. stored_bytes includes every selected original
/// wire (Definition, admission evidence/Plan and associated Facts). It is a
/// bound, not evidence or permission; the native full read must recheck it.
pub fn[I] reserve_request_explanation_read(
  owner : ClientRequestPreparation[I],
  input : I,
  stored_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ExplanationRead else { return Err(WrongPhase) }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if stored_bytes < 1 || max_bytes < 1 || max_nodes < 2 || max_depth < 1 {
    return Err(Policy)
  }
  // The entry above backs these quotation constructors. Sum all simultaneous
  // parsed input/JS snapshots and complete cold codecs; do not substitute a
  // codec byte multiplier or a Result metadata allowance.
  guard @execution.preparation_representation_cost({
      record_headers: 4L * stored_bytes.to_int64(),
      reference_slots: 8L * stored_bytes.to_int64(),
      scalar_words: 4L * stored_bytes.to_int64(),
      owned_utf16_units: 6L * stored_bytes.to_int64(),
      owned_wire_bytes: 2L * stored_bytes.to_int64(),
    })
    is Some(originals) &&
    @execution.preparation_representation_cost({
      // Two complete Node JSON trees can coexist at InProcess handoff: the
      // Host view and the independent caller copy, plus their validation key
      // arrays. A wire byte bounds each possible node/key position; count both
      // trees and traversals independently of the Common codec representation.
      record_headers: 4L * max_bytes.to_int64(),
      reference_slots: 8L * max_bytes.to_int64(),
      scalar_words: 4L * max_bytes.to_int64(),
      // Both parsed trees' text, the original wire, and JSON.stringify's full
      // six-unit escaping expansion coexist before the output byte check.
      owned_utf16_units: 9L * max_bytes.to_int64(),
      // The shared whole-view validator encodes before its byte check, so
      // reserve the full escaping expansion too. HTTP then constructs its
      // Buffer only after that check and holds it through consumption/close.
      owned_wire_bytes: 6L * max_bytes.to_int64(),
    })
    is Some(consumption) &&
    explanation_read_codec_cost(
      "run_definition", stored_bytes, stored_bytes, 64,
    )
    is Some(definition) &&
    explanation_read_codec_cost("compiled_plan", stored_bytes, stored_bytes, 64)
    is Some(plan) &&
    explanation_read_codec_cost("plan_view", stored_bytes, stored_bytes, 64)
    is Some(plan_view) &&
    explanation_read_codec_cost("logical_map", stored_bytes, stored_bytes, 64)
    is Some(map) &&
    explanation_read_codec_cost(
      "explanation_facts", max_bytes, max_nodes, max_depth,
    )
    is Some(facts) &&
    explanation_read_codec_cost(
      "run_explanation_view", max_bytes, max_nodes, max_depth,
    )
    is Some(view) &&
    @execution.checked_preparation_add_product(originals, definition, 1L)
    is Some(cost) &&
    @execution.checked_preparation_add_product(cost, consumption, 1L)
    is Some(cost) &&
    @execution.checked_preparation_add_product(cost, plan, 1L) is Some(cost) &&
    @execution.checked_preparation_add_product(cost, plan_view, 1L)
    is Some(cost) &&
    @execution.checked_preparation_add_product(cost, map, 1L) is Some(cost) &&
    @execution.checked_preparation_add_product(cost, facts, 1L) is Some(cost) &&
    @execution.checked_preparation_add_product(cost, view, 1L) is Some(cost) else {
    return Err(Policy)
  }
  let old = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(old.0, cost, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(old.1, cost, 1L) is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  owner.phase = match result {
    Ok(_) => ExplanationReadReady(stored_bytes, max_bytes, max_nodes, max_depth)
    Err(_) => ExplanationRead
  }
  result.map_err(issue => Capacity(issue))
}

///|
pub(all) enum ClientRequestExplanationReadIssue {
  Preparation(ClientRequestPreparationIssue)
  Projection(@publication_host.ClientRetainedExplanationIssue)
  ReadLimit
} derive(Debug)

///|
fn[I] grow_explanation_binding(
  owner : ClientRequestPreparation[I],
  input : I,
  cost : Int64,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let old = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(old.0, cost, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(old.1, cost, 1L) is Some(e) else {
    return Err(Policy)
  }
  @resources.reserve_working_preparation_phase(owner.capacity, input, r, e).map_err(issue => {
      Capacity(issue)
    },
  )
}

///|
fn[I] reserve_explanation_binding(
  owner : ClientRequestPreparation[I],
  input : I,
  map : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  let (controls, _, _) = @publication.interactive_logical_map_binding_scanner_controls()
  guard @execution.preparation_representation_cost({
      record_headers: controls.record_headers,
      reference_slots: controls.reference_slots,
      scalar_words: controls.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(entry) else {
    return Err(Policy)
  }
  match grow_explanation_binding(owner, input, entry) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The scalar-only borrowed scanner itself now has backing. It does not
  // issue a hash/key or validate the binding while sizing its real work.
  guard @publication.interactive_logical_map_binding_construction(
      map, plan, max_bytes, max_nodes, max_depth,
    )
    is Some(binding) &&
    @execution.preparation_representation_cost({
      record_headers: binding.owner.record_headers,
      reference_slots: binding.owner.reference_slots,
      scalar_words: binding.owner.scalar_words,
      owned_utf16_units: binding.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(own) else {
    return Err(Policy)
  }
  let step = if binding.steps == 0 {
    0L
  } else {
    guard explanation_read_codec_cost(
        "logical_step_key",
        binding.step_key.0,
        binding.step_key.1,
        binding.step_key.2,
      )
      is Some(value) else {
      return Err(Policy)
    }
    value
  }
  let port = if binding.ports == 0 {
    0L
  } else {
    guard explanation_read_codec_cost(
        "logical_port_key",
        binding.port_complete.0,
        binding.port_complete.1,
        binding.port_complete.2,
      )
      is Some(value) else {
      return Err(Policy)
    }
    value
  }
  guard @publication.cold_static_plan_validation_construction(
      "logical_port_key", false, 0, 0L, 0, 0, 0,
    )
    is Some(body) &&
    @execution.preparation_representation_cost({
      record_headers: body.owner.record_headers,
      reference_slots: body.owner.reference_slots,
      scalar_words: body.owner.scalar_words,
      owned_utf16_units: body.owned_utf16_units,
      owned_wire_bytes: body.owned_wire_bytes,
    })
    is Some(body) &&
    @execution.checked_preparation_add_product(own, step, 1L) is Some(cost) &&
    @execution.checked_preparation_add_product(cost, port, 1L) is Some(cost) &&
    @execution.checked_preparation_add_product(cost, body, 1L) is Some(cost) else {
    return Err(Policy)
  }
  grow_explanation_binding(owner, input, cost)
}

///|
/// The installed structural reader's enforced same-Request constructor.
/// Parent/current/reentry and every binding grow stay on its existing original
/// capacity. Returned wire is held until this SAME read's output handoff; the
/// caller must dispose its aliases before the existing Request cleanup.
pub fn[I] read_request_explanation_view(
  owner : ClientRequestPreparation[I],
  input : I,
  definition_wire : String,
  plan_wire : String?,
  plan_view_wire : String?,
  facts_wire : String?,
  program_cid : String,
  parameters_cid : String,
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
  stored_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientRequestExplanationReadIssue] {
  guard owner.phase is ExplanationReadReady(stored, bytes, nodes, depth) else {
    return Err(Preparation(WrongPhase))
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  if (stored, bytes, nodes, depth) !=
    (stored_bytes, max_bytes, max_nodes, max_depth) {
    return Err(Preparation(ForeignOriginal))
  }
  owner.phase = Selecting
  // This one constructor attempt cannot be replayed while its output or
  // failed scratch still lives. Cleanup retains the SAME original capacity.
  defer {
    owner.phase = ExplanationReadComplete
  }
  // Reobserve the actual original/current boundary even when no facts were
  // retained. Neither phase DATA nor a prior admission survives a callback as
  // permission to start another constructor.
  match grow_explanation_binding(owner, input, 0L) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  let mut total = 142L
  for wire in [Some(definition_wire), plan_wire, plan_view_wire, facts_wire] {
    if wire is Some(wire) {
      let bytes = match @scalar.admit_utf8_length(wire, stored_bytes) {
        Ok(value) => value
        Err(_) => return Err(ReadLimit)
      }
      total += bytes.to_int64()
    }
  }
  if total > stored_bytes.to_int64() {
    return Err(ReadLimit)
  }
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", definition_wire, stored_bytes, stored_bytes, 64,
    ) {
    Err(issue) => return Err(Projection(Contract(issue)))
    Ok(value) => value
  }
  let plan = match (facts_wire, plan_wire) {
    (Some(_), Some(wire)) => {
      let value = match
        @publication.admit_publication_contract(
          "compiled_plan", wire, stored_bytes, stored_bytes, 64,
        ) {
        Err(issue) => return Err(Projection(Contract(issue)))
        Ok(value) => value
      }
      Some(value)
    }
    _ => None
  }
  let refused : Ref[ClientRequestPreparationIssue?] = Ref(None)
  let result = @publication_host.retained_client_run_explanation_view(
    definition,
    plan,
    program_cid,
    parameters_cid,
    plan_view_wire,
    facts_wire,
    namespace_id,
    authority_scope_cid,
    definition_cid,
    max_bytes,
    max_nodes,
    max_depth,
    before_binding=Some((map, original_plan) => {
      match
        reserve_explanation_binding(
          owner, input, map, original_plan, stored_bytes, stored_bytes, 64,
        ) {
        Err(issue) => {
          refused.val = Some(issue)
          false
        }
        Ok(_) => true
      }
    }),
  )
  match refused.val {
    Some(issue) => Err(Preparation(issue))
    None => result.map_err(issue => Projection(issue))
  }
}

///|
/// The fixed read boundary's own typed refusal projection, never an error-code
/// allowlist or a Run outcome classifier. The binding retains the original
/// opaque issue as cause; no refusal is converted into missing metadata.
pub fn request_explanation_read_issue_code(
  issue : ClientRequestExplanationReadIssue,
) -> String {
  match issue {
    ReadLimit
    | Projection(InvalidReadLimits)
    | Projection(Encoding(@encode.OutputLimit)) => "RunExplanationReadLimit"
    Preparation(Capacity(_)) => "RunExplanationReadCapacity"
    Preparation(_) => "RunExplanationReadUnavailable"
    Projection(_) => "RunExplanationEncodingRejected"
  }
}
