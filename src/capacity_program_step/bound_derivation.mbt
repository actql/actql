///|
/// A retained operation rule and its admissible operand shapes. This is a
/// request for checked premises, not an application or a capacity guarantee.
pub struct BoundDerivation {
  pipeline : @pipeline.CheckedPipeline
  index : Int
  unit : @arithmetic.BoundUnit
  input_count : Int
  fallback_input_count : Int?
  priv step : @pipeline.CheckedStep
  priv rule : Rule
  priv law : String
  priv bindings : CountBindings?
}

///|
pub struct BoundOperand {
  target : @pipeline.Target
  unit : @arithmetic.BoundUnit
  edge : Int
}

///|
/// Read the existing operation law once. A fallback is an explicitly admitted
/// alternate arity, not permission to omit arbitrary operands or their runtime
/// validations. Bound Parameters must belong to this exact pipeline.
pub fn prepare_bound_derivation(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  unit? : @arithmetic.BoundUnit = @arithmetic.Rows,
  bindings? : CountBindings? = None,
) -> Result[BoundDerivation, Issue] {
  if bindings is Some(bound) && !physical_equal(bound.pipeline, pipeline) {
    return Err(BindingOwnerMismatch)
  }
  guard @pipeline.step_at(pipeline, index) is Some(step) else {
    return Err(MissingStep)
  }
  let (law, rule) = match operation_rule(step, bindings, unit) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if rule_output_unit(rule) != unit {
    return Err(LawMismatch)
  }
  let (input_count, fallback_input_count) = match rule {
    One | Constant(_) => (0, None)
    Preserve | Multiply(_) | GraphMeasure(_, _, _, _) => (1, None)
    Clamp(_) => (1, Some(0))
    Sum | Join(_) => (2, None)
    QueryTopK(_) => (2, Some(1))
    GraphConstructionMeasure(_, _, n) => (n, None)
    Ranking(n, maximum) =>
      (n, if n > 0 && maximum is Some(_) { Some(0) } else { None })
  }
  Ok({
    pipeline,
    index,
    unit,
    input_count,
    fallback_input_count,
    step,
    rule,
    law,
    bindings,
  })
}

///|
/// O(1) read in capacity-operand order. The edge coordinate records the actual
/// data role even when multiple operands select the same target. Invalid arity
/// or index returns None without allocating an input array.
pub fn bound_derivation_input_at(
  derivation : BoundDerivation,
  operand_count : Int,
  index : Int,
) -> BoundOperand? {
  if index < 0 ||
    index >= operand_count ||
    !rule_input_count_valid(derivation.rule, operand_count) {
    return None
  }
  let (unit, edge) = rule_input_descriptor(
    derivation.rule,
    operand_count,
    index,
  )
  @pipeline.input_occurrence_at(derivation.step, edge).map(input => {
    target: input.target,
    unit,
    edge,
  })
}

///|
/// Arithmetic ceiling for potentially reusing a unary input bound. Callers must
/// also require forwarded_bound_target to select that operand: an unchanged
/// numeric bound alone does not establish a valid evidence-transfer path.
/// This reader neither establishes input applicability nor discharges runtime checks.
pub fn bound_derivation_reuse_ceiling(derivation : BoundDerivation) -> Int64? {
  match derivation.rule {
    Clamp(maximum) => Some(maximum)
    Preserve | Multiply(1L) => Some(9007199254740991L)
    _ => None
  }
}

///|
/// Check a supplied claim for this retained request and report application
/// input/operand work separately even on rejection. Integrity admission remains
/// a separate boundary; neither independent allowance replaces aggregate work.
pub fn check_prepared_bound(
  derivation : BoundDerivation,
  proof : @wire.ProgramProofClaim,
  inputs : Array[BoundInput],
  max_work : Int,
  max_input_work? : Int = 2147483647,
  max_operand_work? : Int = 2147483647,
) -> (Result[StepBound, Issue], (Int, Int)) {
  if max_work < 0 {
    return (Err(InvalidInputWorkLimit), (0, 0))
  }
  if @wire.unit(@wire.program_proof_witness(proof)) != derivation.unit {
    return (Err(LawMismatch), (0, 0))
  }
  let usage = [0, 0]
  let result = check_application(
    derivation.pipeline,
    derivation.index,
    proof,
    inputs.length(),
    i => inputs[i],
    max_input_work.min(max_work),
    max_operand_work.min(max_work),
    derivation.bindings,
    false,
    usage=Some(usage),
    aggregate_work=Some(max_work),
  )
  (result, (usage[0], usage[1]))
}

///|
/// The same non-expanding transfer used by input application checks. Absence
/// means that rule cannot transfer this measure, not that no other bound exists.
pub fn forwarded_bound_target(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  unit : @arithmetic.BoundUnit,
) -> @pipeline.Target? {
  guard @pipeline.step_at(pipeline, index) is Some(step) else { return None }
  forwarded_input(step, unit)
}
