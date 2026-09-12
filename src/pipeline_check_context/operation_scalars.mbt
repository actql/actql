///|
pub(all) enum OperationScalarIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner(Int)
  MissingBindings(Int)
  InvalidValue(Int, @pipeline.OperationScalarDemand)
} derive(Eq, Debug)

///|
pub(all) enum OperationScalarValue {
  Integer(Int64)
  Fraction(Double)
  Finite(Double)
  DurationMilliseconds(Int64)
  Milliseconds(Int64)
} derive(Eq, Debug)

///|
pub struct OperationScalarResolution {
  requirement_index : Int
  site : OperationRequirementSite
  parameter : @parameter.BoundParameter
  value : OperationScalarValue
}

///|
struct ProgramOperationScalars {
  orders : ProgramOperationOrders
  entries : Array[OperationScalarResolution]
  work : Int
}

///|
priv struct OperationScalarBudget {
  mut remaining : Int
}

///|
priv suberror OperationScalarStop {
  OperationScalarStop(OperationScalarIssue)
}

///|
fn scalar_spend(
  b : OperationScalarBudget,
  n : Int,
) -> Unit raise OperationScalarStop {
  if n > b.remaining {
    raise OperationScalarStop(BudgetExceeded)
  }
  b.remaining -= n
}

///|
fn operation_scalar_value(
  value : @value.Value,
  demand : @pipeline.OperationScalarDemand,
) -> OperationScalarValue? {
  if demand is @pipeline.Milliseconds(_, ..) && value is @value.Text(text) {
    return @scalar.read_duration_ms(text).map(n => Milliseconds(n))
  }
  if demand is @pipeline.Duration(_) {
    guard value is @value.Text(text) else { return None }
    return @scalar.read_duration_ms(text).map(n => DurationMilliseconds(n))
  }
  guard value is @value.Number(n) else { return None }
  operation_scalar_number(n, demand)
}

///|
fn operation_scalar_number(
  n : Double,
  demand : @pipeline.OperationScalarDemand,
) -> OperationScalarValue? {
  if @scalar.read_finite_number(n) is None || (n == 0.0 && 1.0 / n < 0.0) {
    return None
  }
  match demand {
    SafeInteger(_, minimum~) =>
      match @scalar.read_safe_integer(n) {
        Some(n) if n >= minimum => Some(Integer(n))
        _ => None
      }
    Fraction(_) => if n >= 0.0 && n <= 1.0 { Some(Fraction(n)) } else { None }
    Finite(_) => Some(Finite(n))
    Duration(_) => None
    Milliseconds(_, signed~) =>
      match @scalar.read_safe_integer(n) {
        Some(n) if signed || n > 0L => Some(Milliseconds(n))
        _ => None
      }
  }
}

///|
fn operation_scalar_parameter(
  visit : ParameterVisit,
  name : String,
  i : Int,
  b : OperationScalarBudget,
) -> @parameter.BoundParameter raise OperationScalarStop {
  let index = match visit.bound {
    Some(v) => v
    None => raise OperationScalarStop(MissingBindings(i))
  }
  // Search the selected used values, not unrelated supplied names. They follow
  // the immutable declaration index's ASCII name order.
  let mut lo = 0
  let mut hi = @references.used_value_count(index)
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let entry = @references.used_value_at(index, mid).unwrap()
    scalar_spend(b, 1)
    scalar_spend(b, name.length())
    scalar_spend(b, entry.name.length())
    let order = name.compare(entry.name)
    if order < 0 {
      hi = mid
    } else if order > 0 {
      lo = mid + 1
    } else {
      return entry
    }
  }
  raise OperationScalarStop(MissingBindings(i))
}

///|
/// Validate actual owned bindings, without evaluating row expressions or changing
/// their identity projection. All later failures discard the partial result.
pub fn check_program_operation_scalars(
  orders : ProgramOperationOrders,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationScalars, OperationScalarIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if orders.work >= max_work {
    return Err(BudgetExceeded)
  }
  let b = { remaining: max_work - orders.work - 1, }
  let requirements = orders.requirements
  let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let entries : Array[OperationScalarResolution] = []
  try {
    for i in 0..<requirements.entries.length() {
      scalar_spend(b, 1)
      let site = requirements.entries[i]
      guard @pipeline.operation_scalar_demand(site.requirement) is Some(demand) else {
        continue
      }
      let visit = stages.contexts[site.stage].visits[site.producer_visit]
      if !physical_equal(
          @parameter_slots.pipeline(visit.collected),
          site.pipeline,
        ) {
        raise OperationScalarStop(ForeignOwner(i))
      }
      if entries.length() == max_resolutions {
        raise OperationScalarStop(BudgetExceeded)
      }
      let parameter = operation_scalar_parameter(
        visit,
        @pipeline.operation_scalar_name(demand),
        i,
        b,
      )
      scalar_spend(b, 1)
      // Duration syntax is scanned only after its full input cost is reserved.
      if (
          demand is @pipeline.Duration(_) ||
          demand is @pipeline.Milliseconds(_, ..)
        ) &&
        parameter.value.value is @value.Text(text) {
        scalar_spend(b, text.length())
      }
      let value = match operation_scalar_value(parameter.value.value, demand) {
        Some(v) => v
        None => raise OperationScalarStop(InvalidValue(i, demand))
      }
      entries.push({ requirement_index: i, site, parameter, value, })
    }
    Ok({ orders, entries, work: max_work - b.remaining, })
  } catch {
    OperationScalarStop(issue) => Err(issue)
  }
}

///|
pub fn operation_scalars_orders(
  v : ProgramOperationScalars,
) -> ProgramOperationOrders {
  v.orders
}

///|
pub fn operation_scalars_count(v : ProgramOperationScalars) -> Int {
  v.entries.length()
}

///|
pub fn operation_scalar_at(
  v : ProgramOperationScalars,
  index : Int,
) -> OperationScalarResolution? {
  v.entries.get(index)
}

///|
pub fn operation_scalars_work(v : ProgramOperationScalars) -> Int {
  v.work
}
