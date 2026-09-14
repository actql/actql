///|
priv struct PreparedInputs {
  inputs : Array[BoundInput]
  work : Int
  input_work : Int
}

///|
// A proof's canonical input multiset is not its data-edge order. Match each
// occurrence to an actual edge, preserving repeats and exact applied owners.
// Augmenting paths avoid both factorial enumeration and greedy alias loss.
fn select_prepared_inputs(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  proof : @wire.ProgramProofClaim,
  candidates : Array[Array[BoundInput]],
  bindings : CountBindings?,
  max_work : Int,
  max_input_work : Int,
) -> Result[PreparedInputs, (Issue, Int, Int)] {
  let mut work = 0
  let mut input_work = 0
  guard @pipeline.step_at(pipeline, index) is Some(step) else {
    return Err((MissingStep, work, input_work))
  }
  let (_, rule) = match
    operation_rule(
      step,
      bindings,
      @wire.unit(@wire.program_proof_witness(proof)),
    ) {
    Ok(v) => v
    Err(e) => return Err((e, work, input_work))
  }
  let n = candidates.length()
  if !rule_input_count_valid(rule, n) {
    return Err((InputCountMismatch, work, input_work))
  }
  if max_work < 0 || n > max_work / 6 {
    return Err((OperandWorkLimit, work, input_work))
  }
  work = n * 6
  if n > 0 && n > (max_work - work) / n {
    return Err((OperandWorkLimit, work, input_work))
  }
  work += n * n
  let edges : Array[Array[BoundInput?]] = []
  let derivation = @wire.derivation(@wire.program_proof_witness(proof))
  for edge in 0..<n {
    let row : Array[BoundInput?] = Array::make(n, None)
    for occurrence in 0..<n {
      let cid = @wire.program_proof_input_at(proof, occurrence).unwrap()
      if derivation is @wire.Add(left, right) &&
        cid != (if edge == 0 { left } else { right }) {
        continue
      }
      for candidate in candidates[occurrence] {
        if work == max_work {
          return Err((OperandWorkLimit, work, input_work))
        }
        work += 1
        let (matched, used) = check_input_target_usage(
          pipeline,
          step,
          rule,
          n,
          edge,
          candidate,
          max_input_work - input_work,
        )
        input_work += used
        match matched {
          Ok(_) => {
            row[occurrence] = Some(candidate)
            break
          }
          Err(InputWorkLimit) => return Err((InputWorkLimit, work, input_work))
          Err(_) => ()
        }
      }
    }
    edges.push(row)
  }
  let assigned = Array::make(n, -1)
  let selected = Array::make(n, -1)
  for root in 0..<n {
    if n > max_work - work {
      return Err((OperandWorkLimit, work, input_work))
    }
    work += n
    let previous = Array::make(n, -1)
    let queue = [root]
    let mut cursor = 0
    let mut free = -1
    while cursor < queue.length() && free == -1 {
      let edge = queue[cursor]
      cursor += 1
      for occurrence in 0..<n {
        if work == max_work {
          return Err((OperandWorkLimit, work, input_work))
        }
        work += 1
        if previous[occurrence] != -1 || edges[edge][occurrence] is None {
          continue
        }
        previous[occurrence] = edge
        if assigned[occurrence] == -1 {
          free = occurrence
          break
        }
        queue.push(assigned[occurrence])
      }
    }
    if free == -1 {
      return Err((InputTargetMismatch(root), work, input_work))
    }
    while free != -1 {
      if work == max_work {
        return Err((OperandWorkLimit, work, input_work))
      }
      work += 1
      let edge = previous[free]
      let old = selected[edge]
      selected[edge] = free
      assigned[free] = edge
      free = old
    }
  }
  let inputs = []
  for edge in 0..<n {
    inputs.push(edges[edge][selected[edge]].unwrap())
  }
  Ok({ inputs, work, input_work, })
}
