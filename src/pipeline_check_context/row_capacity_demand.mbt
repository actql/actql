///|
pub enum RowCapacityIssue {
  BudgetExceeded
  InvalidGraph
  Bindings(Int, @step_bounds.Issue)
  Construction(Int, Int, @step_bounds.DeriveBoundIssue)
  Extension(Int, @wire.ProgramExtensionIssue)
  GraphInputs(Int, @graph_input.Issue)
  Dependencies(Int, @wire.ProgramDependencyIssue)
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
  Found(@step_bounds.BoundInput)
}

///|
priv struct RowCapacityStage {
  pipeline : @pipeline.CheckedPipeline
  bindings : @step_bounds.CountBindings?
  material : CapacityMaterial
  roots : Array[@pipeline.Target]
  quantities : Array[CapacityQuantityStates]
  known : Map[String, Bool]
  supplied : Map[String, Array[@wire.ProgramProofClaim]]
  added : Array[@wire.ProgramProofClaim]
  proof_count : Int
  mut graph_inputs : @graph_input.GraphInputs?
  dependencies : Array[@host.HostSources]
  dependency_stages : Map[Int, Bool]
  applications : Map[String, Array[@step_bounds.StepBound]]
}

///|
priv struct CapacityQuantityStates {
  unit : @derivation.BoundUnit
  steps : Array[RowBoundState]
  inputs : Array[RowBoundState]
}

///|
priv enum RowCapacityFrame {
  Visit(Int, @pipeline.Target, @derivation.BoundUnit)
  Forward(Int, @pipeline.Target, Int, @pipeline.Target, @derivation.BoundUnit)
  Finish(
    Int,
    @step_bounds.BoundDerivation,
    Array[@step_bounds.BoundOperand],
    Bool
  )
}

///|
priv struct RowCapacityResult {
  materials : Array[CapacityMaterial]
  applications : Array[Array[@step_bounds.StepBound]]
  work : Int
  text : Int
  bytes : Int
  nodes : Int
  input_work : Int
  operand_work : Int
}

///|
// Demand follows Result targets and collection-envelope inputs through the existing
// non-expanding transfer rules and quantity-typed operand plans. Unavailable premises
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
  sourceviews : @sourceviews.PipelineInputs?,
  selected_policy : @policy.Policy,
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
  fn quantity(
    stage : Int,
    unit : @derivation.BoundUnit,
  ) -> CapacityQuantityStates raise RowCapacityStop {
    for states in stages[stage].quantities {
      spend(1)
      if states.unit == unit {
        return states
      }
    }
    let pipeline = stages[stage].pipeline
    let steps = @pipeline.step_count(pipeline)
    let inputs = @pipeline.input_count(pipeline)
    spend(steps)
    spend(inputs)
    let states = {
      unit,
      steps: Array::make(steps, Unvisited),
      inputs: Array::make(inputs, Unvisited),
    }
    stages[stage].quantities.push(states)
    states
  }
  fn state(
    stage : Int,
    target : @pipeline.Target,
    unit : @derivation.BoundUnit,
  ) -> RowBoundState raise RowCapacityStop {
    let states = quantity(stage, unit)
    match target {
      @pipeline.Step(i) => states.steps[i]
      @pipeline.Input(i) => states.inputs[i]
    }
  }
  fn retain(
    stage : Int,
    target : @pipeline.Target,
    unit : @derivation.BoundUnit,
    value : RowBoundState,
  ) -> Unit raise RowCapacityStop {
    let states = quantity(stage, unit)
    match target {
      @pipeline.Step(i) => states.steps[i] = value
      @pipeline.Input(i) => states.inputs[i] = value
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
      let bucket = match stages[stage].applications.get(id) {
        Some(bucket) => bucket
        None => {
          let bucket = []
          stages[stage].applications[id] = bucket
          bucket
        }
      }
      let mut seen = false
      for prior in bucket {
        spend(1)
        if physical_equal(prior, bound) {
          seen = true
          break
        }
      }
      if seen {
        continue
      }
      bucket.push(bound)
      if !stages[stage].known.contains(id) {
        stages[stage].known[id] = true
        stages[stage].added.push(proof)
      }
      let n = @step_bounds.input_count(bound)
      spend(n)
      for i in 0..<n {
        match @step_bounds.source_at(bound, i) {
          Some(@step_bounds.StepInput(input)) => stack.push(input)
          Some(@step_bounds.GraphInput(input)) => {
            let graph = @graph_input.bound_owner(input)
            let producer = owner(@graph_input.checked_pipeline(graph))
            if !@host.same_source_origin(
                @graph_input.checked_sources(graph),
                stages[producer].material.sources,
              ) {
              raise RowCapacityStop(InvalidGraph)
            }
            if producer != stage &&
              !stages[stage].dependency_stages.contains(producer) {
              stages[stage].dependency_stages[producer] = true
              stages[stage].dependencies.push(stages[producer].material.sources)
            }
          }
          None => raise RowCapacityStop(InvalidGraph)
        }
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
      let remote_names : Map[String, Bool] = Map([])
      if sourceviews is Some(views) {
        guard @sourceviews.pipeline_input_count(views, stage) is Some(count) else {
          raise RowCapacityStop(InvalidGraph)
        }
        spend(count)
        for index in 0..<count {
          let name = @sourceviews.pipeline_input_at(views, stage, index).unwrap().0
          spend(name.length())
          if name.length() > max_text_bytes - text {
            raise RowCapacityStop(BudgetExceeded)
          }
          text += name.length()
          remote_names[name] = true
        }
      }
      spend(inputs)
      let remote_inputs = Array::make(inputs, false)
      for index in 0..<inputs {
        let name = @pipeline.input_at(pipeline, index).unwrap().0
        spend(name.length())
        remote_inputs[index] = remote_names.contains(name)
      }
      for i in 0..<@results.port_count(ports) {
        roots.push(
          @results.target(
            @results.port_result(@results.port_at(ports, i).unwrap()),
          ),
        )
      }
      // A global aggregate can determine its output count without inspecting
      // its input count. Its array envelope nevertheless needs input bounds,
      // including when a different target is published. Register one demand
      // per operation, not one copy of the traversal per aggregate call.
      let selected_join_limits : Map[Int, Bool] = Map([])
      for consumer in materials[stage].consumers {
        if consumer is @capacity.Join(step~, ..) {
          selected_join_limits[step] = true
        }
      }
      for index in 0..<steps {
        spend(1)
        let step = @pipeline.step_at(pipeline, index).unwrap()
        match step.operation {
          @pipeline.Join(..)
          | @pipeline.CrossJoin(..)
          | @pipeline.IntervalJoin(..)
          | @pipeline.AsOfJoin(..) if !selected_join_limits.contains(index) => {
            // The selected output limit must include every applicable local
            // Program candidate, including for an unpublished branch.
            spend(1)
            roots.push(@pipeline.Step(index))
          }
          _ => ()
        }
        guard step.input is Some(input) else { continue }
        if step.operation is @pipeline.Join(right=@pipeline.Input(index), ..) &&
          remote_inputs[index] {
          // Same JoinRight role as source request classification. This demand
          // is not admission of the keyed request, mode or access policy.
          spend(1)
          roots.push(input)
          continue
        }
        match step.operation {
          @pipeline.AsOfJoin(right~, ..) | @pipeline.IntervalJoin(right~, ..) => {
            // Search work depends on both operands, independently of whether
            // the output count rule needs both or the output is published.
            spend(2)
            roots.push(input)
            roots.push(right)
            continue
          }
          _ => ()
        }
        if step.operation is @pipeline.Window(_) {
          // Membership envelopes consume input counts even if no Result reads
          // the expanded output. The window-specific factor is resolved later.
          spend(1)
          roots.push(input)
          continue
        }
        if step.operation is @pipeline.Nest(right=child, ..) {
          // Child rows bound each grouped array; parent rows bound attachment
          // copies. Neither demand depends on publishing the nest output.
          spend(2)
          roots.push(input)
          roots.push(child)
          continue
        }
        let operation = match step.operation {
          @pipeline.Unary(operation) | @pipeline.WindowGroup(operation) =>
            operation
          _ => continue
        }
        let mut needed = false
        if @relation.group(operation) is Some(group) {
          for call in 0..<@relation.aggregate_count(group) {
            spend(1)
            if @relation.aggregate_function(
                @relation.aggregate_at(group, call).unwrap(),
              )
              is @relation.ArrayAgg {
              needed = true
              break
            }
          }
        } else if @relation.analytic(operation) is Some(analytic) {
          for call in 0..<@relation.analytic_call_count(analytic) {
            spend(1)
            if @relation.analytic_call_at(analytic, call).unwrap().function
              is @relation.Aggregate(aggregate) &&
              @relation.aggregate_function(aggregate) is @relation.ArrayAgg {
              needed = true
              break
            }
          }
        }
        if needed {
          spend(1)
          roots.push(input)
        }
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
        quantities: [
          {
            unit: @derivation.Rows,
            steps: Array::makei(steps, i => {
              match seeds[stage][i] {
                Some(bound) => Found(@step_bounds.StepInput(bound))
                None => Unvisited
              }
            }),
            inputs: Array::make(inputs, Unvisited),
          },
        ],
        known,
        dependencies: [],
        dependency_stages: Map([]),
        applications: Map([]),
        supplied,
        added: [],
        proof_count,
        graph_inputs: None,
      })
      for seed in seeds[stage] {
        if seed is Some(bound) {
          add_closure(stage, bound)
        }
      }
      let key = @decode.cursor_span(@pipeline.source(pipeline)).start_byte
      match owners.get(key) {
        Some(bucket) => bucket.push(stage)
        None => owners[key] = [stage]
      }
    }
    for root_stage in 0..<stages.length() {
      for root in stages[root_stage].roots {
        let stack = [Visit(root_stage, root, @derivation.Rows)]
        while !stack.is_empty() {
          spend(1)
          match stack.pop().unwrap() {
            Visit(stage, target, unit) => {
              match state(stage, target, unit) {
                Found(_) | Missing => continue
                Visiting => raise RowCapacityStop(InvalidGraph)
                Unvisited => ()
              }
              retain(stage, target, unit, Visiting)
              let pipeline = stages[stage].pipeline
              match target {
                @pipeline.Input(index) =>
                  match @pipeline.input_producer(pipeline, index) {
                    Some(producer) => {
                      let source = owner(@pipeline.producer_pipeline(producer))
                      let source_target = @pipeline.producer_target(producer)
                      stack.push(
                        Forward(stage, target, source, source_target, unit),
                      )
                      stack.push(Visit(source, source_target, unit))
                    }
                    None => {
                      let measure = match unit {
                        @derivation.Nodes => Some(@graph_input.Nodes)
                        @derivation.Edges => Some(@graph_input.Edges)
                        _ => None
                      }
                      if measure is Some(measure) &&
                        @carrier.kind(
                          @pipeline.input_at(pipeline, index).unwrap().1,
                        ) ==
                        @carrier.GraphKind {
                        let graph = match stages[stage].graph_inputs {
                          Some(graph) => graph
                          None => {
                            let graph = match
                              @graph_input.check(
                                pipeline,
                                stages[stage].material.sources,
                                selected_policy,
                                {
                                  max_work: remaining,
                                  max_name_bytes: max_text_bytes - text,
                                },
                              ) {
                              Ok(graph) => graph
                              Err(issue) =>
                                raise RowCapacityStop(GraphInputs(stage, issue))
                            }
                            let usage = @graph_input.usage(graph)
                            spend(usage.0)
                            text += usage.1
                            stages[stage].graph_inputs = Some(graph)
                            graph
                          }
                        }
                        let value = match
                          @graph_input.input_bound(graph, index, measure) {
                          Some(bound) => Found(@step_bounds.GraphInput(bound))
                          None => Missing
                        }
                        retain(stage, target, unit, value)
                      } else {
                        retain(stage, target, unit, Missing)
                      }
                    }
                  }
                @pipeline.Step(index) => {
                  let derivation = match
                    @step_bounds.prepare_bound_derivation(
                      pipeline,
                      index,
                      unit~,
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
                    for i in 0..<derivation.input_count {
                      let operand = @step_bounds.bound_derivation_input_at(
                        derivation,
                        derivation.input_count,
                        i,
                      ).unwrap()
                      targets.push(operand)
                    }
                    stack.push(Finish(stage, derivation, targets, false))
                    for i = targets.length() - 1; i >= 0; i = i - 1 {
                      stack.push(
                        Visit(stage, targets[i].target, targets[i].unit),
                      )
                    }
                  } else {
                    match
                      @step_bounds.forwarded_bound_target(pipeline, index, unit) {
                      Some(input) => {
                        stack.push(Forward(stage, target, stage, input, unit))
                        stack.push(Visit(stage, input, unit))
                      }
                      None => retain(stage, target, unit, Missing)
                    }
                  }
                }
              }
            }
            Forward(stage, target, source, input, unit) =>
              retain(stage, target, unit, state(source, input, unit))
            Finish(stage, derivation, targets, fallback) => {
              spend(targets.length())
              let inputs = []
              for target in targets {
                if state(stage, target.target, target.unit) is Found(bound) {
                  inputs.push(bound)
                }
              }
              if inputs.length() != targets.length() {
                if !fallback && derivation.fallback_input_count is Some(n) {
                  spend(n)
                  let targets = Array::makei(n, i => {
                    @step_bounds.bound_derivation_input_at(derivation, n, i).unwrap()
                  })
                  stack.push(Finish(stage, derivation, targets, true))
                } else if @step_bounds.forwarded_bound_target(
                    derivation.pipeline,
                    derivation.index,
                    derivation.unit,
                  )
                  is Some(input) {
                  // A missing construction premise does not invalidate an
                  // independently applicable non-expanding transfer. Follow
                  // that exact edge through the same metered demand walk.
                  stack.push(
                    Forward(
                      stage,
                      @pipeline.Step(derivation.index),
                      stage,
                      input,
                      derivation.unit,
                    ),
                  )
                  stack.push(Visit(stage, input, derivation.unit))
                } else {
                  retain(
                    stage,
                    @pipeline.Step(derivation.index),
                    derivation.unit,
                    Missing,
                  )
                }
                continue
              }
              if inputs.length() == 1 &&
                @step_bounds.forwarded_bound_target(
                  derivation.pipeline,
                  derivation.index,
                  derivation.unit,
                ) ==
                Some(targets[0].target) &&
                @step_bounds.bound_derivation_reuse_ceiling(derivation)
                is Some(ceiling) &&
                inputs[0] is @step_bounds.StepInput(bound) &&
                @wire.value(
                  @wire.program_proof_witness(@step_bounds.checked_proof(bound)),
                ) <=
                ceiling {
                retain(
                  stage,
                  @pipeline.Step(derivation.index),
                  derivation.unit,
                  Found(@step_bounds.StepInput(bound)),
                )
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
                      // Retain all applicable candidates. Limit resolution
                      // must not omit a second valid proof merely because the
                      // first one was sufficient to derive the numeric bound.
                      add_closure(stage, bound)
                      if reused is None {
                        reused = Some(bound)
                      }
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
                retain(
                  stage,
                  @pipeline.Step(derivation.index),
                  derivation.unit,
                  Found(@step_bounds.StepInput(bound)),
                )
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
                derivation.unit,
                Found(@step_bounds.StepInput(result.bound)),
              )
            }
          }
        }
      }
    }
    let output = []
    let applications : Array[Array[@step_bounds.StepBound]] = []
    for stage in 0..<stages.length() {
      spend(1)
      let entry = stages[stage]
      let owned : Array[@step_bounds.StepBound] = []
      for _, bucket in entry.applications {
        spend(bucket.length())
        for bound in bucket {
          if physical_equal(
              @step_bounds.checked_pipeline(bound),
              entry.pipeline,
            ) {
            owned.push(bound)
          }
        }
      }
      applications.push(owned)
      if !entry.dependencies.is_empty() {
        let (sources, used) = match
          @host.extend_source_dependencies(
            entry.material.sources,
            entry.dependencies,
            entry.added,
            { max_witnesses: remaining, max_references: remaining, },
            max_work=remaining,
          ) {
          Ok(value) => value
          Err(issue) => raise RowCapacityStop(Dependencies(stage, issue))
        }
        spend(used)
        output.push({ ..entry.material, sources, })
        continue
      }
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
        for
          extra in [
            @wire.dependency_count(witness),
            @wire.witness_operand_count(witness),
            @wire.program_proof_input_count(proof),
          ] {
          spend(extra)
          references += extra
        }
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
      applications,
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
