///|
pub(all) struct IncomingGateLimits {
  max_work : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub enum IncomingGateIssue {
  InvalidLimits
  BudgetExceeded
  MissingSite
  NotSuccessGate
  UnresolvedContracts
  Hash(@encode.EncodeFailure)
}

///|
/// A static requirement identity, not proof that its producer has succeeded.
struct PreparedIncomingGate {
  owner : ProgramIncomingLinks
  check : IncomingExecutionCheck
  producer : String
  milestone : IncomingMilestone
  cid : String
  work : Int
  bytes : Int
  nodes : Int
}

///|
fn emit_incoming_gate_body(
  producer : String,
  milestone : IncomingMilestone,
  writer : @encode.Writer,
  cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for
    key in [
      "completion_contracts", "completion_nodes", "effect_contracts", "effect_nodes",
    ] {
    @encode.key(writer, key)
    @encode.begin_object(writer)
    @encode.end_object(writer)
  }
  @encode.key(writer, "empty_items")
  @encode.string_value(writer, "require-successful-computation-and-preflight")
  @encode.key(writer, "milestone")
  @encode.string_value(
    writer,
    match milestone {
      Accepted => "accepted"
      Completed => "completed"
    },
  )
  @encode.key(writer, "producer_node_id")
  @encode.string_value(writer, producer)
  if cid is Some(value) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, value)
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-graph-success-requirement/0.1")
  @encode.end_object(writer)
}

///|
/// Construct only when the owned readiness check establishes that no Effect
/// contracts need interpretation. Never replace unadmitted contracts with {}.
pub fn prepare_incoming_gate(
  owner : ProgramIncomingLinks,
  index : Int,
  limits : IncomingGateLimits,
) -> Result[PreparedIncomingGate, IncomingGateIssue] {
  if limits.max_work < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  guard owner.incoming.entries.get(index) is Some(site) else {
    return Err(MissingSite)
  }
  guard site.requirement is Success(milestone, producer) else {
    return Err(NotSuccessGate)
  }
  if owner.work >= limits.max_work {
    return Err(BudgetExceeded)
  }
  let at = @program_refs.stage_semantics_index(
    @program_refs.stage_definition_semantics(producer.definition),
  )
  let stage = @stages.stage_at(
    @stage_results.wiring_source(owner.incoming.wiring),
    at,
  ).unwrap()
  let fields = @decode.object_length(@syntax.stage_body(stage)).unwrap()
  if fields > limits.max_work - owner.work - 1 {
    return Err(BudgetExceeded)
  }
  guard incoming_execution_at(owner, index) is Some(Connected(check)) else {
    return Err(UnresolvedContracts)
  }
  let name = @program_refs.stage_definition_id(producer.definition)
  let hash = try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_incoming_gate_body(name, milestone, writer, None)
    @encode.finish_hash_usage(writer)
  } catch {
    e => return Err(Hash(e))
  }
  Ok({
    owner,
    check,
    producer: name,
    milestone,
    cid: "sha256:" + hash.0,
    work: owner.work + fields + 1,
    bytes: hash.1,
    nodes: hash.2,
  })
}

///|
pub fn incoming_gate_owner(v : PreparedIncomingGate) -> ProgramIncomingLinks {
  v.owner
}

///|
pub fn incoming_gate_check(v : PreparedIncomingGate) -> IncomingExecutionCheck {
  v.check
}

///|
pub fn incoming_gate_cid(v : PreparedIncomingGate) -> String {
  v.cid
}

///|
pub fn incoming_gate_usage(v : PreparedIncomingGate) -> (Int, Int, Int) {
  (v.work, v.bytes, v.nodes)
}

///|
pub fn emit_incoming_gate_preimage(
  v : PreparedIncomingGate,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_incoming_gate_body(v.producer, v.milestone, writer, None)
}

///|
pub fn emit_incoming_gate(
  v : PreparedIncomingGate,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_incoming_gate_body(v.producer, v.milestone, writer, Some(v.cid))
}
