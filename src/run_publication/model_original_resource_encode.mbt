///|
/// Bounded DATA packaging for the existing closed private artifact. The
/// caller supplies original Owner observations; this never authenticates a
/// Scope, Store ACK, stable cut, current Ledger or permission to resume/send.
/// All source trees, emitted wire and final validation overlap are funded by
/// the original caller before entry, not derived from these codec ceilings.
pub fn encode_model_original_resource_document(
  origin_wire : String,
  resource_state_wire : String,
  cut_wire : String,
  resource_phase : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, PublicationContractIssue] {
  // Reject the UTF-16 lower bound before allocating any additional trees.
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  if origin_wire.length() > max_wire_bytes ||
    resource_state_wire.length() > max_wire_bytes - origin_wire.length() ||
    cut_wire.length() >
    max_wire_bytes - origin_wire.length() - resource_state_wire.length() ||
    resource_phase.length() >
    max_wire_bytes -
    origin_wire.length() -
    resource_state_wire.length() -
    cut_wire.length() {
    return Err(Encoding)
  }
  let origin = match
    parse_contract_wire(
      origin_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let state = match
    parse_contract_wire(
      resource_state_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let cut = match
    parse_contract_wire(
      cut_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  try {
    // Never replace the original Writer bytes with a lexical rewrite and
    // call its different digest the same saved resource state.
    if @json.stringify_value(state, max_wire_bytes, max_nodes, max_depth) !=
      resource_state_wire {
      return Err(InvalidWire)
    }
    let state_cid = @json.cid_value(state, max_wire_bytes, max_nodes, max_depth)
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "cut")
    @json.emit_value(cut, writer)
    @encode.ordered_key(writer, "origin")
    @json.emit_value(origin, writer)
    @encode.ordered_key(writer, "resource_phase")
    @encode.string_value(writer, resource_phase)
    @encode.ordered_key(writer, "resource_state")
    @json.emit_value(state, writer)
    @encode.ordered_key(writer, "resource_state_cid")
    @encode.string_value(writer, state_cid)
    @encode.ordered_key(writer, "version")
    @encode.string_value(writer, "actql-model-original-resource-state/0.1")
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    // Reuse the existing generated closed shape and embedded-CID reader;
    // there is no independently handwritten origin/cut/schema validator.
    match
      read_model_original_resource_document(
        wire, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(_) => Ok(wire)
      Err(issue) => Err(issue)
    }
  } catch {
    _ => Err(Encoding)
  }
}
