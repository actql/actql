///|
pub(all) enum OutputEnforcement {
  JoinEnforcement(JoinLimit)
  ComponentsEnforcement(ComponentsLimits)
  TraversalEnforcement(TraversalLimits)
}

///|
pub(all) enum ResolutionInput {
  ExistingInput(BoundInput)
  PriorApplication(Int)
}

///|
pub(all) enum ResolutionRequest {
  ExistingApplication(StepBound)
  DeriveApplication(
    Int,
    @wire.ProgramProofClaim,
    Array[ResolutionInput],
    CountBindings?
  )
  ComponentsApplication(Int, @wire.ProgramProofClaim, Int, Int)
  JoinApplication(Int, @wire.ProgramProofClaim, Int)
  TraversalApplication(Int, @wire.ProgramProofClaim, Int, Int)
}

///|
pub(all) enum ResolutionIssue {
  InvalidLimits
  WorkLimit
  InvalidDependency(Int, Int)
  ForeignApplication(Int)
  DuplicateApplication(Int)
  Step(Int, Issue)
  Components(Int, ComponentsLimitIssue)
  Join(Int, JoinLimitIssue)
  Traversal(Int, TraversalLimitIssue)
  InvalidOutputProof(Int)
  Collection(ApplicationIssue)
}

///|
struct ResolvedApplications {
  program : Applications
  outputs : Array[StepBound]
  work : Int
}

///|
/// Resolves a dependency-ordered construction plan without publishing a partial
/// application table. Every ordinary claim is required before returning. This
/// is not the enclosing Program identity or the all-obligation compiler result.
pub fn resolve_applications(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  policy : @policy.Policy,
  requests : Array[ResolutionRequest],
  max_work~ : Int,
) -> Result[ResolvedApplications, ResolutionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let claims = @host.source_claims(sources)
  let arithmetic = @wire.program_claim_arithmetic(claims)
  let n = @wire.claim_count(arithmetic)
  if n > max_work || requests.length() > max_work - n {
    return Err(WorkLimit)
  }
  let mut work = n + requests.length()
  // Mutation is private to this constructor. No reference escapes until the
  // complete table and every early limit application have been revalidated.
  let table : Applications = {
    claims,
    entries: Array::make(n, None),
    remaining: 0,
    work: 0,
  }
  let resolved : Array[StepBound] = []
  for position, request in requests {
    let application = match request {
      ExistingApplication(app) => app
      DeriveApplication(step, proof, operands, bindings) => {
        if operands.length() > max_work - work {
          return Err(WorkLimit)
        }
        work += operands.length()
        let inputs : Array[BoundInput] = []
        for j, operand in operands {
          match operand {
            ExistingInput(input) => inputs.push(input)
            PriorApplication(index) => {
              guard resolved.get(index) is Some(app) else {
                return Err(InvalidDependency(position, j))
              }
              inputs.push(StepInput(app))
            }
          }
        }
        let app = match
          check_with_sources(
            pipeline,
            step,
            proof,
            inputs,
            bindings~,
            max_input_work=max_work - work,
            max_operand_work=max_work - work,
          ) {
          Ok(app) => app
          Err(e) => return Err(Step(position, e))
        }
        if app.input_work > max_work - work ||
          app.operand_work > max_work - work - app.input_work {
          return Err(WorkLimit)
        }
        work += app.input_work + app.operand_work
        app
      }
      JoinApplication(step, proof, index) => {
        let limit = match
          check_join_limit(
            pipeline,
            step,
            sources,
            table,
            policy,
            index,
            max_work=max_work - work,
          ) {
          Ok(v) => v
          Err(e) => return Err(Join(position, e))
        }
        work += limit.work
        let app = match
          resolved_output(
            pipeline,
            step,
            proof,
            JoinEnforcement(limit),
            table,
            max_work - work,
          ) {
          Ok(v) => v
          Err(OutputWorkLimit) => return Err(WorkLimit)
          Err(InvalidOutput) => return Err(InvalidOutputProof(position))
        }
        work += app.operand_work
        app
      }
      ComponentsApplication(step, proof, nodes, rows) => {
        let limit = match
          check_components_limits(
            pipeline,
            step,
            sources,
            table,
            policy,
            nodes,
            rows,
            max_work=max_work - work,
          ) {
          Ok(v) => v
          Err(e) => return Err(Components(position, e))
        }
        work += limit.work
        let app = match
          resolved_output(
            pipeline,
            step,
            proof,
            ComponentsEnforcement(limit),
            table,
            max_work - work,
          ) {
          Ok(v) => v
          Err(OutputWorkLimit) => return Err(WorkLimit)
          Err(InvalidOutput) => return Err(InvalidOutputProof(position))
        }
        work += app.operand_work
        app
      }
      TraversalApplication(step, proof, paths, rows) => {
        let limit = match
          check_traversal_limits(
            pipeline,
            step,
            sources,
            table,
            policy,
            paths,
            rows,
            max_work=max_work - work,
          ) {
          Ok(v) => v
          Err(e) => return Err(Traversal(position, e))
        }
        work += limit.work
        let app = match
          resolved_output(
            pipeline,
            step,
            proof,
            TraversalEnforcement(limit),
            table,
            max_work - work,
          ) {
          Ok(v) => v
          Err(OutputWorkLimit) => return Err(WorkLimit)
          Err(InvalidOutput) => return Err(InvalidOutputProof(position))
        }
        work += app.operand_work
        app
      }
    }
    let id = @wire.cid(@wire.program_proof_witness(application.proof))
    guard @wire.claim_index(arithmetic, id) is Some(index) &&
      @wire.program_claim_proof_at(claims, index) is Some(_) else {
      return Err(ForeignApplication(position))
    }
    if table.entries[index] is Some(_) {
      return Err(DuplicateApplication(position))
    }
    table.entries[index] = Some(application)
    resolved.push(application)
  }
  let checked = match
    check_applications(claims, resolved, max_work=max_work - work) {
    Ok(v) => v
    Err(e) => return Err(Collection(e))
  }
  work += checked.work
  // A later registered candidate must not be omitted from an earlier minimum.
  for i, app in resolved {
    if work >= max_work {
      return Err(WorkLimit)
    }
    work += 1
    match app.enforcement {
      None => ()
      Some(JoinEnforcement(v)) => {
        let verified = match
          check_join_limit(
            v.pipeline,
            v.step,
            sources,
            table,
            policy,
            v.index,
            max_work=max_work - work,
          ) {
          Ok(v) => v
          Err(e) => return Err(Join(i, e))
        }
        work += verified.work
      }
      Some(ComponentsEnforcement(v)) => {
        let verified = match
          check_components_limits(
            v.pipeline,
            v.step,
            sources,
            table,
            policy,
            v.nodes_index,
            v.rows_index,
            max_work=max_work - work,
          ) {
          Ok(v) => v
          Err(e) => return Err(Components(i, e))
        }
        work += verified.work
      }
      Some(TraversalEnforcement(v)) => {
        let verified = match
          check_traversal_limits(
            v.pipeline,
            v.step,
            sources,
            table,
            policy,
            v.paths_index,
            v.rows_index,
            max_work=max_work - work,
          ) {
          Ok(v) => v
          Err(e) => return Err(Traversal(i, e))
        }
        work += verified.work
      }
    }
  }
  table.remaining = checked.remaining
  table.work = checked.work
  Ok({ program: table, outputs: resolved, work, })
}

///|
priv enum OutputIssue {
  OutputWorkLimit
  InvalidOutput
}

///|
fn resolved_output(
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  proof : @wire.ProgramProofClaim,
  enforcement : OutputEnforcement,
  program : Applications,
  max_work : Int,
) -> Result[StepBound, OutputIssue] {
  let (limit, law) = match enforcement {
    JoinEnforcement(v) => (v.limit, "actql.bound.join-resolved-output")
    ComponentsEnforcement(v) => (v.rows, "actql.bound.components-output")
    TraversalEnforcement(v) => (v.rows, "actql.bound.traverse-output")
  }
  let witness = @wire.program_proof_witness(proof)
  let minimum = @wire.limit_minimum(limit)
  let count = @arithmetic.minimum_candidate_count(minimum)
  if count > max_work / 3 {
    return Err(OutputWorkLimit)
  }
  if @wire.program_proof_form(proof) != @wire.DerivedInputs ||
    !(@wire.derivation(witness) is @wire.SourceValue) ||
    @wire.role(witness) != @arithmetic.ProvenUpperBound ||
    @wire.unit(witness) != @arithmetic.Rows ||
    @wire.value(witness) != @arithmetic.minimum_value(minimum) ||
    @law.name(@wire.law(witness)) != law ||
    @wire.program_proof_input_count(proof) != count {
    return Err(InvalidOutput)
  }
  guard @wire.source(witness) is @wire.Program(reference, _) &&
    reference == "checked-step:" + step.to_string() else {
    return Err(InvalidOutput)
  }
  let arithmetic = @wire.program_claim_arithmetic(program.claims)
  let inputs : Array[BoundInput] = []
  let remaining : Map[String, Int] = Map([])
  for i in 0..<count {
    let candidate = @arithmetic.minimum_candidate_at(minimum, i).unwrap()
    let wire = @wire.claim_at(arithmetic, candidate.node).unwrap()
    let id = @wire.cid(wire)
    remaining[id] = remaining.get(id).unwrap_or(0) + 1
    if program.entries[candidate.node] is Some(app) {
      inputs.push(StepInput(app))
    }
  }
  for i in 0..<count {
    let id = @wire.program_proof_input_at(proof, i).unwrap()
    let times = remaining.get(id).unwrap_or(0)
    if times == 0 {
      return Err(InvalidOutput)
    }
    remaining[id] = times - 1
  }
  Ok({
    pipeline,
    index: step,
    proof,
    inputs,
    input_work: 0,
    operand_work: count * 3,
    bindings: None,
    join_evidence: None,
    enforcement: Some(enforcement),
  })
}

///|
pub fn resolved_program(v : ResolvedApplications) -> Applications {
  v.program
}

///|
pub fn resolved_application_at(
  v : ResolvedApplications,
  index : Int,
) -> StepBound? {
  v.outputs.get(index)
}

///|
pub fn resolution_work(v : ResolvedApplications) -> Int {
  v.work
}

///|
pub fn checked_enforcement(v : StepBound) -> OutputEnforcement? {
  v.enforcement
}
