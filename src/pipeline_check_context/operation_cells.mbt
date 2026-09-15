///|
pub(all) enum OperationCellIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner(Int)
  IncompatibleCell(Int)
  Scalar(OperationScalarIssue)
} derive(Eq, Debug)

///|
pub struct OperationCellResolution {
  requirement_index : Int
  site : OperationRequirementSite
  values : @values.CheckedValues
  occurrence : @values.BindingCell
  parameter : @parameter.BoundParameter
}

///|
struct ProgramOperationCells {
  queries : ProgramOperationQueries
  entries : Array[OperationCellResolution]
  by_requirement : Map[Int, Int]
  work : Int
}

///|
/// Transfer existing value admission to each owned cell's declaration and target.
/// No wire reconstruction, recursive hole expansion, or value conversion occurs.
pub fn check_program_operation_cells(
  queries : ProgramOperationQueries,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationCells, OperationCellIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if queries.work >= max_work {
    return Err(BudgetExceeded)
  }
  let b = { remaining: max_work - queries.work - 1, }
  let requirements = queries.ranges.fills.frames.scalars.orders.requirements
  let stages = requirements.stages
  let entries : Array[OperationCellResolution] = []
  let by_requirement : Map[Int, Int] = Map([])
  try {
    for i in 0..<requirements.entries.length() {
      scalar_spend(b, 1)
      let site = requirements.entries[i]
      let name = match site.requirement {
        ValuesRequirement(BindCell(name)) => name
        _ => continue
      }
      if entries.length() == max_resolutions {
        return Err(BudgetExceeded)
      }
      let visit = stages.contexts[site.stage].visits[site.producer_visit]
      if !physical_equal(
          @parameter_slots.pipeline(visit.collected),
          site.pipeline,
        ) {
        return Err(ForeignOwner(i))
      }
      guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
        return Err(ForeignOwner(i))
      }
      guard step.operation is @pipeline.Values(values) else {
        return Err(ForeignOwner(i))
      }
      guard @values.pending_binding_cell_at(values, site.index)
        is Some(occurrence) else {
        return Err(ForeignOwner(i))
      }
      guard occurrence.cell
        is @values.Parameter(cell_name, contract=declared, ..) else {
        return Err(ForeignOwner(i))
      }
      scalar_spend(b, name.length())
      scalar_spend(b, cell_name.length())
      if name != cell_name {
        return Err(ForeignOwner(i))
      }
      let parameter = operation_scalar_parameter(visit, name, i, b)
      let actual = parameter.value.contract
      fill_contract_cost(actual, b)
      fill_contract_cost(declared, b)
      fill_contract_cost(actual, b)
      fill_contract_cost(occurrence.target, b)
      let (declared_ok, used) = @contract.assignable_usage(
        actual,
        declared,
        b.remaining,
      ) catch {
        _ => return Err(BudgetExceeded)
      }
      scalar_spend(b, used)
      let (target_ok, used) = @contract.assignable_usage(
        actual,
        occurrence.target,
        b.remaining,
      ) catch {
        _ => return Err(BudgetExceeded)
      }
      scalar_spend(b, used)
      if !declared_ok || !target_ok {
        return Err(IncompatibleCell(i))
      }
      by_requirement[i] = entries.length()
      entries.push({
        requirement_index: i,
        site,
        values,
        occurrence,
        parameter,
      })
    }
    Ok({ queries, entries, by_requirement, work: max_work - b.remaining, })
  } catch {
    OperationScalarStop(BudgetExceeded) => Err(BudgetExceeded)
    OperationScalarStop(issue) => Err(Scalar(issue))
  }
}

///|
pub fn operation_cells_queries(
  v : ProgramOperationCells,
) -> ProgramOperationQueries {
  v.queries
}

///|
pub fn operation_cells_count(v : ProgramOperationCells) -> Int {
  v.entries.length()
}

///|
pub fn operation_cell_at(
  v : ProgramOperationCells,
  index : Int,
) -> OperationCellResolution? {
  v.entries.get(index)
}

///|
pub fn operation_cells_work(v : ProgramOperationCells) -> Int {
  v.work
}
