///|
/// One owned demand with a static template for every generated pivot column.
/// Empty generated columns retain the checked demand but have no observations.
pub struct PivotNumericDemand {
  requirement_index : Int
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  pivot : @relation.CheckedPivot
  profile : @numeric.Profile
}

///|
struct ProgramPivotNumericSlots {
  requirements : ProgramOperationRequirements
  entries : Array[PivotNumericDemand]
  columns : Int
  work : Int
}

///|
pub fn pivot_numeric_demand_count(v : ProgramPivotNumericSlots) -> Int {
  v.entries.length()
}

///|
pub fn pivot_numeric_demand_at(
  v : ProgramPivotNumericSlots,
  index : Int,
) -> PivotNumericDemand? {
  v.entries.get(index)
}

///|
pub fn pivot_numeric_slots_requirements(
  v : ProgramPivotNumericSlots,
) -> ProgramOperationRequirements {
  v.requirements
}

///|
pub fn pivot_numeric_slots_work(v : ProgramPivotNumericSlots) -> Int {
  v.work
}

///|
pub fn pivot_numeric_total_slot_count(v : ProgramPivotNumericSlots) -> Int {
  v.columns
}

///|
pub fn pivot_numeric_slot_count(v : PivotNumericDemand) -> Int {
  @relation.pivot_column_count(v.pivot)
}

///|
pub fn pivot_numeric_slot_name_at(
  v : PivotNumericDemand,
  index : Int,
) -> String? {
  @relation.pivot_column_at(v.pivot, index)
}

///|
pub fn prepare_program_pivot_numeric_slots(
  requirements : ProgramOperationRequirements,
  profile : @numeric.Profile,
  max_work : Int,
  max_demands : Int,
  max_columns : Int,
) -> Result[ProgramPivotNumericSlots, NumericSlotsIssue] {
  if max_work < 0 || max_demands < 0 || max_columns < 0 {
    return Err(InvalidLimits)
  }
  let mut work = requirements.work
  let mut columns = 0
  let entries : Array[PivotNumericDemand] = []
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
    guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
      return Err(UnsupportedOccurrence(i))
    }
    let operation = match step.operation {
      @pipeline.WindowGroup(_) => continue
      @pipeline.Unary(op) => op
      _ => return Err(UnsupportedOccurrence(i))
    }
    if @relation.operation(operation) == @relation.Group ||
      @relation.analytic(operation) is Some(_) {
      continue
    }
    guard @relation.pivot(operation) is Some(pivot) else {
      return Err(UnsupportedOccurrence(i))
    }
    guard step.input is Some(input) &&
      site.group == 0 &&
      @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
      @pipeline.input_occurrence_count(step) == 1 &&
      @relation.pending_validation_at(operation, site.index) is Some(owned) &&
      owned.kind == pending.kind &&
      physical_equal(owned.source, pending.source) &&
      (
        @relation.pivot_function(pivot) is @relation.Sum ||
        @relation.pivot_function(pivot) is @relation.Avg
      ) &&
      @relation.pivot_result(pivot).shape is @contract.Number else {
      return Err(ForeignOccurrence(i))
    }
    let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
    if edge.role != @pipeline.Primary || edge.target != input {
      return Err(ForeignOccurrence(i))
    }
    let n = @relation.pivot_column_count(pivot)
    if entries.length() == max_demands ||
      n > max_columns - columns ||
      work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    if n > max_work - work {
      return Err(BudgetExceeded)
    }
    work += n
    for column in 0..<n {
      let name = @relation.pivot_column_at(pivot, column).unwrap()
      if name.length() > max_work - work {
        return Err(BudgetExceeded)
      }
      work += name.length()
    }
    columns += n
    entries.push({ requirement_index: i, site, step, input, pivot, profile, })
  }
  if work > max_work {
    return Err(BudgetExceeded)
  }
  Ok({ requirements, entries, columns, work, })
}

///|
pub fn link_program_pivot_numeric_slots(
  index : ProgramOperationResolutionIndex,
  slots : ProgramPivotNumericSlots,
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
  if index.states.length() > max_work - work ||
    slots.entries.length() > max_links {
    return Err(BudgetExceeded)
  }
  work += index.states.length()
  let states = index.states.copy()
  for demand in slots.entries {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let i = demand.requirement_index
    guard states.get(i) is Some(Unresolved) &&
      demand.step.operation is @pipeline.Unary(operation) else {
      return Err(ForeignOccurrence(i))
    }
    states[i] = Execution(
      PivotExecution({
        site: demand.site,
        step: demand.step,
        input: demand.input,
        operation,
        pivot: demand.pivot,
        rule: CaptureNumericObservations(demand),
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
