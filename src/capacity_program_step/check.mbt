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
} derive(Eq, Debug)

///|
/// An owner-relative operation application, not a Program identity or Plan.
struct StepBound {
  pipeline : @pipeline.CheckedPipeline
  index : Int
  proof : @wire.ProgramProofClaim
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
  guard @pipeline.step_at(pipeline, index) is Some(step) else {
    return Err(MissingStep)
  }
  let witness = @wire.program_proof_witness(proof)
  guard @wire.source(witness) is @wire.Program(reference, _) &&
    reference == subject_ref(pipeline, index).unwrap() else {
    return Err(SubjectMismatch)
  }
  if @wire.program_proof_form(proof) != @wire.DerivedInputs ||
    @wire.program_proof_input_count(proof) != 0 {
    return Err(UnsupportedProofForm)
  }
  guard step.operation is @pipeline.Unary(operation) else {
    return Err(UnsupportedOperation)
  }
  let (law, count, clamp) = if @relation.operation(operation) == @relation.Group &&
    @relation.row_count_rule(operation) is @relation.OneRow {
    ("actql.bound.global-group", 1L, false)
  } else {
    let (law, value) = match @relation.row_operation(operation) {
      Some(@relation.Take(count~, ..)) => ("actql.bound.take", count)
      Some(@relation.TopK(count~, ..)) => ("actql.bound.top-k", count)
      Some(@relation.TopKBy(partition~, count~, ..)) if partition.is_empty() =>
        ("actql.bound.top-k", count)
      _ => return Err(UnsupportedOperation)
    }
    guard value is @relation.Literal(n) else { return Err(UnresolvedCount) }
    (law, n, true)
  }
  if @law.name(@wire.law(witness)) != law ||
    @wire.role(witness) != @arithmetic.ProvenUpperBound ||
    @wire.unit(witness) != @arithmetic.Rows {
    return Err(LawMismatch)
  }
  if @wire.value(witness) != count {
    return Err(ValueMismatch)
  }
  match @wire.derivation(witness) {
    @wire.SourceValue if !clamp => ()
    @wire.Clamp(None, maximum) if clamp && maximum == count => ()
    _ => return Err(InvalidDerivation)
  }
  Ok({ pipeline, index, proof, })
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
