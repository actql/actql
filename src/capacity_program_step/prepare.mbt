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
/// this exact pipeline and claim owner. Producer collections retain already
/// checked external operation applications, selected by actual input edges.
/// Other external and enforced-proof applications require separate entrances.
/// The work cap covers orchestration and collection. Input-link traversal and
/// operand passes have separate cumulative caps, as on individual applications.
/// A subject spelling alone never binds a producer. Inherited applications
/// retain their original owner; the enclosing closure must admit that exact
/// collection and its Parameter/policy correspondence.
pub fn prepare_derived_applications(
  pipeline : @pipeline.CheckedPipeline,
  claims : @wire.ProgramClaims,
  limits : PreparationLimits,
  bindings? : CountBindings? = None,
  graph_inputs? : @graph_input.GraphInputs? = None,
  sequences? : @sequence.Applications? = None,
  producers? : Array[Applications] = [],
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
  let inherited : Map[String, Array[BoundInput]] = Map([])
  for producer in producers {
    if work == limits.max_work {
      return Err(WorkLimit)
    }
    work += 1
    let n = @wire.claim_count(@wire.program_claim_arithmetic(producer.claims))
    if n > limits.max_work - work {
      return Err(WorkLimit)
    }
    work += n
    for claim in 0..<n {
      if application_at(producer, claim) is Some(bound) {
        let cid = @wire.cid(@wire.program_proof_witness(bound.proof))
        match inherited.get(cid) {
          Some(values) => values.push(StepInput(bound))
          None => inherited[cid] = [StepInput(bound)]
        }
      }
    }
  }
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
          if @wire.source(@wire.program_proof_witness(proof))
            is @wire.Program(reference, _) &&
            !subjects.contains(reference) {
            let cid = @wire.cid(@wire.program_proof_witness(proof))
            guard inherited.get(cid) is Some([StepInput(bound), ..]) else {
              return Err(UnknownSubject(index))
            }
            applications[index] = Some(bound)
            states[index] = 2
            ready.push(bound)
            continue
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
              producers: [],
              input_usage: 0,
              operand_usage: 0,
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
          let mut missing = None
          for input in 0..<n {
            let cid = @wire.program_proof_input_at(proof, input).unwrap()
            if !(@wire.claim_index(arithmetic, cid) is Some(child) &&
              @wire.program_claim_proof_at(claims, child) is Some(_)) &&
              !external.contains(cid) {
              missing = Some(input)
              break
            }
          }
          if missing is Some(input) {
            let cid = @wire.cid(@wire.program_proof_witness(proof))
            guard inherited.get(cid) is Some([StepInput(bound), ..]) else {
              return Err(MissingDependency(index, input))
            }
            // Local source ordinals can coincide across pipelines. This exact
            // producer application already owns its foreign Graph premises;
            // do not reconstruct those premises in the consumer's input scope.
            applications[index] = Some(bound)
            states[index] = 2
            ready.push(bound)
            continue
          }
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
          let candidates : Array[Array[BoundInput]] = []
          for input in 0..<n {
            let cid = @wire.program_proof_input_at(proof, input).unwrap()
            let choices : Array[BoundInput] = []
            if @wire.claim_index(arithmetic, cid) is Some(child) &&
              applications[child] is Some(value) {
              choices.push(StepInput(value))
            } else if external.get(cid) is Some(value) {
              choices.push(value)
            } else {
              return Err(MissingDependency(index, input))
            }
            if inherited.get(cid) is Some(values) {
              if values.length() > limits.max_work - work {
                return Err(WorkLimit)
              }
              work += values.length()
              for value in values {
                choices.push(value)
              }
            }
            candidates.push(choices)
          }
          let selected = select_prepared_inputs(
            pipeline,
            step,
            proof,
            candidates,
            bindings,
            limits.max_work - work,
            limits.max_input_work - input_work,
          )
          let checked_usage = [0, 0]
          let checked = match selected {
            Ok(selected) => {
              work += selected.work
              input_work += selected.input_work
              check_application(
                pipeline,
                step,
                proof,
                selected.inputs.length(),
                i => selected.inputs[i],
                limits.max_input_work - input_work,
                limits.max_operand_work - operand_work,
                bindings,
                false,
                usage=Some(checked_usage),
              )
            }
            Err((e, used_work, used_input)) => {
              work += used_work
              input_work += used_input
              Err(e)
            }
          }
          input_work += checked_usage[0]
          operand_work += checked_usage[1]
          let value = match checked {
            Ok(v) => v
            Err(InputWorkLimit) =>
              return Err(Application(index, InputWorkLimit))
            Err(OperandWorkLimit) =>
              return Err(Application(index, OperandWorkLimit))
            Err(e) => {
              // A body may belong to an already checked producer rather than
              // this visit. Retain that exact application; the closure must
              // still register its pipeline and Parameter owner.
              let cid = @wire.cid(@wire.program_proof_witness(proof))
              match inherited.get(cid) {
                Some([StepInput(bound), ..]) => bound
                _ => return Err(Application(index, e))
              }
            }
          }
          applications[index] = Some(value)
          states[index] = 2
          ready.push(value)
        }
      }
    }
  }
  match
    check_applications(
      claims,
      ready,
      max_work=limits.max_work - work,
      producers~,
    ) {
    Ok(v) =>
      Ok({
        ..v,
        work: v.work + work,
        input_usage: input_work,
        operand_usage: operand_work,
      })
    Err(e) => Err(Collection(e))
  }
}
