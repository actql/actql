///|
/// Complete success-gate identities for one incoming inventory. Result and
/// receipt obligations remain owned by that inventory, not discharged here.
struct ProgramIncomingGates {
  owner : ProgramIncomingLinks
  stages : Array[Array[PreparedIncomingGate]]
  work : Int
  bytes : Int
  nodes : Int
}

///|
pub enum ProgramIncomingGatesIssue {
  InvalidLimits
  BudgetExceeded
  Gate(Int, IncomingGateIssue)
}

///|
/// All gates succeed atomically. Work includes the owner prefix once; emitted
/// bytes and nodes accumulate across gates, while depth bounds each emission.
pub fn prepare_program_incoming_gates(
  owner : ProgramIncomingLinks,
  limits : IncomingGateLimits,
) -> Result[ProgramIncomingGates, ProgramIncomingGatesIssue] {
  if limits.max_work < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let count = owner.incoming.identity.stages.length()
  if owner.work >= limits.max_work || count > limits.max_work - owner.work - 1 {
    return Err(BudgetExceeded)
  }
  let stages : Array[Array[PreparedIncomingGate]] = Array::makei(count, _ => [])
  let mut work = owner.work + 1 + count
  let mut bytes = 0
  let mut nodes = 0
  for index in 0..<owner.incoming.entries.length() {
    if work == limits.max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let site = owner.incoming.entries[index]
    match site.requirement {
      Result(_, _, _) | Receipt(_, _, _) => ()
      Success(_, _) => {
        let gate = match
          prepare_incoming_gate(owner, index, {
            max_work: owner.work + (limits.max_work - work),
            max_bytes: limits.max_bytes - bytes,
            max_nodes: limits.max_nodes - nodes,
            max_depth: limits.max_depth,
          }) {
          Ok(gate) => gate
          Err(issue) => return Err(Gate(index, issue))
        }
        work += gate.work - owner.work
        bytes += gate.bytes
        nodes += gate.nodes
        stages[site.stage].push(gate)
      }
    }
  }
  Ok({ owner, stages, work, bytes, nodes, })
}

///|
pub fn program_incoming_gates_owner(
  v : ProgramIncomingGates,
) -> ProgramIncomingLinks {
  v.owner
}

///|
pub fn program_incoming_gates_usage(
  v : ProgramIncomingGates,
) -> (Int, Int, Int) {
  (v.work, v.bytes, v.nodes)
}

///|
pub fn program_incoming_gates_stage_count(v : ProgramIncomingGates) -> Int {
  v.stages.length()
}

///|
pub fn program_incoming_gates_count(
  v : ProgramIncomingGates,
  stage : Int,
) -> Int? {
  v.stages.get(stage).map(gates => gates.length())
}

///|
pub fn program_incoming_gates_at(
  v : ProgramIncomingGates,
  stage : Int,
  index : Int,
) -> PreparedIncomingGate? {
  match v.stages.get(stage) {
    None => None
    Some(gates) => gates.get(index)
  }
}
