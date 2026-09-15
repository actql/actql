///|
priv struct ProofConversionFrame {
  original : @step_bounds.StepBound
  mut next : Int
  inputs : Array[ReidentifiedStep]
  graph_inputs : Array[ReidentifiedGraphInput]
}

///|
// Iterative, dependency-first conversion. The cache uses CIDs only as buckets;
// reuse additionally requires the exact admitted StepBound owner. Equal wire
// evidence from another Program never establishes this correspondence.
fn reidentify_step_graph(
  units : Array[BuiltUnit],
  root : @step_bounds.StepBound,
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> ReidentifiedStep raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  let session = match conversion {
    Some(session) => session
    None => proof_conversion(units, remaining)
  }
  if session.failed {
    raise UnconvertedProofInput
  }
  errdefer {
    session.failed = true
  }
  let result = convert_proof_graph(session, root, remaining)
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
fn convert_proof_graph(
  session : ProofConversion,
  root : @step_bounds.StepBound,
  remaining : IdentityBudget,
) -> ReidentifiedStep raise UnitBuildFailure {
  identity_charge(remaining, 1)
  if converted_proof(session, root, remaining) is Some(converted) {
    return converted
  }
  let stack : Array[ProofConversionFrame] = [
    { original: root, next: 0, inputs: [], graph_inputs: [], },
  ]
  let mut result : ReidentifiedStep? = None
  while !stack.is_empty() {
    identity_charge(remaining, 1)
    let frame = stack[stack.length() - 1]
    if frame.next < @step_bounds.input_count(frame.original) {
      if @step_bounds.source_at(frame.original, frame.next)
        is Some(GraphInput(input)) {
        let key = @wire.cid(@graph_input.bound_witness(input))
        identity_charge(remaining, key.length())
        let mut found : ReidentifiedGraphInput? = None
        if session.graph_cache.get(key) is Some(bucket) {
          for entry in bucket {
            identity_charge(remaining, 1)
            if physical_equal(entry.original, input) {
              found = Some(entry)
              break
            }
          }
        }
        let converted = match found {
          Some(value) => value
          None => {
            let unit = proof_conversion_owner(
              session,
              @graph_input.checked_pipeline(@graph_input.bound_owner(input)),
              remaining,
            )
            let value = reidentify_graph_input(unit, input, remaining)
            identity_charge(remaining, 1)
            match session.graph_cache.get(key) {
              Some(bucket) => bucket.push(value)
              None => session.graph_cache[key] = [value]
            }
            value
          }
        }
        identity_charge(remaining, 1)
        frame.graph_inputs.push(converted)
        frame.next += 1
        continue
      }
      guard @step_bounds.input_at(frame.original, frame.next) is Some(child) else {
        // Graph-input evidence requires its own source-preserving conversion.
        // Do not substitute an old witness or a fabricated operation owner.
        raise UnconvertedProofInput
      }
      let found = converted_proof(session, child, remaining)
      if found is Some(converted) {
        identity_charge(remaining, 1)
        frame.inputs.push(converted)
        frame.next += 1
      } else {
        identity_charge(remaining, 1)
        stack.push({ original: child, next: 0, inputs: [], graph_inputs: [], })
      }
      continue
    }
    let unit = proof_conversion_owner(
      session,
      @step_bounds.checked_pipeline(frame.original),
      remaining,
    )
    if session.on_construct is Some(observe) {
      observe(frame.original)
    }
    let converted = reidentify_step(
      unit,
      frame.original,
      frame.inputs,
      remaining,
      graph_inputs=frame.graph_inputs,
    )
    let key = @wire.cid(
      @wire.program_proof_witness(@step_bounds.checked_proof(frame.original)),
    )
    identity_charge(remaining, key.length())
    identity_charge(remaining, 1)
    match session.cache.get(key) {
      Some(bucket) => bucket.push(converted)
      None => session.cache[key] = [converted]
    }
    ignore(stack.pop())
    if stack.is_empty() {
      result = Some(converted)
    }
  }
  guard result is Some(result) else { raise UnconvertedProofInput }
  result
}
