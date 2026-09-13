///|
struct ReidentifiedGraphInput {
  original : @graph_input.InputBound
  witness : @wire.WireWitness
  limit : @wire.LimitClaim
  limit_bytes : Bytes
  claims : @wire.MixedClaims
}

///|
// The enclosing application retains its original GraphInputs and policy
// agreement. This conversion does not execute the input preflight.
fn reidentify_graph_input(
  unit : BuiltUnit,
  input : @graph_input.InputBound,
  budget : IdentityBudget,
) -> ReidentifiedGraphInput raise UnitBuildFailure {
  let owner = @graph_input.bound_owner(input)
  if !physical_equal(unit.pipeline, @graph_input.checked_pipeline(owner)) {
    raise ForeignOwner
  }
  let original = @graph_input.bound_witness(input)
  let (measure, label, field) = match @wire.unit(original) {
    Nodes => (@graph_input.Nodes, "nodes", "max_graph_input_nodes")
    Edges => (@graph_input.Edges, "edges", "max_graph_input_edges")
    _ => raise UnconvertedProofInput
  }
  let index = @graph_input.bound_input(input)
  guard @graph_input.input_limit(owner, index, measure) is Some(old_limit) &&
    @pipeline.input_at(unit.pipeline, index) is Some((name, _)) else {
    raise ForeignOwner
  }
  guard @policy.ceiling(@graph_input.selected_policy(owner), field)
    is Some(ceiling) else {
    raise ForeignOwner
  }
  if @wire.value(original) != @policy.ceiling_value(ceiling) ||
    @wire.limit_subject(old_limit) != "graph-input:" + name + ":" + label {
    raise ForeignOwner
  }
  let remaining = IdentityBudget::{ ..budget, }
  for _ in 0..<3 {
    identity_charge(remaining, name.length())
  }
  identity_charge(remaining, unit.definition_cid.length())
  let reference = "unit:" +
    unit.definition_cid +
    "#/inputs/" +
    name.replace(old="~", new="~0").replace(old="/", new="~1")
  let host = publication_host(ceiling, remaining)
  let host_bytes = publication_metadata(
    w => @host.emit(host, w) catch { e => raise Encoding(e) },
    remaining,
  )
  identity_charge(remaining, host_bytes.length())
  let host_wire = @wire.admit(host_bytes, @host.cid(host), {
    max_bytes: host_bytes.length(),
    max_nodes: host_bytes.length(),
    max_depth: remaining.depth,
  })
  let host_wire = match host_wire {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  let hash = identity_writer(remaining)
  emit_graph_input_limit(reference, label, host, hash, None)
  let limit_cid = identity_finish(remaining, hash)
  let limit_bytes = publication_metadata(
    w => emit_graph_input_limit(reference, label, host, w, Some(limit_cid)),
    remaining,
  )
  let hash = identity_writer(remaining)
  emit_graph_input_witness(
    reference,
    label,
    @wire.value(original),
    limit_cid,
    hash,
    None,
  )
  let witness_cid = identity_finish(remaining, hash)
  let bytes = publication_metadata(
    w => {
      emit_graph_input_witness(
        reference,
        label,
        @wire.value(original),
        limit_cid,
        w,
        Some(witness_cid),
      )
    },
    remaining,
  )
  identity_charge(remaining, bytes.length())
  let witness = match
    @wire.admit(bytes, witness_cid, {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  identity_charge(remaining, limit_bytes.length())
  identity_charge(remaining, 3)
  let claims = match
    @wire.check_mixed_claims([host_wire, witness], [(limit_bytes, limit_cid)], {
      max_entities: 3,
      max_references: remaining.work / 2,
      max_bytes: limit_bytes.length(),
      max_nodes: limit_bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationMixed(e)
  }
  let (references, _, _) = @wire.mixed_usage(claims)
  identity_charge(remaining, references)
  guard @wire.mixed_limit_at(claims, 0) is Some(limit) else {
    raise ForeignOwner
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  { original: input, witness, limit, limit_bytes, claims, }
}
