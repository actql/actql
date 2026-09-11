///|
pub(all) enum Issue {
  MissingStep
  SubjectMismatch
  UnsupportedProofForm
  UnsupportedOperation
  UnresolvedCount
  LawMismatch
  ValueMismatch
  InvalidDerivation
  InputCountMismatch
  InputOwnerMismatch(Int)
  InputTargetMismatch(Int)
  InputWitnessMismatch(Int)
  BoundOverflow
  InvalidInputWorkLimit
  InputWorkLimit
  MissingInputProducer(Int)
  InvalidBindingLimits
  BindingOwnerMismatch
  BindingWorkLimit
  BindingTextLimit
  InvalidBoundCount
} derive(Eq, Debug)

///|
/// An owner-relative operation application, not a Program identity or Plan.
struct StepBound {
  pipeline : @pipeline.CheckedPipeline
  index : Int
  proof : @wire.ProgramProofClaim
  inputs : Array[StepBound]
  input_work : Int
  bindings : CountBindings?
}

///|
/// Internal subject spelling, scoped by the retained checked pipeline owner.
/// Not an authored alias, source pointer, semantic CID or external compiler ID.
pub fn subject_ref(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
) -> String? {
  @pipeline.step_at(pipeline, index).map(_ => {
    "checked-step:" + index.to_string()
  })
}

///|
/// Check input-independent global-group and literal selection upper bounds.
/// Ordered data inputs and their unresolved validations remain on the pipeline.
pub fn check(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  proof : @wire.ProgramProofClaim,
) -> Result[StepBound, Issue] {
  check_with_inputs(pipeline, index, proof, [])
}

///|
priv enum Rule {
  One
  Preserve
  Clamp(Int64)
  Sum
  Multiply(Int64)
}

///|
fn operation_rule(
  step : @pipeline.CheckedStep,
  bindings : CountBindings?,
) -> Result[(String, Rule), Issue] {
  if step.operation is @pipeline.Append(..) {
    return Ok(("actql.bound.append", Sum))
  }
  if step.operation is @pipeline.AsOfJoin(..) {
    return Ok(("actql.bound.asof-left", Preserve))
  }
  guard step.operation is @pipeline.Unary(operation) else {
    return Err(UnsupportedOperation)
  }
  if @relation.operation(operation) == @relation.Group &&
    @relation.row_count_rule(operation) is @relation.OneRow {
    return Ok(("actql.bound.global-group", One))
  }
  match (@relation.operation(operation), @relation.row_count_rule(operation)) {
    (@relation.Unpivot, @relation.Repeat(n)) =>
      return Ok(("actql.bound.unpivot", Multiply(n)))
    (@relation.Unnest, @relation.Expand(Some(n))) =>
      return Ok(("actql.bound.unnest-array-items", Multiply(n)))
    (@relation.Unnest, _) => return Err(UnresolvedCount)
    _ => ()
  }
  let (law, value) = match @relation.row_operation(operation) {
    Some(@relation.Take(count~, ..)) => ("actql.bound.take", count)
    Some(@relation.TopK(count~, ..)) => ("actql.bound.top-k", count)
    Some(@relation.TopKBy(partition~, count~, ..)) if partition.is_empty() =>
      ("actql.bound.top-k", count)
    _ => return Err(UnsupportedOperation)
  }
  let n = match resolve_count(value, bindings) {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  Ok((law, Clamp(n)))
}

///|
/// Inputs are verified applications in actual data-input order, not CID order.
/// Producer-input traversal requires an explicit cumulative work allowance.
/// Imported external facts and Program identity require their separate owners.
pub fn check_with_inputs(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  proof : @wire.ProgramProofClaim,
  inputs : Array[StepBound],
  max_input_work? : Int = 0,
  bindings? : CountBindings? = None,
) -> Result[StepBound, Issue] {
  if max_input_work < 0 {
    return Err(InvalidInputWorkLimit)
  }
  if bindings is Some(bound) && !physical_equal(bound.pipeline, pipeline) {
    return Err(BindingOwnerMismatch)
  }
  guard @pipeline.step_at(pipeline, index) is Some(step) else {
    return Err(MissingStep)
  }
  let witness = @wire.program_proof_witness(proof)
  guard @wire.source(witness) is @wire.Program(reference, _) &&
    reference == subject_ref(pipeline, index).unwrap() else {
    return Err(SubjectMismatch)
  }
  if @wire.program_proof_form(proof) != @wire.DerivedInputs {
    return Err(UnsupportedProofForm)
  }
  let (law, rule) = match operation_rule(step, bindings) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let n = inputs.length()
  let valid_count = match rule {
    One => n == 0
    Preserve => n == 1
    Clamp(_) => n <= 1
    Sum => n == 2
    Multiply(_) => n == 1
  }
  if !valid_count || @wire.program_proof_input_count(proof) != n {
    return Err(InputCountMismatch)
  }
  let edges = @pipeline.input_occurrences(step)
  let ids : Array[String] = []
  let mut input_work = 0
  for i in 0..<n {
    let mut owner = pipeline
    let mut target = edges[i].target
    while target is @pipeline.Input(input_index) {
      if input_work >= max_input_work {
        return Err(InputWorkLimit)
      }
      input_work = input_work + 1
      guard @pipeline.input_producer(owner, input_index) is Some(producer) else {
        return Err(MissingInputProducer(i))
      }
      owner = @pipeline.producer_pipeline(producer)
      target = @pipeline.producer_target(producer)
    }
    if !physical_equal(inputs[i].pipeline, owner) {
      return Err(InputOwnerMismatch(i))
    }
    if target != @pipeline.Step(inputs[i].index) {
      return Err(InputTargetMismatch(i))
    }
    ids.push(@wire.cid(@wire.program_proof_witness(inputs[i].proof)))
  }
  // Proof arrays sort capacity operands but retain repetitions. Derivations
  // below must still match their actual left/right data roles.
  for i in 0..<n {
    let expected = if n == 2 && ids[0] > ids[1] { ids[1 - i] } else { ids[i] }
    if @wire.program_proof_input_at(proof, i) != Some(expected) {
      return Err(InputWitnessMismatch(i))
    }
  }
  if @law.name(@wire.law(witness)) != law ||
    @wire.role(witness) != @arithmetic.ProvenUpperBound ||
    @wire.unit(witness) != @arithmetic.Rows {
    return Err(LawMismatch)
  }
  let input_value = fn(i) {
    @numeric.read(@wire.value(@wire.program_proof_witness(inputs[i].proof))).unwrap()
  }
  let count = match rule {
    One => 1L
    Preserve => @numeric.value(input_value(0))
    Clamp(maximum) =>
      @numeric.value(
        @numeric.clamp(
          if n == 0 {
            None
          } else {
            Some(input_value(0))
          },
          @numeric.read(maximum).unwrap(),
        ),
      )
    Sum =>
      match @numeric.add(input_value(0), input_value(1)) {
        Ok(v) => @numeric.value(v)
        Err(_) => return Err(BoundOverflow)
      }
    Multiply(factor) =>
      match @numeric.multiply(input_value(0), @numeric.read(factor).unwrap()) {
        Ok(v) => @numeric.value(v)
        Err(_) => return Err(BoundOverflow)
      }
  }
  if @wire.value(witness) != count {
    return Err(ValueMismatch)
  }
  match (rule, @wire.derivation(witness)) {
    (One, @wire.SourceValue) => ()
    (Preserve, @wire.Preserve(input)) if input == ids[0] => ()
    (Clamp(expected), @wire.Clamp(input, maximum)) if maximum == expected &&
      input == ids.get(0) => ()
    (Sum, @wire.Add(left, right)) if left == ids[0] && right == ids[1] => ()
    (Multiply(expected), @wire.Multiply(input, factor)) if factor == expected &&
      input == ids[0] => ()
    _ => return Err(InvalidDerivation)
  }
  Ok({ pipeline, index, proof, inputs: inputs.copy(), input_work, bindings, })
}

///|
pub fn checked_pipeline(v : StepBound) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn checked_step(v : StepBound) -> Int {
  v.index
}

///|
pub fn checked_proof(v : StepBound) -> @wire.ProgramProofClaim {
  v.proof
}

///|
pub fn input_count(v : StepBound) -> Int {
  v.inputs.length()
}

///|
pub fn input_at(v : StepBound, index : Int) -> StepBound? {
  v.inputs.get(index)
}

///|
/// Producer-input links visited, cumulatively across repeated operands.
pub fn input_work(v : StepBound) -> Int {
  v.input_work
}

///|
pub fn checked_bindings(v : StepBound) -> CountBindings? {
  v.bindings
}
