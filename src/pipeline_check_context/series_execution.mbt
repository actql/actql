///|
pub(all) enum SeriesExecutionRule {
  GenerateTimeGrid
  EnforceSeriesRowCount
  EnforceSeriesOutputEnvelope
} derive(Eq, Debug)

///|
/// An exact conditional count and future generation check, never source coverage
/// or an observed output. Retains the admitted range and original step binding.
pub struct SeriesExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  series : @series.CheckedSeries
  range : OperationRangeResolution
  step_ms : Int64
  step_resolution : OperationScalarResolution?
  row_count : Int64
  policy : @policy.Policy
  ceiling : @policy.Ceiling
  rule : SeriesExecutionRule
}

///|
fn series_execution_check(
  site : OperationRequirementSite,
  occurrence : Int,
  entries : Array[OperationRequirementSite],
  states : Array[OperationResolutionState],
  policy : @policy.Policy,
  max_work : Int,
) -> (Result[OperationExecutionCheck?, OperationResolutionIndexIssue], Int) {
  guard site.requirement is @pipeline.SeriesRequirement(pending) else {
    return (Ok(None), 0)
  }
  let rule = match pending {
    CheckedArithmetic => GenerateTimeGrid
    ResolveRowBound => EnforceSeriesRowCount
    ResolveResources => EnforceSeriesOutputEnvelope
    BindTimestamp(_) | BindStep(_) | ValidateRange => return (Ok(None), 0)
  }
  guard entries.get(occurrence) is Some(expected) &&
    physical_equal(site, expected) &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.TimeSeries(series) &&
    step.input is None &&
    @pipeline.input_occurrence_count(step) == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @series.pending_validation_at(series, site.index) == Some(pending) &&
    @policy.ceiling(policy, "max_relation_output_rows") is Some(ceiling) else {
    return (Err(ForeignOccurrence(occurrence)), 0)
  }
  let budget = { remaining: max_work, }
  let result : Result[OperationExecutionCheck?, OperationResolutionIndexIssue] = try {
    let (range, step_resolution) = series_execution_arguments(
      site, occurrence, entries, states, series, budget,
    )
    let step_ms = match @series.step(series) {
      Literal(n) => n
      Parameter(_) => {
        guard step_resolution is Some(value) && value.value is Milliseconds(n) else {
          raise OperationScalarStop(ForeignOwner(occurrence))
        }
        n
      }
    }
    scalar_spend(budget, range.start.length())
    scalar_spend(budget, range.end.length())
    scalar_spend(budget, 1)
    let row_count = match
      @series.resolve_row_count(
        series,
        start_value=range.start_parameter.map(p => p.value),
        end_value=range.end_parameter.map(p => p.value),
        step_value=if step_resolution is Some(_) { Some(step_ms) } else { None },
      ) {
      Ok(count) => count
      Err(_) => raise OperationScalarStop(ForeignOwner(occurrence))
    }
    Ok(
      Some(
        SeriesExecution({
          site,
          step,
          series,
          range,
          step_ms,
          step_resolution,
          row_count,
          policy,
          ceiling,
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
fn series_execution_arguments(
  site : OperationRequirementSite,
  occurrence : Int,
  entries : Array[OperationRequirementSite],
  states : Array[OperationResolutionState],
  series : @series.CheckedSeries,
  budget : OperationScalarBudget,
) -> (OperationRangeResolution, OperationScalarResolution?) raise OperationScalarStop {
  let mut range : OperationRangeResolution? = None
  let mut scalar : OperationScalarResolution? = None
  let start = occurrence - site.index
  for slot in 0..<@pipeline.operation_obligations_count(site.obligations) {
    scalar_spend(budget, 1)
    let index = start + slot
    guard entries.get(index) is Some(expected) &&
      expected.stage == site.stage &&
      expected.producer_visit == site.producer_visit &&
      expected.step == site.step &&
      physical_equal(expected.pipeline, site.pipeline) &&
      physical_equal(expected.obligations, site.obligations) else {
      raise OperationScalarStop(ForeignOwner(occurrence))
    }
    match expected.requirement {
      @pipeline.SeriesRequirement(ValidateRange) => {
        guard range is None &&
          states.get(index) is Some(Resolved(Range(value))) &&
          value.requirement_index == index &&
          physical_equal(value.site, expected) else {
          raise OperationScalarStop(ForeignOwner(occurrence))
        }
        range = Some(value)
      }
      @pipeline.SeriesRequirement(BindStep(candidate)) => {
        guard @series.step(series) is @window.Parameter(name, ..) else {
          raise OperationScalarStop(ForeignOwner(occurrence))
        }
        scalar_spend(budget, name.length())
        scalar_spend(budget, candidate.length())
        guard candidate == name &&
          scalar is None &&
          states.get(index) is Some(Resolved(Scalar(value))) &&
          value.requirement_index == index &&
          physical_equal(value.site, expected) &&
          value.value is Milliseconds(_) else {
          raise OperationScalarStop(ForeignOwner(occurrence))
        }
        scalar = Some(value)
      }
      _ => ()
    }
  }
  guard range is Some(range) else {
    raise OperationScalarStop(ForeignOwner(occurrence))
  }
  (range, scalar)
}
