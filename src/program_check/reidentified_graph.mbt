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
) -> ReidentifiedStep raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, 1)
  let stack : Array[ProofConversionFrame] = [
    { original: root, next: 0, inputs: [], graph_inputs: [], },
  ]
  let cache : Map[String, Array[ReidentifiedStep]] = Map([])
  let mut result : ReidentifiedStep? = None
  while !stack.is_empty() {
    identity_charge(remaining, 1)
    let frame = stack[stack.length() - 1]
    if frame.next < @step_bounds.input_count(frame.original) {
      if @step_bounds.source_at(frame.original, frame.next)
        is Some(GraphInput(input)) {
        let mut owner : BuiltUnit? = None
        for unit in units {
          identity_charge(remaining, 1)
          if physical_equal(
              unit.pipeline,
              @graph_input.checked_pipeline(@graph_input.bound_owner(input)),
            ) {
            if owner is Some(_) {
              raise ForeignOwner
            }
            owner = Some(unit)
          }
        }
        guard owner is Some(unit) else { raise ForeignOwner }
        let converted = reidentify_graph_input(unit, input, remaining)
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
      let key = @wire.cid(
        @wire.program_proof_witness(@step_bounds.checked_proof(child)),
      )
      identity_charge(remaining, key.length())
      let mut found : ReidentifiedStep? = None
      if cache.get(key) is Some(bucket) {
        for entry in bucket {
          identity_charge(remaining, 1)
          if physical_equal(entry.original, child) {
            found = Some(entry)
            break
          }
        }
      }
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
    let mut owner : BuiltUnit? = None
    for unit in units {
      identity_charge(remaining, 1)
      if physical_equal(
          unit.pipeline,
          @step_bounds.checked_pipeline(frame.original),
        ) {
        if owner is Some(_) {
          raise ForeignOwner
        }
        owner = Some(unit)
      }
    }
    guard owner is Some(unit) else { raise ForeignOwner }
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
    match cache.get(key) {
      Some(bucket) => bucket.push(converted)
      None => cache[key] = [converted]
    }
    ignore(stack.pop())
    if stack.is_empty() {
      result = Some(converted)
    }
  }
  guard result is Some(result) else { raise UnconvertedProofInput }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}
