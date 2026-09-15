///|
/// The inspected cardinality choice, retaining conditional key evidence and any
/// assertion separately. None is unproven, not an inferred many-to-many claim.
pub struct JoinCardinalitySelection {
  requirement_index : Int
  site : OperationRequirementSite
  evidence : @pipeline.JoinEvidence
}

///|
pub struct JoinOutputCheck {
  site : OperationRequirementSite
  capacity : @capacity.ApplicationClosure
  limit : @step_bounds.JoinLimit
}

///|
/// Enforce the checked join kind's occurrence order. Optional logical witnesses
/// are dependencies, not proof supplied by physical input enumeration.
pub struct JoinRowOrderCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  left_order : @pipeline.LogicalOrder?
  right_order : @pipeline.LogicalOrder?
  output_order : @pipeline.LogicalOrder?
}

///|
pub(all) enum JoinInputValidationRule {
  AssertCardinality(@join.Cardinality)
  RejectNullKeyComponents
} derive(Eq, Debug)

///|
/// Validate the exact authored key tuples on the indicated inputs. This is a
/// runtime obligation, never an observation that those rows have passed.
pub struct JoinInputValidationCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @join.CheckedJoin
  rule : JoinInputValidationRule
}

///|
/// A selected row identity, independent of the tuple used to match join rows.
/// The retained conditional key includes its producer and admission obligations.
pub struct JoinIdentityCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  side : @schema.Side
  input : @pipeline.Target
  key : @evidence.KeyedRelation
}

///|
pub(all) enum JoinRequirementIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOccurrence(Int)
  MissingEvidence(Int)
  MissingCapacity(Int)
  KeyEvidence(Int, @evidence.IssueKind)
} derive(Eq, Debug)

///|
/// Consume cached evidence and the selected producer's capacity applications.
/// Does not recompute keys, interpret unproven cardinality as many-to-many, or
/// mark authored uniqueness or null-key assertions as already validated. Their
/// exact input checks remain execution obligations. Row-order preservation
/// is a future execution obligation, not a new total-order witness.
pub fn link_program_join_requirements(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_links : Int,
) -> Result[ProgramOperationResolutionIndex, JoinRequirementIssue] {
  if max_work < 0 || max_links < 0 {
    return Err(InvalidLimits)
  }
  let count = index.states.length()
  if index.work > max_work || count > (max_work - index.work) / 2 {
    return Err(BudgetExceeded)
  }
  let stages = index.requirements.stages
  let states = index.states.copy()
  let mut unresolved = index.unresolved
  let mut links = 0
  let mut selection_work = 0
  for i in 0..<count {
    let site = index.requirements.entries[i]
    let kind = match site.requirement {
      @pipeline.JoinRequirement(ResolveCardinality) => 0
      @pipeline.JoinRequirement(PreserveRowOrder) => 2
      @pipeline.JoinRequirement(ValidateCardinality(_))
      | @pipeline.JoinRequirement(RejectNullKeys) => 3
      @pipeline.JoinRequirement(StableIdentity(_)) => 4
      @pipeline.CrossJoinRequirement(StableIdentity(_)) => 4
      @pipeline.CrossJoinRequirement(ResolveProductBound)
      | @pipeline.CrossJoinRequirement(PreserveLeftMajorProductOrder)
      | @pipeline.CrossJoinRequirement(ValidateExactlyOneRightRow) => 5
      @pipeline.JoinRequirement(ResolveOutputLimit)
      | @pipeline.CrossJoinRequirement(ResolveOutputLimit)
      | @pipeline.IntervalJoinRequirement(ResolveOutputLimit)
      | @pipeline.AsOfRequirement(ResolveOutputLimit) => 1
      _ => continue
    }
    if links == max_links {
      return Err(BudgetExceeded)
    }
    guard states[i] is Unresolved else { return Err(ForeignOccurrence(i)) }
    let stage = stages.contexts[site.stage]
    let visit = stage.visits[site.producer_visit]
    if !physical_equal(
        @parameter_slots.pipeline(visit.collected),
        site.pipeline,
      ) ||
      @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body {
      return Err(ForeignOccurrence(i))
    }
    if kind == 0 {
      guard @pipeline.join_evidence(site.pipeline, site.step) is Some(evidence) else {
        return Err(MissingEvidence(i))
      }
      states[i] = Resolved(
        JoinCardinality({ requirement_index: i, site, evidence, }),
      )
    } else if kind == 2 {
      guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
        return Err(ForeignOccurrence(i))
      }
      guard step.operation is @pipeline.Join(right~, ..) else {
        return Err(ForeignOccurrence(i))
      }
      guard step.input is Some(left) else { return Err(ForeignOccurrence(i)) }
      states[i] = Execution(
        JoinRowOrder({
          site,
          step,
          left,
          right,
          left_order: @pipeline.logical_order(site.pipeline, left),
          right_order: @pipeline.logical_order(site.pipeline, right),
          output_order: @pipeline.logical_order(
            site.pipeline,
            @pipeline.Step(site.step),
          ),
        }),
      )
    } else if kind == 3 {
      guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
        step.operation is @pipeline.Join(right~, checked=operation) &&
        step.input is Some(left) else {
        return Err(ForeignOccurrence(i))
      }
      if @pipeline.input_occurrence_count(step) != 2 {
        return Err(ForeignOccurrence(i))
      }
      let l = @pipeline.input_occurrence_at(step, 0).unwrap()
      let r = @pipeline.input_occurrence_at(step, 1).unwrap()
      if l.target != left ||
        l.role != @pipeline.Left ||
        r.target != right ||
        r.role != @pipeline.Right {
        return Err(ForeignOccurrence(i))
      }
      let rule = match site.requirement {
        @pipeline.JoinRequirement(ValidateCardinality(assertion)) => {
          if @join.assertion(operation) != Some(assertion) {
            return Err(ForeignOccurrence(i))
          }
          AssertCardinality(assertion)
        }
        @pipeline.JoinRequirement(RejectNullKeys) => {
          if @join.null_key(operation) != @join.NullKey::Fail {
            return Err(ForeignOccurrence(i))
          }
          RejectNullKeyComponents
        }
        _ => return Err(ForeignOccurrence(i))
      }
      states[i] = Execution(
        JoinInputValidation({ site, step, left, right, operation, rule, }),
      )
    } else if kind == 4 {
      let side = match site.requirement {
        @pipeline.JoinRequirement(StableIdentity(side))
        | @pipeline.CrossJoinRequirement(StableIdentity(side)) => side
        _ => return Err(ForeignOccurrence(i))
      }
      guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
        step.input is Some(left) else {
        return Err(ForeignOccurrence(i))
      }
      let right = match step.operation {
        @pipeline.Join(right~, ..) | @pipeline.CrossJoin(right~, ..) => right
        _ => return Err(ForeignOccurrence(i))
      }
      let input = if side == @schema.Left { left } else { right }
      let mut key = None
      if @pipeline.candidate_keys(site.pipeline, input) is Some(keys) {
        let remaining = max_work - index.work - count * 2 - selection_work
        let selected = match
          @evidence.select_key(step.source, keys, CanonicalOrder, {
            max_work: remaining,
            max_name_bytes: remaining,
          }) {
          Ok(v) => v
          Err(e) => {
            if e.kind == @evidence.LimitExceeded {
              return Err(BudgetExceeded)
            }
            return Err(KeyEvidence(i, e.kind))
          }
        }
        if selected.work > remaining ||
          selected.name_bytes > remaining - selected.work {
          return Err(BudgetExceeded)
        }
        selection_work += selected.work + selected.name_bytes
        key = selected.key
      }
      if site.requirement is @pipeline.CrossJoinRequirement(_) {
        states[i] = Execution(
          CrossJoinIdentity({ site, step, side, input, key, }),
        )
      } else {
        guard key is Some(key) else { return Err(MissingEvidence(i)) }
        states[i] = Execution(JoinIdentity({ site, step, side, input, key, }))
      }
    } else {
      let capacity = stage.context.capacity
      guard @capacity.application_closure_at(capacity, site.producer_visit)
        is Some(application) else {
        return Err(MissingCapacity(i))
      }
      guard @capacity.consumer_coverage_joins(
          @capacity.application_coverage_consumers(application),
        )
        is Some(joins) else {
        return Err(MissingCapacity(i))
      }
      guard @step_bounds.join_application_at(joins, site.step) is Some(limit) else {
        return Err(MissingCapacity(i))
      }
      if !physical_equal(@step_bounds.join_limit_pipeline(limit), site.pipeline) ||
        @step_bounds.join_limit_step(limit) != site.step ||
        @policy.cid(@step_bounds.join_limit_policy(limit)) !=
        @policy.cid(stages.policy) {
        return Err(ForeignOccurrence(i))
      }
      if kind == 5 {
        let check = match cross_join_execution_check(site, limit) {
          Ok(v) => v
          Err(_) => return Err(ForeignOccurrence(i))
        }
        states[i] = Execution(CrossJoinRows(check))
      } else {
        states[i] = Execution(JoinOutputLimit({ site, capacity, limit, }))
      }
    }
    links += 1
    unresolved -= 1
  }
  Ok({
    ..index,
    states,
    unresolved,
    work: index.work + count * 2 + selection_work,
  })
}
