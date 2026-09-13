///|
/// Attach the admitted profile and exact contributor demand to a runtime
/// obligation. This does not select an algorithm or certify an observation.
pub fn link_program_numeric_slots(
  index : ProgramOperationResolutionIndex,
  slots : ProgramNumericSlots,
  max_work : Int,
  max_links : Int,
) -> Result[ProgramOperationResolutionIndex, NumericSlotsIssue] {
  if max_work < 0 || max_links < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(index.requirements, slots.requirements) {
    return Err(ForeignOccurrence(-1))
  }
  let extra = slots.work - slots.requirements.work
  if index.work > max_work || extra > max_work - index.work {
    return Err(BudgetExceeded)
  }
  let mut work = index.work + extra
  let count = index.states.length()
  if count > max_work - work || slots.entries.length() > max_links {
    return Err(BudgetExceeded)
  }
  work += count
  let states = index.states.copy()
  for slot in slots.entries {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let i = slot.requirement_index
    guard states.get(i) is Some(Unresolved) else {
      return Err(ForeignOccurrence(i))
    }
    let operation = match slot.step.operation {
      @pipeline.Unary(op) | @pipeline.WindowGroup(op) => op
      _ => return Err(ForeignOccurrence(i))
    }
    states[i] = Execution(
      GroupExecution({
        site: slot.site,
        step: slot.step,
        input: slot.input,
        operation,
        group: slot.group,
        rule: CaptureNumericObservation(slot),
      }),
    )
  }
  Ok({
    ..index,
    states,
    unresolved: index.unresolved - slots.entries.length(),
    work,
  })
}
