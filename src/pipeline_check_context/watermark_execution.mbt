///|
pub enum WatermarkThreshold {
  FixedWatermark(Double, OperationScalarResolution?)
  PrefixWatermark(Int64, OperationScalarResolution?, OperationOrderLink)
}

///|
pub enum WatermarkExecutionRule {
  AdmitWatermarkTime
  ApplyWatermark(WatermarkThreshold)
}

///|
/// Future execution obligation, not an observed threshold or valid output.
pub struct WatermarkExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  time : @relation.KeyField
  timestamp : Bool
  late_policy : @relation.LatePolicy
  rule : WatermarkExecutionRule
}

///|
fn watermark_execution_check(
  site : OperationRequirementSite,
  occurrence : Int,
  requirements : ProgramOperationRequirements,
  states : Array[OperationResolutionState],
  max_work : Int,
) -> (Result[OperationExecutionCheck?, OperationResolutionIndexIssue], Int) {
  guard site.requirement is @pipeline.RelationRequirement(pending) &&
    (
      pending.kind is @relation.ValidateReshapeRows ||
      pending.kind is @relation.WatermarkArithmetic
    ) &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Unary(operation) &&
    @relation.operation(operation) == @relation.WatermarkRows else {
    return (Ok(None), 0)
  }
  guard step.input is Some(input) &&
    @relation.row_operation(operation)
    is Some(Watermark(time~, timestamp~, threshold~, policy~)) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @relation.pending_validation_at(operation, site.index) is Some(owned) else {
    return (Err(ForeignOccurrence(occurrence)), 0)
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary ||
    edge.target != input ||
    owned.kind != pending.kind ||
    !physical_equal(owned.source, pending.source) {
    return (Err(ForeignOccurrence(occurrence)), 0)
  }
  let budget = { remaining: max_work, }
  let result : Result[OperationExecutionCheck?, OperationResolutionIndexIssue] = try {
    let rule = if pending.kind is @relation.ValidateReshapeRows {
      AdmitWatermarkTime
    } else {
      ApplyWatermark(
        watermark_threshold(
          threshold, site, occurrence, requirements, states, budget,
        ),
      )
    }
    Ok(
      Some(
        WatermarkExecution({
          site,
          step,
          input,
          operation,
          time,
          timestamp,
          late_policy: policy,
          rule,
        }),
      ),
    )
  } catch {
    OperationScalarStop(BudgetExceeded) => Err(BudgetExceeded)
    OperationScalarStop(_) => Err(ForeignOccurrence(occurrence))
  }
  (result, max_work - budget.remaining)
}

///|
// Scan only this operation's owned requirement group. Keep exact resolution
// objects, never substitute an equal scalar or another producer's input order.
fn watermark_threshold(
  threshold : @relation.WatermarkSource,
  site : OperationRequirementSite,
  occurrence : Int,
  requirements : ProgramOperationRequirements,
  states : Array[OperationResolutionState],
  budget : OperationScalarBudget,
) -> WatermarkThreshold raise OperationScalarStop {
  scalar_spend(budget, 1)
  if threshold is @relation.FixedThreshold(value) {
    return FixedWatermark(value, None)
  }
  let demand : @relation.ValidationKind? = match threshold {
    ThresholdParameter(name) => Some(BoundFinite(name))
    PrefixSkew(Parameter(name), duration~) =>
      if duration {
        Some(BoundDuration(name))
      } else {
        Some(BoundInteger(name~, minimum=1L))
      }
    PrefixSkew(Literal(_), ..) => None
    FixedThreshold(_) => None
  }
  let mut scalar : OperationScalarResolution? = None
  let mut order : OperationOrderLink? = None
  let start = occurrence - site.index
  for slot in 0..<@pipeline.operation_obligations_count(site.obligations) {
    scalar_spend(budget, 1)
    let index = start + slot
    guard requirements.entries.get(index) is Some(expected) &&
      expected.stage == site.stage &&
      expected.producer_visit == site.producer_visit &&
      expected.step == site.step &&
      physical_equal(expected.obligations, site.obligations) else {
      raise OperationScalarStop(ForeignOwner(occurrence))
    }
    guard expected.requirement is @pipeline.RelationRequirement(pending) else {
      continue
    }
    if demand is Some(kind) {
      // Parameter names are bounded source text; charge comparisons as well.
      match kind {
        BoundFinite(name) | BoundDuration(name) | BoundInteger(name~, ..) =>
          scalar_spend(budget, name.length())
        _ => ()
      }
      if pending.kind == kind {
        guard scalar is None &&
          states.get(index) is Some(Resolved(Scalar(value))) &&
          value.requirement_index == index &&
          physical_equal(value.site, expected) else {
          raise OperationScalarStop(ForeignOwner(occurrence))
        }
        scalar = Some(value)
      }
    }
    if pending.kind is @relation.WatermarkPrefixOrder {
      guard order is None &&
        states.get(index) is Some(Resolved(Order(value))) &&
        value.requirement_index == index &&
        physical_equal(value.site, expected) &&
        value.resolution is @pipeline.InputSequence(input_order) &&
        @pipeline.input_order_requirement(input_order)
        is @relation.WatermarkPrefixOrder else {
        raise OperationScalarStop(ForeignOwner(occurrence))
      }
      order = Some(value)
    }
  }
  match threshold {
    ThresholdParameter(_) => {
      guard scalar is Some(value) && value.value is Finite(n) else {
        raise OperationScalarStop(ForeignOwner(occurrence))
      }
      FixedWatermark(n, scalar)
    }
    PrefixSkew(count, duration~) => {
      guard order is Some(order) else {
        raise OperationScalarStop(ForeignOwner(occurrence))
      }
      let n = match count {
        Literal(n) => n
        Parameter(_) => {
          guard scalar is Some(value) else {
            raise OperationScalarStop(ForeignOwner(occurrence))
          }
          match value.value {
            DurationMilliseconds(n) if duration => n
            Integer(n) if !duration => n
            _ => raise OperationScalarStop(ForeignOwner(occurrence))
          }
        }
      }
      PrefixWatermark(n, scalar, order)
    }
    FixedThreshold(n) => FixedWatermark(n, None)
  }
}
