///|
pub(all) enum GraphStructuralRule {
  AdmitStructuralInputs
  CompareIdentityRecords
  RequirePropertyEquality
  ApplyPropertyStrategies
  RetainOneSidedRecords
  SubtractMatchingRecords
  CloseResultEndpoints
  ValidateSetResults
  ValidateNumericResults
  PreserveOperandPolicies
  RequireStructuralResources
} derive(Eq, Debug)

///|
pub(all) enum GraphStructuralResource {
  CompositionWork
  ValueAndTemporaryBytes
  RetainedCompositionState
} derive(Eq, Debug)

///|
/// A fold accumulator belongs to this check's exact pipeline step, not a
/// generated pipeline target or a reorderable list of source graph names.
pub(all) enum StructuralOperand {
  StructuralInput(@pipeline.Target)
  UnionAccumulator(Int)
} derive(Eq, Debug)

///|
pub struct GraphStructuralCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : StructuralOperand
  right : @pipeline.Target
  operation : @graph.CheckedStructural
  rule : GraphStructuralRule
  policy : @policy.Policy
}

///|
/// All folds of one owned step consume the same operation-wide resource scope.
/// These categories require a selected realization contract, not a new ceiling
/// inferred from an external Graph-input policy field or a candidate row bound.
pub fn graph_structural_resource_count(check : GraphStructuralCheck) -> Int {
  if check.rule == RequireStructuralResources {
    3
  } else {
    0
  }
}

///|
pub fn graph_structural_resource_at(
  check : GraphStructuralCheck,
  index : Int,
) -> GraphStructuralResource? {
  if check.rule != RequireStructuralResources {
    return None
  }
  match index {
    0 => Some(CompositionWork)
    1 => Some(ValueAndTemporaryBytes)
    2 => Some(RetainedCompositionState)
    _ => None
  }
}

///|
fn graph_structural_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.StructuralRequirement(pending) else {
    return Ok(None)
  }
  let rule : GraphStructuralRule = match pending {
    AdmitGraphsUnderCommonContract => AdmitStructuralInputs
    CompareCompleteIdentityPayloads => CompareIdentityRecords
    RejectUnspecifiedConflicts => RequirePropertyEquality
    ApplyEveryAuthoredStrategy => ApplyPropertyStrategies
    KeepCompleteOneSidedUnionRecords => RetainOneSidedRecords
    KeepOnlyLeftSubtractionRecords => SubtractMatchingRecords
    CloseSubtractionEndpoints => CloseResultEndpoints
    ValidateCanonicalSetOperations => ValidateSetResults
    ValidateFiniteNumericResults => ValidateNumericResults
    PreservePolicyDependencies => PreserveOperandPolicies
    ResolveStructuralResources => RequireStructuralResources
    ResolveSgaProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.input is Some(input) else {
    return Err(ForeignOccurrence(site.step))
  }
  let (operation, left, right, right_index, right_role) = match step.operation {
    @pipeline.GraphStructural(right~, checked=operation) => {
      guard site.group == 0 &&
        @pipeline.operation_obligations_scope(site.obligations) ==
        @pipeline.Body &&
        @pipeline.input_occurrence_count(step) == 2 else {
        return Err(ForeignOccurrence(site.step))
      }
      (operation, StructuralInput(input), right, 1, @pipeline.Right)
    }
    @pipeline.GraphUnion(union) => {
      guard @pipeline.operation_obligations_scope(site.obligations)
        is @pipeline.UnionFold(fold) &&
        fold == site.group &&
        @graph.union_fold_at(union, fold) is Some(operation) &&
        @pipeline.input_occurrence_count(step) == @graph.union_count(union) + 1 &&
        @pipeline.input_occurrence_at(step, fold + 1) is Some(right) else {
        return Err(ForeignOccurrence(site.step))
      }
      (
        operation,
        if fold == 0 {
          StructuralInput(input)
        } else {
          UnionAccumulator(fold - 1)
        },
        right.target,
        fold + 1,
        @pipeline.Sample(fold),
      )
    }
    _ => return Err(ForeignOccurrence(site.step))
  }
  guard @graph.structural_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_at(step, 0) is Some(first) &&
    first.role == @pipeline.Left &&
    first.target == input &&
    @pipeline.input_occurrence_at(step, right_index) is Some(second) &&
    second.role == right_role &&
    second.target == right else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      GraphStructuralExecution({
        site,
        step,
        left,
        right,
        operation,
        rule,
        policy,
      }),
    ),
  )
}
