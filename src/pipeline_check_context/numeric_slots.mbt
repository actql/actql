///|
pub(all) enum NumericSlotsIssue {
  InvalidLimits
  BudgetExceeded
  UnsupportedOccurrence(Int)
  ForeignOccurrence(Int)
} derive(Eq, Debug)

///|
pub struct NumericSlot {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  group : @relation.CheckedGroup
  call : @relation.CheckedAggregate
  profile : @numeric.Profile
}

///|
struct ProgramNumericSlots {
  requirements : ProgramOperationRequirements
  entries : Array[NumericSlot]
  work : Int
}

///|
/// Prepare static ordinary-group slots. No algorithm, future observation or
/// persistent slot identity is selected, and original requirements stay open.
pub fn prepare_program_numeric_slots(
  requirements : ProgramOperationRequirements,
  profile : @numeric.Profile,
  max_work : Int,
  max_slots : Int,
) -> Result[ProgramNumericSlots, NumericSlotsIssue] {
  if max_work < 0 || max_slots < 0 {
    return Err(InvalidLimits)
  }
  let mut work = requirements.work
  let entries : Array[NumericSlot] = []
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
    guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
      step.operation is @pipeline.Unary(operation) &&
      @relation.operation(operation) == @relation.Group &&
      @relation.group(operation) is Some(group) else {
      return Err(UnsupportedOccurrence(i))
    }
    guard step.input is Some(input) &&
      @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
      @pipeline.input_occurrence_count(step) == 1 &&
      @relation.aggregate_for_validation(group, site.index) is Some(call) else {
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
    entries.push({ site, step, input, group, call, profile, })
  }
  if work > max_work {
    return Err(BudgetExceeded)
  }
  Ok({ requirements, entries, work, })
}

///|
pub fn numeric_slots_requirements(
  v : ProgramNumericSlots,
) -> ProgramOperationRequirements {
  v.requirements
}

///|
pub fn numeric_slot_count(v : ProgramNumericSlots) -> Int {
  v.entries.length()
}

///|
pub fn numeric_slot_at(v : ProgramNumericSlots, index : Int) -> NumericSlot? {
  v.entries.get(index)
}

///|
pub fn numeric_slots_work(v : ProgramNumericSlots) -> Int {
  v.work
}
