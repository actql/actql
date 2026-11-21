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
  begin_original_explanation_read(owner, input, false)
}

///|
/// Admit the original Context query's fixed controls before the extent probe.
pub fn[I] begin_request_explanation_context_read(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestPreparationIssue] {
  begin_original_explanation_read(owner, input, true)
}

///|
fn[I] begin_original_explanation_read(
  owner : ClientRequestPreparation[I],
  input : I,
  context : Bool,
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
  let extra = if context {
    @execution.preparation_representation_cost({
      // Added companion scalar fields, guards, read wrappers and digest
      // results. The selected query bodies still fit the fixed SQL bound.
      record_headers: 24L,
      reference_slots: 48L,
      scalar_words: 32L,
      owned_utf16_units: 2L * 64L,
      owned_wire_bytes: 2L * 32L,
    }).unwrap()
  } else {
    0L
  }
  let entry = request_explanation_read_entry_bytes + extra
  guard @execution.checked_preparation_add_product(old.0, entry, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(old.1, entry, 1L) is Some(e) else {
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
    Ok(_) => if context { ExplanationContextRead } else { ExplanationRead }
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
  reserve_original_explanation_read(
    owner,
    input,
    stored_bytes,
    max_bytes,
    max_nodes,
    max_depth,
    None,
  )
}

///|
/// Reserve the exact companion extents before the Journal's original rows can
/// cross into the Host. A legacy Run can have neither companion field.
pub fn[I] reserve_request_explanation_context_read(
  owner : ClientRequestPreparation[I],
  input : I,
  stored_bytes : Int,
  context_bytes : Int,
  template_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ExplanationContextRead else { return Err(WrongPhase) }
  if context_bytes < 0 ||
    template_bytes < 0 ||
    (context_bytes == 0) != (template_bytes == 0) ||
    (
      context_bytes > 0 &&
      context_bytes.to_int64() + template_bytes.to_int64() + 206L >=
      stored_bytes.to_int64()
    ) {
    return Err(Policy)
  }
  reserve_original_explanation_read(
    owner,
    input,
    stored_bytes,
    max_bytes,
    max_nodes,
    max_depth,
    Some((context_bytes, template_bytes)),
  )
}

///|
fn[I] reserve_original_explanation_read(
  owner : ClientRequestPreparation[I],
  input : I,
  stored_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  companion : (Int, Int)?,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if stored_bytes < 1 || max_bytes < 1 || max_nodes < 2 || max_depth < 1 {
    return Err(Policy)
  }
  let view_schema = if companion is Some(_) {
    "run_explanation_context_view"
  } else {
    "run_explanation_view"
  }
  let companion_cost = match companion {
    Some((context_bytes, template_bytes)) if context_bytes > 0 => {
      if context_bytes > max_bytes {
        return Err(Policy)
      }
      guard explanation_read_codec_cost(
          "explanation_context", context_bytes, max_nodes, max_depth,
        )
        is Some(context) &&
        explanation_read_codec_cost(
          "bound_invocation_template", template_bytes, template_bytes, 64,
        )
        is Some(template) &&
        @execution.preparation_representation_cost({
          // Both native readbacks can hash the held Context. The original
          // texts already have backing below; count two UTF-8 hash inputs.
          record_headers: 0L,
          reference_slots: 0L,
          scalar_words: 0L,
          owned_utf16_units: 0L,
          owned_wire_bytes: 2L * (context_bytes.to_int64() + 71L),
        })
        is Some(hash_inputs) &&
        @execution.checked_preparation_add_product(context, template, 1L)
        is Some(cost) &&
        @execution.checked_preparation_add_product(cost, hash_inputs, 1L)
        is Some(cost) else {
        return Err(Policy)
      }
      cost
    }
    _ => 0L
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
    explanation_read_codec_cost(view_schema, max_bytes, max_nodes, max_depth)
    is Some(view) &&
    @execution.checked_preparation_add_product(originals, consumption, 1L)
    is Some(cost) &&
    @execution.checked_preparation_add_product(cost, view, 1L) is Some(cost) &&
    @execution.checked_preparation_add_product(cost, companion_cost, 1L)
    is Some(cost) else {
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
  owner.phase = match (result, companion) {
    (Ok(_), Some((context, template))) =>
      ExplanationContextReadReady(
        stored_bytes, context, template, max_bytes, max_nodes, max_depth,
      )
    (Ok(_), None) =>
      ExplanationReadReady(stored_bytes, max_bytes, max_nodes, max_depth)
    (Err(_), Some(_)) => ExplanationContextRead
    (Err(_), None) => ExplanationRead
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
// Native readback and JS's evidence parser already have the full original
// row backed. Size the separate Common codecs from the actual extracted
// wires before parsing a contract. Irrelevant admission evidence never
// becomes a second or third full-row bound for the Plan or its logical map.
fn[I] admit_explanation_read_originals(
  owner : ClientRequestPreparation[I],
  input : I,
  definition_wire : String,
  plan_wire : String?,
  plan_view_wire : String?,
  facts_wire : String?,
  stored_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.PublicationContract, @publication.PublicationContract?),
  ClientRequestExplanationReadIssue,
] {
  let def = match @scalar.admit_utf8_length(definition_wire, stored_bytes) {
    Ok(value) => value
    Err(_) => return Err(ReadLimit)
  }
  guard explanation_read_codec_cost("run_definition", def, def, 64)
    is Some(definition_cost) else {
    return Err(Preparation(Policy))
  }
  let mut cost = definition_cost
  let mut plan_bytes = 0
  if facts_wire is Some(facts) {
    guard plan_wire is Some(plan) && plan_view_wire is Some(view) else {
      return Err(Projection(ForeignOriginal))
    }
    guard @scalar.admit_utf8_length(plan, stored_bytes) is Ok(plan_size) &&
      @scalar.admit_utf8_length(view, max_bytes) is Ok(view_size) &&
      @scalar.admit_utf8_length(facts, max_bytes) is Ok(facts_size) else {
      return Err(ReadLimit)
    }
    // Map nodes are contained in the original bounded Plan view. The map's
    // independent canonical encode can use the full selected wire allowance.
    let view_nodes = Int::min(view_size, max_nodes)
    let facts_nodes = Int::min(facts_size, max_nodes)
    guard explanation_read_codec_cost("compiled_plan", plan_size, plan_size, 64)
      is Some(plan_cost) &&
      explanation_read_codec_cost("plan_view", view_size, view_nodes, max_depth)
      is Some(view_cost) &&
      explanation_read_codec_cost(
        "logical_map", max_bytes, view_nodes, max_depth,
      )
      is Some(map_cost) &&
      explanation_read_codec_cost(
        "explanation_facts", facts_size, facts_nodes, max_depth,
      )
      is Some(facts_cost) &&
      @execution.checked_preparation_add_product(cost, plan_cost, 1L)
      is Some(next) &&
      @execution.checked_preparation_add_product(next, view_cost, 1L)
      is Some(next) &&
      @execution.checked_preparation_add_product(next, map_cost, 1L)
      is Some(next) &&
      @execution.checked_preparation_add_product(next, facts_cost, 1L)
      is Some(next) else {
      return Err(Preparation(Policy))
    }
    plan_bytes = plan_size
    cost = next
  }
  match grow_explanation_binding(owner, input, cost) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", definition_wire, def, def, 64,
    ) {
    Err(issue) => return Err(Projection(Contract(issue)))
    Ok(value) => value
  }
  let plan = match plan_wire {
    Some(wire) if plan_bytes > 0 => {
      let value = match
        @publication.admit_publication_contract(
          "compiled_plan", wire, plan_bytes, plan_bytes, 64,
        ) {
        Err(issue) => return Err(Projection(Contract(issue)))
        Ok(value) => value
      }
      Some(value)
    }
    _ => None
  }
  Ok((definition, plan))
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
  let (definition, plan) = match
    admit_explanation_read_originals(
      owner, input, definition_wire, plan_wire, plan_view_wire, facts_wire, stored_bytes,
      max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
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
/// Build the body for the additive Saved read from its original Journal DATA.
/// The Host holds this Request through authorization, native readback and
/// consumption. The older Facts-only operation uses its own phase and wire.
pub fn[I] read_request_explanation_context(
  owner : ClientRequestPreparation[I],
  input : I,
  definition_wire : String,
  plan_wire : String?,
  plan_view_wire : String?,
  facts_wire : String?,
  context_wire : String?,
  template_wire : String?,
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
  guard owner.phase
    is ExplanationContextReadReady(
      stored,
      context_bytes,
      template_bytes,
      bytes,
      nodes,
      depth
    ) else {
    return Err(Preparation(WrongPhase))
  }
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    (stored, bytes, nodes, depth) ==
    (stored_bytes, max_bytes, max_nodes, max_depth) else {
    return Err(Preparation(ForeignOriginal))
  }
  owner.phase = Selecting
  defer {
    owner.phase = ExplanationReadComplete
  }
  match grow_explanation_binding(owner, input, 0L) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  for
    (wire, extent) in [
      (context_wire, context_bytes),
      (template_wire, template_bytes),
    ] {
    match (wire, extent) {
      (None, 0) => ()
      (Some(wire), extent) if extent > 0 =>
        if @scalar.admit_utf8_length(wire, extent) != Ok(extent) {
          return Err(ReadLimit)
        }
      _ => return Err(Preparation(ForeignOriginal))
    }
  }
  let mut total = if context_bytes > 0 { 206L } else { 142L }
  for
    wire in [
      Some(definition_wire),
      plan_wire,
      plan_view_wire,
      facts_wire,
      context_wire,
      template_wire,
    ] {
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
  let (definition, plan) = match
    admit_explanation_read_originals(
      owner,
      input,
      definition_wire,
      plan_wire,
      plan_view_wire,
      if context_bytes > 0 {
        facts_wire
      } else {
        None
      },
      stored_bytes,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let refused : Ref[ClientRequestPreparationIssue?] = Ref(None)
  let result = @publication_host.retained_client_run_explanation_context(
    definition,
    plan,
    program_cid,
    parameters_cid,
    plan_view_wire,
    facts_wire,
    context_wire,
    template_wire,
    namespace_id,
    definition_cid,
    Int::max(1, template_bytes),
    max_bytes,
    max_nodes,
    max_depth,
    (map, original_plan) => {
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
    },
  )
  if refused.val is Some(issue) {
    return Err(Preparation(issue))
  }
  let projected = match result {
    Err(issue) => return Err(Projection(issue))
    Ok(value) => value
  }
  let wire = match
    retained_explanation_context_wire(
      projected, namespace_id, authority_scope_cid, definition_cid, max_bytes, max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(Projection(issue))
    Ok(value) => value
  }
  grow_explanation_binding(owner, input, 0L)
  .map(_ => wire)
  .map_err(issue => Preparation(issue))
}

///|
fn retained_explanation_context_wire(
  projected : @publication_host.ClientRetainedExplanationContext?,
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication_host.ClientRetainedExplanationIssue] {
  let wire = try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "explanation")
    @encode.begin_object(writer)
    match projected {
      None => {
        @encode.key(writer, "reason")
        @encode.string_value(writer, "not_retained")
        @encode.key(writer, "state")
        @encode.string_value(writer, "not_projected")
      }
      Some(projected) => {
        @encode.key(writer, "state")
        @encode.string_value(writer, "projected")
        @encode.key(writer, "view")
        @encode.begin_object(writer)
        @encode.key(writer, "context")
        @identity.emit_value(projected.context, writer)
        @encode.key(writer, "facts")
        @identity.emit_value(projected.facts, writer)
        @encode.key(writer, "plan")
        @identity.emit_value(projected.plan, writer)
        @encode.key(writer, "version")
        @encode.string_value(writer, "actql-static-explanation/0.1")
        @encode.end_object(writer)
      }
    }
    @encode.end_object(writer)
    @encode.key(writer, "run_ref")
    @encode.begin_object(writer)
    @encode.key(writer, "authorityScopeCid")
    @encode.string_value(writer, authority_scope_cid)
    @encode.key(writer, "namespaceId")
    @encode.string_value(writer, namespace_id)
    @encode.key(writer, "runDefinitionCid")
    @encode.string_value(writer, definition_cid)
    @encode.end_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-run-explanation-context-view/0.1")
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    issue => return Err(Encoding(issue))
  }
  @publication.parse_interactive_run_control_shape(
    "run_explanation_context_view", wire, max_bytes, max_nodes, max_depth,
  )
  .map(_ => wire)
  .map_err(issue => Contract(issue))
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
