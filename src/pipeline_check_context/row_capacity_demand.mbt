///|
pub enum RowCapacityIssue {
  BudgetExceeded
  InvalidGraph
  Bindings(Int, @step_bounds.Issue)
  Construction(Int, Int, @step_bounds.DeriveBoundIssue)
  Extension(Int, @wire.ProgramExtensionIssue)
}

///|
priv suberror RowCapacityStop {
  RowCapacityStop(RowCapacityIssue)
}

///|
priv enum RowBoundState {
  Unvisited
  Visiting
  Missing
  Found(@step_bounds.StepBound)
}

///|
priv struct RowCapacityStage {
  pipeline : @pipeline.CheckedPipeline
  bindings : @step_bounds.CountBindings?
  material : CapacityMaterial
  roots : Array[@pipeline.Target]
  steps : Array[RowBoundState]
  inputs : Array[RowBoundState]
  known : Map[String, Bool]
  supplied : Map[String, Array[@wire.ProgramProofClaim]]
  added : Array[@wire.ProgramProofClaim]
  proof_count : Int
}

///|
priv enum RowCapacityFrame {
  Visit(Int, @pipeline.Target)
  Forward(Int, @pipeline.Target, Int, @pipeline.Target)
  Finish(Int, @step_bounds.BoundDerivation, Array[@pipeline.Target], Bool)
}

///|
priv struct RowCapacityResult {
  materials : Array[CapacityMaterial]
  work : Int
  text : Int
  bytes : Int
  nodes : Int
  input_work : Int
  operand_work : Int
}

///|
// Demand follows actual Result targets through the existing non-expanding
// transfer rules and existing row-bound operand plans. Unavailable premises
// do not become Host claims. Cache entries retain exact producer handles.
fn derive_row_capacity(
  prepared : @stage_results.PreparedLocalSource,
  materials : Array[CapacityMaterial],
  seeds : Array[Array[@step_bounds.StepBound?]],
  max_work : Int,
  metadata : @wire.Limits,
  max_input_work : Int,
  max_operand_work : Int,
  count_bindings : CapacityCountBindings,
  max_text_bytes : Int,
) -> Result[RowCapacityResult, RowCapacityIssue] {
  let mut remaining = max_work
  let mut bytes = 0
  let mut nodes = 0
  let mut input_work = 0
  let mut operand_work = 0
  let mut text = 0
  fn spend(n : Int) -> Unit raise RowCapacityStop {
    if n < 0 || n > remaining {
      raise RowCapacityStop(BudgetExceeded)
    }
    remaining -= n
  }
  let stages : Array[RowCapacityStage] = []
  let owners : Map[Int, Array[Int]] = Map([])
  fn owner(pipeline : @pipeline.CheckedPipeline) -> Int raise RowCapacityStop {
    spend(1)
    let key = @decode.cursor_span(@pipeline.source(pipeline)).start_byte
    guard owners.get(key) is Some(bucket) else {
      raise RowCapacityStop(InvalidGraph)
    }
    for stage in bucket {
      spend(1)
      if physical_equal(stages[stage].pipeline, pipeline) {
        return stage
      }
    }
    raise RowCapacityStop(InvalidGraph)
  }
  fn state(stage : Int, target : @pipeline.Target) -> RowBoundState {
    match target {
      @pipeline.Step(i) => stages[stage].steps[i]
      @pipeline.Input(i) => stages[stage].inputs[i]
    }
  }
  fn retain(
    stage : Int,
    target : @pipeline.Target,
    value : RowBoundState,
  ) -> Unit {
    match target {
      @pipeline.Step(i) => stages[stage].steps[i] = value
      @pipeline.Input(i) => stages[stage].inputs[i] = value
    }
  }
  fn add_closure(
    stage : Int,
    bound : @step_bounds.StepBound,
  ) -> Unit raise RowCapacityStop {
    let stack = [bound]
    while !stack.is_empty() {
      spend(1)
      let bound = stack.pop().unwrap()
      let proof = @step_bounds.checked_proof(bound)
      let id = @wire.cid(@wire.program_proof_witness(proof))
      if stages[stage].known.contains(id) {
        continue
      }
      stages[stage].known[id] = true
      stages[stage].added.push(proof)
      let n = @step_bounds.input_count(bound)
      spend(n)
      for i in 0..<n {
        guard @step_bounds.input_at(bound, i) is Some(input) else {
          raise RowCapacityStop(InvalidGraph)
        }
        stack.push(input)
      }
    }
  }
  try {
    spend(materials.length())
    let wiring = @stage_results.local_source_wiring(prepared)
    for stage in 0..<materials.length() {
      let ports = @stage_results.stage_port_publications(
        @stage_results.wiring_stage_at(wiring, stage).unwrap(),
      )
      let orders = @results.checked_producer_orders(
        @results.ports_orders(ports),
      )
      let pipeline = @pipeline.contextual_orders_pipeline(
        @pipeline.contextual_closure_at(orders, 0).unwrap(),
      )
      let (bindings, used, used_text) = match
        capacity_count_binding(
          count_bindings,
          pipeline,
          remaining,
          max_text_bytes - text,
        ) {
        Ok(value) => value
        Err(issue) => raise RowCapacityStop(Bindings(stage, issue))
      }
      spend(used)
      text += used_text
      let steps = @pipeline.step_count(pipeline)
      let inputs = @pipeline.input_count(pipeline)
      spend(steps)
      spend(inputs)
      spend(@results.port_count(ports))
      let roots = []
      for i in 0..<@results.port_count(ports) {
        roots.push(
          @results.target(
            @results.port_result(@results.port_at(ports, i).unwrap()),
          ),
        )
      }
      let claims = @host.source_claims(materials[stage].sources)
      let arithmetic = @wire.program_claim_arithmetic(claims)
      let count = @wire.claim_count(arithmetic)
      spend(count)
      let known : Map[String, Bool] = Map([])
      let supplied : Map[String, Array[@wire.ProgramProofClaim]] = Map([])
      let mut proof_count = 0
      for i in 0..<count {
        known[@wire.cid(@wire.claim_at(arithmetic, i).unwrap())] = true
        if @wire.program_claim_proof_at(claims, i) is Some(proof) {
          proof_count += 1
          let witness = @wire.program_proof_witness(proof)
          let law = @law.name(@wire.law(witness))
          spend(law.length())
          if @wire.source(witness) is @wire.Program(subject, _) {
            spend(subject.length())
            match supplied.get(subject) {
              Some(entries) => entries.push(proof)
              None => supplied[subject] = [proof]
            }
          }
        }
      }
      stages.push({
        pipeline,
        bindings,
        material: materials[stage],
        roots,
        steps: Array::makei(steps, i => {
          match seeds[stage][i] {
            Some(bound) => Found(bound)
            None => Unvisited
          }
        }),
        inputs: Array::make(inputs, Unvisited),
        known,
        supplied,
        added: [],
        proof_count,
      })
      let key = @decode.cursor_span(@pipeline.source(pipeline)).start_byte
      match owners.get(key) {
        Some(bucket) => bucket.push(stage)
        None => owners[key] = [stage]
      }
    }
    for root_stage in 0..<stages.length() {
      for root in stages[root_stage].roots {
        let stack = [Visit(root_stage, root)]
        while !stack.is_empty() {
          spend(1)
          match stack.pop().unwrap() {
            Visit(stage, target) => {
              match state(stage, target) {
                Found(_) | Missing => continue
                Visiting => raise RowCapacityStop(InvalidGraph)
                Unvisited => ()
              }
              retain(stage, target, Visiting)
              let pipeline = stages[stage].pipeline
              match target {
                @pipeline.Input(index) =>
                  match @pipeline.input_producer(pipeline, index) {
                    Some(producer) => {
                      let source = owner(@pipeline.producer_pipeline(producer))
                      let source_target = @pipeline.producer_target(producer)
                      stack.push(Forward(stage, target, source, source_target))
                      stack.push(Visit(source, source_target))
                    }
                    None => retain(stage, target, Missing)
                  }
                @pipeline.Step(index) => {
                  let derivation = match
                    @step_bounds.prepare_bound_derivation(
                      pipeline,
                      index,
                      bindings=stages[stage].bindings,
                    ) {
                    Ok(value) => Some(value)
                    Err(
                      @step_bounds.UnsupportedOperation
                      | @step_bounds.UnresolvedCount
                      | @step_bounds.LawMismatch
                    ) => None
                    Err(issue) =>
                      raise RowCapacityStop(
                        Construction(stage, index, Application(issue)),
                      )
                  }
                  if derivation is Some(derivation) {
                    spend(derivation.input_count)
                    let targets = []
                    let mut rows_only = true
                    for i in 0..<derivation.input_count {
                      let operand = @step_bounds.bound_derivation_input_at(
                        derivation,
                        derivation.input_count,
                        i,
                      ).unwrap()
                      if operand.unit != @derivation.Rows {
                        rows_only = false
                      }
                      targets.push(operand.target)
                    }
                    if rows_only {
                      stack.push(Finish(stage, derivation, targets, false))
                      for i = targets.length() - 1; i >= 0; i = i - 1 {
                        stack.push(Visit(stage, targets[i]))
                      }
                    } else {
                      retain(stage, target, Missing)
                    }
                  } else {
                    match
                      @step_bounds.forwarded_bound_target(
                        pipeline,
                        index,
                        @derivation.Rows,
                      ) {
                      Some(input) => {
                        stack.push(Forward(stage, target, stage, input))
                        stack.push(Visit(stage, input))
                      }
                      None => retain(stage, target, Missing)
                    }
                  }
                }
              }
            }
            Forward(stage, target, source, input) =>
              retain(stage, target, state(source, input))
            Finish(stage, derivation, targets, fallback) => {
              spend(targets.length())
              let inputs = []
              for target in targets {
                if state(stage, target) is Found(bound) {
                  inputs.push(@step_bounds.StepInput(bound))
                }
              }
              if inputs.length() != targets.length() {
                if !fallback && derivation.fallback_input_count is Some(n) {
                  spend(n)
                  let targets = Array::makei(n, i => {
                    @step_bounds.bound_derivation_input_at(derivation, n, i).unwrap().target
                  })
                  stack.push(Finish(stage, derivation, targets, true))
                } else {
                  retain(stage, @pipeline.Step(derivation.index), Missing)
                }
                continue
              }
              if inputs.length() == 1 &&
                @step_bounds.bound_derivation_reuse_ceiling(derivation)
                is Some(ceiling) &&
                inputs[0] is @step_bounds.StepInput(bound) &&
                @wire.value(
                  @wire.program_proof_witness(@step_bounds.checked_proof(bound)),
                ) <=
                ceiling {
                retain(stage, @pipeline.Step(derivation.index), Found(bound))
                continue
              }
              let subject = @step_bounds.subject_ref(
                derivation.pipeline,
                derivation.index,
              ).unwrap()
              spend(subject.length())
              let mut reused = None
              if stages[stage].supplied.get(subject) is Some(candidates) {
                for proof in candidates {
                  spend(1)
                  let (checked, used) = @step_bounds.check_prepared_bound(
                    derivation,
                    proof,
                    inputs,
                    remaining,
                    max_input_work=max_input_work - input_work,
                    max_operand_work=max_operand_work - operand_work,
                  )
                  spend(used.0 + used.1)
                  input_work += used.0
                  operand_work += used.1
                  match checked {
                    Ok(bound) => {
                      reused = Some(bound)
                      break
                    }
                    Err(
                      @step_bounds.InputWorkLimit
                      | @step_bounds.OperandWorkLimit
                    ) => raise RowCapacityStop(BudgetExceeded)
                    Err(_) => ()
                  }
                }
              }
              if reused is Some(bound) {
                retain(stage, @pipeline.Step(derivation.index), Found(bound))
                continue
              }
              let result = match
                @step_bounds.derive_prepared_bound(
                  derivation,
                  inputs,
                  {
                    max_input_work: max_input_work - input_work,
                    max_operand_work: max_operand_work - operand_work,
                    max_reference_work: remaining,
                    metadata: {
                      max_bytes: metadata.max_bytes - bytes,
                      max_nodes: metadata.max_nodes - nodes,
                      max_depth: metadata.max_depth,
                    },
                  },
                  max_work=remaining,
                ) {
                Ok(value) => value
                Err(issue) =>
                  raise RowCapacityStop(
                    Construction(stage, derivation.index, issue),
                  )
              }
              spend(result.work)
              bytes += result.metadata_bytes
              nodes += result.metadata_nodes
              input_work += @step_bounds.input_work(result.bound)
              operand_work += @step_bounds.operand_work(result.bound)
              add_closure(stage, result.bound)
              retain(
                stage,
                @pipeline.Step(derivation.index),
                Found(result.bound),
              )
            }
          }
        }
      }
    }
    let output = []
    for stage in 0..<stages.length() {
      spend(1)
      let entry = stages[stage]
      if entry.added.is_empty() {
        output.push(entry.material)
        continue
      }
      let claims = @host.source_claims(entry.material.sources)
      let count = @wire.claim_count(@wire.program_claim_arithmetic(claims))
      let limits = match @wire.program_claim_mixed(claims) {
        Some(mixed) => @wire.mixed_limit_count(mixed)
        None => 0
      }
      spend(count)
      spend(entry.proof_count)
      spend(limits)
      spend(entry.added.length())
      spend(entry.added.length())
      let mut references = @wire.program_claim_reference_count(claims)
      spend(references)
      for proof in entry.added {
        let witness = @wire.program_proof_witness(proof)
        let operands = match @wire.derivation(witness) {
          @wire.SourceValue => 0
          @wire.Add(_, _) => 2
          @wire.Preserve(_) | @wire.Multiply(_, _) | @wire.EnforcedCeiling(_) =>
            1
          @wire.Clamp(input, _) => if input is Some(_) { 1 } else { 0 }
          @wire.Minimum(inputs) => inputs.length()
        }
        let extra = @wire.dependencies(witness).length() +
          operands +
          @wire.program_proof_input_count(proof)
        spend(extra)
        references += extra
      }
      let sources = match
        @host.extend_program_sources(entry.material.sources, entry.added, {
          max_witnesses: count +
          entry.proof_count +
          limits +
          entry.added.length() * 2,
          max_references: references,
        }) {
        Ok(value) => value
        Err(issue) => raise RowCapacityStop(Extension(stage, issue))
      }
      output.push({ ..entry.material, sources, })
    }
    Ok({
      materials: output,
      work: max_work - remaining,
      text,
      bytes,
      nodes,
      input_work,
      operand_work,
    })
  } catch {
    RowCapacityStop(issue) => Err(issue)
  }
}
