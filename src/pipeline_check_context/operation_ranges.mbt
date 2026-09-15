///|
pub(all) enum OperationRangeIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner(Int)
  InvalidCalendarYear(Int)
  ReversedRange(Int)
  Scalar(OperationScalarIssue)
} derive(Eq, Debug)

///|
pub struct OperationRangeResolution {
  requirement_index : Int
  site : OperationRequirementSite
  start : String
  end : String
  start_parameter : @parameter.BoundParameter?
  end_parameter : @parameter.BoundParameter?
}

///|
struct ProgramOperationRanges {
  fills : ProgramOperationFills
  entries : Array[OperationRangeResolution]
  work : Int
}

///|
priv enum RangeEndpoint {
  Literal(String)
  Parameter(String)
}

///|
fn range_endpoint(
  value : RangeEndpoint,
  visit : ParameterVisit,
  i : Int,
  b : OperationScalarBudget,
) -> (String, @parameter.BoundParameter?) raise OperationScalarStop {
  scalar_spend(b, 1)
  match value {
    Literal(text) => (text, None)
    Parameter(name) => {
      let p = operation_scalar_parameter(visit, name, i, b)
      guard p.value.value is @value.Timestamp(text) else {
        raise OperationScalarStop(InvalidValue(i, @pipeline.Timestamp(name)))
      }
      (text, Some(p))
    }
  }
}

///|
fn series_endpoint(v : @series.Endpoint) -> RangeEndpoint {
  match v {
    Literal(t) => Literal(t)
    Parameter(n) => Parameter(n)
  }
}

///|
fn calendar_endpoint(v : @calendar_options.Endpoint) -> RangeEndpoint {
  match v {
    Literal(t) => Literal(t)
    Parameter(n) => Parameter(n)
  }
}

///|
/// Close UTC interval relationships without evaluating a generated series or
/// converting its endpoints through the host timezone or clock representation.
pub fn check_program_operation_ranges(
  fills : ProgramOperationFills,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationRanges, OperationRangeIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if fills.work >= max_work {
    return Err(BudgetExceeded)
  }
  let b = { remaining: max_work - fills.work - 1, }
  let requirements = fills.frames.scalars.orders.requirements
  let stages = requirements.stages
  let entries : Array[OperationRangeResolution] = []
  try {
    for i in 0..<requirements.entries.length() {
      scalar_spend(b, 1)
      let site = requirements.entries[i]
      let calendar = match site.requirement {
        SeriesRequirement(ValidateRange) => false
        CalendarRequirement(ValidateBoundRange) => true
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
      let (a, z) = match step.operation {
        TimeSeries(series) if !calendar =>
          (
            series_endpoint(@series.start(series)),
            series_endpoint(@series.end(series)),
          )
        Calendar(operation) if calendar =>
          match @calendar_options.input(@calendar.options(operation)) {
            Range(start~, end~) =>
              (calendar_endpoint(start), calendar_endpoint(end))
            _ => return Err(ForeignOwner(i))
          }
        _ => return Err(ForeignOwner(i))
      }
      let (start, start_parameter) = range_endpoint(a, visit, i, b)
      let (end, end_parameter) = range_endpoint(z, visit, i, b)
      scalar_spend(b, start.length())
      scalar_spend(b, end.length())
      if calendar {
        scalar_spend(b, 8)
      }
      if calendar && (start.has_prefix("0000") || end.has_prefix("0000")) {
        return Err(InvalidCalendarYear(i))
      }
      // Both timestamps already have fixed-width canonical UTC spelling, so
      // lexicographic order is chronological, including millisecond precision.
      if start.compare(end) > 0 {
        return Err(ReversedRange(i))
      }
      entries.push({
        requirement_index: i,
        site,
        start,
        end,
        start_parameter,
        end_parameter,
      })
    }
    Ok({ fills, entries, work: max_work - b.remaining, })
  } catch {
    OperationScalarStop(BudgetExceeded) => Err(BudgetExceeded)
    OperationScalarStop(issue) => Err(Scalar(issue))
  }
}

///|
pub fn operation_ranges_fills(
  v : ProgramOperationRanges,
) -> ProgramOperationFills {
  v.fills
}

///|
pub fn operation_ranges_count(v : ProgramOperationRanges) -> Int {
  v.entries.length()
}

///|
pub fn operation_range_at(
  v : ProgramOperationRanges,
  index : Int,
) -> OperationRangeResolution? {
  v.entries.get(index)
}

///|
pub fn operation_ranges_work(v : ProgramOperationRanges) -> Int {
  v.work
}
