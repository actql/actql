///|
pub struct AnalyticNumericSlot {
  requirement_index : Int
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  analytic : @relation.CheckedAnalytic
  frame_call : @relation.AnalyticCall
  call : @relation.CheckedAggregate
  profile : @numeric.Profile
}

///|
struct ProgramAnalyticNumericSlots {
  requirements : ProgramOperationRequirements
  entries : Array[AnalyticNumericSlot]
  work : Int
}

///|
/// Prepare static analytic call-template slots. No algorithm, future observation or
/// persistent slot identity is selected, and original requirements stay open.
pub fn prepare_program_analytic_numeric_slots(
  requirements : ProgramOperationRequirements,
  profile : @numeric.Profile,
  max_work : Int,
  max_slots : Int,
) -> Result[ProgramAnalyticNumericSlots, NumericSlotsIssue] {
  if max_work < 0 || max_slots < 0 {
    return Err(InvalidLimits)
  }
  let mut work = requirements.work
  let entries : Array[AnalyticNumericSlot] = []
  for i in 0..<requirements.entries.length() {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let site = requirements.entries[i]
    guard site.requirement is @pipeline.RelationRequirement(pending) &&
      pending.kind is @relation.NumericAggregateObservation else {
      continue
    }
    if @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
      step.operation is @pipeline.Unary(operation) &&
      @relation.operation(operation) == @relation.Group {
      continue
    }
    guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
      step.operation is @pipeline.Unary(operation) &&
      @relation.analytic(operation) is Some(analytic) else {
      return Err(UnsupportedOccurrence(i))
    }
    guard step.input is Some(input) &&
      @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
      @pipeline.input_occurrence_count(step) == 1 &&
      @relation.analytic_call_for_validation(analytic, site.index)
      is Some(frame_call) &&
      frame_call.function is @relation.Aggregate(call) else {
      return Err(ForeignOccurrence(i))
    }
    let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
    guard @relation.pending_validation_at(operation, site.index) is Some(owned) &&
      owned.kind == pending.kind &&
      physical_equal(owned.source, pending.source) &&
      edge.role == @pipeline.Primary &&
      edge.target == input &&
      (
        @relation.aggregate_function(call) is @relation.Sum ||
        @relation.aggregate_function(call) is @relation.Avg
      ) &&
      @relation.aggregate_result(call).shape is @contract.Number else {
      return Err(ForeignOccurrence(i))
    }
    if entries.length() == max_slots || work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    entries.push({
      requirement_index: i,
      site,
      step,
      input,
      analytic,
      frame_call,
      call,
      profile,
    })
  }
  if work > max_work {
    return Err(BudgetExceeded)
  }
  Ok({ requirements, entries, work, })
}

///|
pub fn analytic_numeric_slots_requirements(
  v : ProgramAnalyticNumericSlots,
) -> ProgramOperationRequirements {
  v.requirements
}

///|
pub fn analytic_numeric_slot_count(v : ProgramAnalyticNumericSlots) -> Int {
  v.entries.length()
}

///|
pub fn analytic_numeric_slot_at(
  v : ProgramAnalyticNumericSlots,
  index : Int,
) -> AnalyticNumericSlot? {
  v.entries.get(index)
}

///|
pub fn analytic_numeric_slots_work(v : ProgramAnalyticNumericSlots) -> Int {
  v.work
}
