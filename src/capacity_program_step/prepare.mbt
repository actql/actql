///|
pub(all) struct PreparationLimits {
  max_work : Int
  max_input_work : Int
  max_operand_work : Int
} derive(Eq, Debug)

///|
pub(all) enum PreparationIssue {
  InvalidLimits
  WorkLimit
  ForeignBindings
  ForeignGraphInputs
  ForeignSequenceApplications
  MissingSequenceApplication(Int)
  InvalidSequenceProof(Int)
  UnknownSubject(Int)
  UnsupportedProof(Int)
  MissingDependency(Int, Int)
  CyclicDependency(Int)
  Application(Int, Issue)
  Collection(ApplicationIssue)
} derive(Eq, Debug)

///|
priv enum PreparationFrame {
  Visit(Int)
  Finish(Int)
}

///|
/// Construct ordinary derived applications from admitted claims, in dependency
/// order, without caller-supplied StepBounds. Optional Graph inputs must retain
/// this exact pipeline and claim owner. Other external and enforced-proof
/// applications require their separate entrances; they are never fabricated.
/// The work cap covers orchestration and collection. Input-link traversal and
/// operand passes have separate cumulative caps, as on individual applications.
/// Internal subject refs are resolved only within this exact pipeline owner;
/// the enclosing Program identity and cross-producer closure remain required.
pub fn prepare_derived_applications(
  pipeline : @pipeline.CheckedPipeline,
  claims : @wire.ProgramClaims,
  limits : PreparationLimits,
  bindings? : CountBindings? = None,
  graph_inputs? : @graph_input.GraphInputs? = None,
  sequences? : @sequence.Applications? = None,
) -> Result[Applications, PreparationIssue] {
  if limits.max_work < 0 ||
    limits.max_input_work < 0 ||
    limits.max_operand_work < 0 {
    return Err(InvalidLimits)
  }
  if bindings is Some(v) && !physical_equal(v.pipeline, pipeline) {
    return Err(ForeignBindings)
  }
  if graph_inputs is Some(v) &&
    (
      !physical_equal(@graph_input.checked_pipeline(v), pipeline) ||
      !physical_equal(
        @host.source_claims(@graph_input.checked_sources(v)),
        claims,
      )
    ) {
    return Err(ForeignGraphInputs)
  }
  let arithmetic = @wire.program_claim_arithmetic(claims)
  if sequences is Some(v) &&
    (
      !physical_equal(@sequence.application_pipeline(v), pipeline) ||
      !physical_equal(
        @host.source_claims(@sequence.application_sources(v)),
        claims,
      )
    ) {
    return Err(ForeignSequenceApplications)
  }
  let count = @wire.claim_count(arithmetic)
  let steps = @pipeline.step_count(pipeline)
  if count > limits.max_work || steps > limits.max_work - count {
    return Err(WorkLimit)
  }
  let mut work = count + steps
  let external : Map[String, BoundInput] = Map([])
  if graph_inputs is Some(graph) {
    let n = @pipeline.input_count(pipeline)
    if n > (limits.max_work - work) / 2 {
      return Err(WorkLimit)
    }
    work += n * 2
    for input in 0..<n {
      for measure in [@graph_input.Nodes, @graph_input.Edges] {
        if @graph_input.input_bound(graph, input, measure) is Some(bound) {
          let cid = @wire.cid(@graph_input.bound_witness(bound))
          if external.contains(cid) {
            return Err(ForeignGraphInputs)
          }
          external[cid] = GraphInput(bound)
        }
      }
    }
  }
  let subjects : Map[String, Int] = Map([])
  for step in 0..<steps {
    subjects[subject_ref(pipeline, step).unwrap()] = step
  }
  let states = Array::make(count, 0)
  let applications : Array[StepBound?] = Array::make(count, None)
  let ready : Array[StepBound] = []
  let mut input_work = 0
  let mut operand_work = 0
  for root in 0..<count {
    if work == limits.max_work {
      return Err(WorkLimit)
    }
    work += 1
    if @wire.program_claim_proof_at(claims, root) is None || states[root] == 2 {
      continue
    }
    let stack : Array[PreparationFrame] = [Visit(root)]
    while stack.pop() is Some(frame) {
      if work == limits.max_work {
        return Err(WorkLimit)
      }
      work += 1
      match frame {
        Visit(index) => {
          if states[index] == 2 {
            continue
          }
          if states[index] == 1 {
            return Err(CyclicDependency(index))
          }
          let proof = @wire.program_claim_proof_at(claims, index).unwrap()
          if @wire.program_proof_form(proof) != @wire.DerivedInputs {
            return Err(UnsupportedProof(index))
          }
          if @law.name(@wire.law(@wire.program_proof_witness(proof))) ==
            "actql.bound.sequence-output" {
            guard @wire.source(@wire.program_proof_witness(proof))
              is @wire.Program(reference, _) &&
              subjects.get(reference) is Some(step) else {
              return Err(UnknownSubject(index))
            }
            guard sequences is Some(sequence) &&
              @sequence.application_at(sequence, step) is Some(selected) else {
              return Err(MissingSequenceApplication(index))
            }
            let table : Applications = {
              claims,
              entries: applications,
              remaining: 0,
              work: 0,
            }
            let bound = match
              resolved_output(
                pipeline,
                step,
                proof,
                SequenceEnforcement(selected),
                table,
                limits.max_operand_work - operand_work,
              ) {
              Ok(v) => v
              Err(OutputWorkLimit) =>
                return Err(Application(index, OperandWorkLimit))
              Err(InvalidOutput) => return Err(InvalidSequenceProof(index))
            }
            operand_work += bound.operand_work
            applications[index] = Some(bound)
            states[index] = 2
            ready.push(bound)
            continue
          }
          let n = @wire.program_proof_input_count(proof)
          if n > limits.max_work - work {
            return Err(WorkLimit)
          }
          work += n
          states[index] = 1
          stack.push(Finish(index))
          // Reverse scheduling preserves authored input order, including repeats.
          for offset in 0..<n {
            let input = n - 1 - offset
            let cid = @wire.program_proof_input_at(proof, input).unwrap()
            if @wire.claim_index(arithmetic, cid) is Some(child) &&
              @wire.program_claim_proof_at(claims, child) is Some(_) {
              stack.push(Visit(child))
            } else if !external.contains(cid) {
              return Err(MissingDependency(index, input))
            }
          }
        }
        Finish(index) => {
          let proof = @wire.program_claim_proof_at(claims, index).unwrap()
          guard @wire.source(@wire.program_proof_witness(proof))
            is @wire.Program(reference, _) &&
            subjects.get(reference) is Some(step) else {
            return Err(UnknownSubject(index))
          }
          let n = @wire.program_proof_input_count(proof)
          if n > limits.max_work - work {
            return Err(WorkLimit)
          }
          work += n
          let inputs : Array[BoundInput] = []
          for input in 0..<n {
            let cid = @wire.program_proof_input_at(proof, input).unwrap()
            if @wire.claim_index(arithmetic, cid) is Some(child) &&
              applications[child] is Some(value) {
              inputs.push(StepInput(value))
            } else if external.get(cid) is Some(value) {
              inputs.push(value)
            } else {
              return Err(MissingDependency(index, input))
            }
          }
          let value = match
            check_with_sources(
              pipeline,
              step,
              proof,
              inputs,
              max_input_work=limits.max_input_work - input_work,
              max_operand_work=limits.max_operand_work - operand_work,
              bindings~,
            ) {
            Ok(v) => v
            Err(e) => return Err(Application(index, e))
          }
          input_work += value.input_work
          operand_work += value.operand_work
          applications[index] = Some(value)
          states[index] = 2
          ready.push(value)
        }
      }
    }
  }
  match check_applications(claims, ready, max_work=limits.max_work - work) {
    Ok(v) => Ok({ ..v, work: v.work + work, })
    Err(e) => Err(Collection(e))
  }
}
