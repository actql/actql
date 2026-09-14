///|
/// A future check, not evidence that input rows or their representatives passed.
/// The input target belongs to site.pipeline; producer and admission dependencies
/// remain owned by the enclosing profile chain.
pub struct DedupeTopTieCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
}

///|
pub(all) enum OperationExecutionCheck {
  GraphSelectorExecution(GraphSelectorCheck)
  SubgraphExecution(SubgraphCheck)
  GraphMatchExecution(GraphMatchCheck)
  GraphApplyExecution(GraphApplyCheck)
  GraphDiffExecution(GraphDiffCheck)
  GraphEqualityExecution(GraphEqualityCheck)
  GraphStructuralExecution(GraphStructuralCheck)
  GraphResources(GraphResourcesCheck)
  ComponentsLimits(ComponentsLimitsCheck)
  TraversalLimits(TraversalLimitsCheck)
  ReachLimits(TraversalLimitsCheck)
  ShortestLimits(TraversalLimitsCheck)
  ShortestOutputGuard(TraversalLimitsCheck)
  TraversalOutputGuard(TraversalLimitsCheck)
  TraversalExecution(TraversalCheck)
  ReachExecution(ReachCheck)
  ShortestExecution(ShortestCheck)
  GraphExecution(GraphExecutionCheck)
  GraphConstructionExecution(GraphConstructionCheck)
  GraphProjection(GraphProjectionCheck)
  GraphProjectionOutput(GraphProjectionEnvelope)
  SequenceMatch(SequenceMatchCheck)
  SequenceLimits(SequenceLimitsCheck)
  SequenceExecution(SequenceExecutionCheck)
  CalendarExecution(CalendarExecutionCheck)
  SeriesExecution(SeriesExecutionCheck)
  EventEnvelope(EventOutputEnvelope)
  SessionExecution(SessionExecutionCheck)
  EventExecution(EventExecutionCheck)
  AsOfExecution(AsOfExecutionCheck)
  AsOfSearch(AsOfSearchCheck)
  IntervalExecution(IntervalExecutionCheck)
  IntervalSearch(IntervalSearchCheck)
  WatermarkExecution(WatermarkExecutionCheck)
  WindowMembershipLimit(WindowMembershipLimit)
  WindowExecution(WindowExecutionCheck)
  AnalyticExecution(AnalyticExecutionCheck)
  AnalyticEnvelope(AnalyticEnvelopeCheck)
  ExpansionExecution(ExpansionExecutionCheck)
  JsonPickExecution(JsonPickExecutionCheck)
  LagExecution(LagExecutionCheck)
  TopKExecution(TopKExecutionCheck)
  GroupExecution(GroupExecutionCheck)
  RowAssertion(RowAssertionCheck)
  DedupeTopTie(DedupeTopTieCheck)
  ValuesPublication(ValuesPublicationCheck)
  JoinOutputLimit(JoinOutputCheck)
  JoinRowOrder(JoinRowOrderCheck)
  JoinInputValidation(JoinInputValidationCheck)
  JoinIdentity(JoinIdentityCheck)
  AppendRows(AppendRowsCheck)
  SetRows(SetRowsCheck)
  CrossJoinRows(CrossJoinRowsCheck)
  CrossJoinIdentity(CrossJoinIdentityCheck)
}

///|
pub(all) enum ExecutionCheckPhase {
  BeforeOperationInputUse
  BeforeOperationOutput
} derive(Eq, Debug)

///|
pub(all) enum ExecutionCheckFailure {
  RejectOperationOutput
} derive(Eq, Debug)

///|
pub fn operation_execution_phase(
  v : OperationExecutionCheck,
) -> ExecutionCheckPhase {
  match v {
    GraphSelectorExecution(v) =>
      match v.rule {
        AdmitIdentities | RevalidateReferences | RequireSelectorResources =>
          BeforeOperationInputUse
        DeduplicateIdentities | RequireMembership | EvaluateNodePredicate =>
          BeforeOperationOutput
      }
    SubgraphExecution(v) =>
      match v.rule {
        AdmitInputGraph | RequireMaterializationResources =>
          BeforeOperationInputUse
        InduceBothEndpoints
        | FilterInducedEdges
        | PreserveIdentitiesAndProperties
        | PreservePolicyAndScope => BeforeOperationOutput
      }
    GraphMatchExecution(v) =>
      match v.rule {
        AdmitGraph | EnforceMatchResources => BeforeOperationInputUse
        SelectExistingIdentities
        | FilterEdgeTypes
        | EvaluatePredicate
        | OrderMatches => BeforeOperationOutput
      }
    GraphApplyExecution(v) =>
      match v.rule {
        ApplyChangesAtomically | AdmitResultGraph | MatchTargetIdentity =>
          BeforeOperationOutput
        RequireSingleDeltaRow
        | AdmitDeltaShapeAndVersion
        | MatchGraphContract
        | AdmitBaseGraph
        | MatchBaseIdentity
        | ValidateUniqueOrderedActions
        | MatchBeforeRecords
        | CheckActionExistence
        | PreservePolicyDependencies
        | RequireApplicationResources => BeforeOperationInputUse
      }
    GraphDiffExecution(v) =>
      match v.rule {
        AdmitCommonSnapshots | RequireDeltaResources => BeforeOperationInputUse
        EmitVersion
        | EmitContractIdentity
        | BindSnapshotIdentities
        | EmitCompleteRecords
        | OrderUniqueActions => BeforeOperationOutput
      }
    GraphEqualityExecution(v) =>
      match v.rule {
        AdmitOperands | RequireComparisonResources => BeforeOperationInputUse
        CompareCanonicalGraphs => BeforeOperationOutput
      }
    GraphStructuralExecution(v) =>
      match v.rule {
        AdmitStructuralInputs => BeforeOperationInputUse
        CompareIdentityRecords
        | RequirePropertyEquality
        | ApplyPropertyStrategies
        | RetainOneSidedRecords
        | SubtractMatchingRecords
        | CloseResultEndpoints
        | ValidateSetResults
        | ValidateNumericResults
        | PreserveOperandPolicies => BeforeOperationOutput
      }
    ComponentsLimits(_)
    | TraversalLimits(_)
    | ReachLimits(_)
    | ShortestLimits(_)
    | ShortestOutputGuard(_)
    | TraversalOutputGuard(_)
    | GraphResources(_) => BeforeOperationOutput
    ShortestExecution(v) =>
      match v.rule {
        AdmitShortestInput | RequireEndpoints | ValidateAllWeights =>
          BeforeOperationInputUse
        FoldCostsWithOverrange
        | RejectSelectedOverrange
        | SelectSimpleBoundedPaths
        | ApplyPathTieBreaks
        | OrderOutputRows => BeforeOperationOutput
      }
    ReachExecution(v) =>
      match v.rule {
        AdmitInputGraph | RequireStartMembership => BeforeOperationInputUse
        EmitBoundedMinimumDepth | OrderReachRows => BeforeOperationOutput
      }
    TraversalExecution(v) =>
      match v.rule {
        AdmitInputGraph => BeforeOperationInputUse
        RespectAuthoredHops
        | EvaluateHopConditions
        | EmitMinimumDepth
        | EnumerateSimplePaths
        | DeduplicatePathIdentities
        | OrderTraversalRows => BeforeOperationOutput
      }
    GraphExecution(v) =>
      match v.rule {
        AdmitGraphData => BeforeOperationInputUse
        OrderComponentIdentities | OrderBoundsReport => BeforeOperationOutput
      }
    GraphConstructionExecution(v) =>
      match v.rule {
        AdmitInputRows => BeforeOperationInputUse
        CloseDeclaredEndpoints
        | DeriveEndpointNodes
        | JournalEndpoints
        | JournalLabels
        | CollapseEqualPayloads
        | EnforceConstructionEnvelope
        | RejectPayloadConflicts => BeforeOperationOutput
      }
    GraphProjectionOutput(_) => BeforeOperationOutput
    GraphProjection(v) =>
      match v.rule {
        AdmitGraphRecords => BeforeOperationInputUse
        RejectColumnCollisions | RestoreIdentityNames => BeforeOperationOutput
      }
    SequenceMatch(_) => BeforeOperationOutput
    SequenceLimits(_) => BeforeOperationOutput
    SequenceExecution(_) => BeforeOperationInputUse
    CalendarExecution(v) =>
      if v.rule == AdmitCalendarValues && v.step.input is Some(_) {
        BeforeOperationInputUse
      } else {
        BeforeOperationOutput
      }
    SeriesExecution(_) => BeforeOperationOutput
    EventEnvelope(_) => BeforeOperationOutput
    SessionExecution(_) => BeforeOperationOutput
    EventExecution(v) =>
      match v.rule {
        AdmitEventValues | ValidateEventIdentities | ConvertEventClock =>
          BeforeOperationInputUse
        ClassifyEventWatermark | SelectEventRepresentative =>
          BeforeOperationOutput
      }
    AsOfExecution(v) =>
      match v.rule {
        AdmitAsOfClocksAndDistances
        | ValidateAsOfLeftIdentity
        | ValidateAsOfKey(_, _) => BeforeOperationInputUse
        SelectAsOfMatch | OrderAsOfOutput => BeforeOperationOutput
      }
    IntervalSearch(_) => BeforeOperationInputUse
    AsOfSearch(_) => BeforeOperationInputUse
    IntervalExecution(v) =>
      match v.rule {
        AdmitAllIntervalEndpoints | AdmitSafeIntegerClocks =>
          BeforeOperationInputUse
        PreserveIntervalOccurrenceOrder => BeforeOperationOutput
      }
    WatermarkExecution(v) =>
      match v.rule {
        AdmitWatermarkTime => BeforeOperationInputUse
        ApplyWatermark(_) => BeforeOperationOutput
      }
    WindowMembershipLimit(_) => BeforeOperationOutput
    WindowExecution(v) =>
      match v.rule {
        AdmitTimeValues => BeforeOperationInputUse
        AssignMemberships(_) => BeforeOperationOutput
      }
    AnalyticExecution(_) => BeforeOperationOutput
    AnalyticEnvelope(_) => BeforeOperationOutput
    ExpansionExecution(_) => BeforeOperationOutput
    JsonPickExecution(_) => BeforeOperationOutput
    LagExecution(_) => BeforeOperationOutput
    TopKExecution(_) => BeforeOperationOutput
    GroupExecution(_) => BeforeOperationOutput
    RowAssertion(_) => BeforeOperationOutput
    DedupeTopTie(_) => BeforeOperationOutput
    ValuesPublication(_) => BeforeOperationOutput
    JoinOutputLimit(_) => BeforeOperationOutput
    JoinRowOrder(_) => BeforeOperationOutput
    JoinInputValidation(_) => BeforeOperationInputUse
    JoinIdentity(_) => BeforeOperationInputUse
    CrossJoinIdentity(_) => BeforeOperationInputUse
    CrossJoinRows(v) =>
      match v.rule {
        CheckProductArithmetic | RequireExactlyOneRightRow =>
          BeforeOperationInputUse
        PreserveLeftMajorOrder => BeforeOperationOutput
      }
    AppendRows(v) =>
      match v.rule {
        AdmitBothInputs => BeforeOperationInputUse
        PreserveLeftThenRight
        | RetainIdentityAndCompleteness
        | EnforceOutputEnvelope(_) => BeforeOperationOutput
      }
    SetRows(v) =>
      match v.rule {
        AdmitBothInputs | RequireComparisonResources => BeforeOperationInputUse
        CompareCompleteTypedRows
        | PreserveEarliestLeftOccurrences
        | BoundOutputByLeftInput
        | RetainIdentityAndCompleteness => BeforeOperationOutput
      }
  }
}

///|
pub fn operation_execution_failure(
  v : OperationExecutionCheck,
) -> ExecutionCheckFailure {
  match v {
    GraphSelectorExecution(_)
    | SubgraphExecution(_)
    | GraphMatchExecution(_)
    | GraphApplyExecution(_)
    | GraphDiffExecution(_)
    | GraphEqualityExecution(_)
    | GraphStructuralExecution(_)
    | GraphResources(_)
    | ComponentsLimits(_)
    | TraversalLimits(_)
    | ReachLimits(_)
    | ShortestLimits(_)
    | ShortestOutputGuard(_)
    | TraversalOutputGuard(_)
    | TraversalExecution(_)
    | ReachExecution(_)
    | ShortestExecution(_)
    | GraphProjection(_)
    | GraphExecution(_)
    | GraphProjectionOutput(_)
    | GraphConstructionExecution(_) => RejectOperationOutput
    AsOfExecution(_) => RejectOperationOutput
    IntervalExecution(_) => RejectOperationOutput
    IntervalSearch(_) => RejectOperationOutput
    SessionExecution(_) => RejectOperationOutput
    SequenceMatch(_) => RejectOperationOutput
    SequenceLimits(_) => RejectOperationOutput
    SequenceExecution(_) => RejectOperationOutput
    CalendarExecution(_) => RejectOperationOutput
    SeriesExecution(_) => RejectOperationOutput
    EventEnvelope(_) => RejectOperationOutput
    EventExecution(_) => RejectOperationOutput
    AsOfSearch(_) => RejectOperationOutput
    WatermarkExecution(_) => RejectOperationOutput
    WindowMembershipLimit(_) => RejectOperationOutput
    WindowExecution(_) => RejectOperationOutput
    AnalyticExecution(_) => RejectOperationOutput
    AnalyticEnvelope(_) => RejectOperationOutput
    ExpansionExecution(_) => RejectOperationOutput
    JsonPickExecution(_) => RejectOperationOutput
    LagExecution(_) => RejectOperationOutput
    TopKExecution(_) => RejectOperationOutput
    GroupExecution(_) => RejectOperationOutput
    RowAssertion(_) => RejectOperationOutput
    DedupeTopTie(_) => RejectOperationOutput
    ValuesPublication(_) => RejectOperationOutput
    JoinOutputLimit(_) => RejectOperationOutput
    JoinRowOrder(_) => RejectOperationOutput
    JoinInputValidation(_) => RejectOperationOutput
    JoinIdentity(_) => RejectOperationOutput
    CrossJoinIdentity(_) => RejectOperationOutput
    CrossJoinRows(_) => RejectOperationOutput
    AppendRows(_) => RejectOperationOutput
    SetRows(_) => RejectOperationOutput
  }
}

///|
/// Interpretation rule, not backend registration or an execution receipt.
pub fn dedupe_top_tie_law(_v : DedupeTopTieCheck) -> String {
  "aoa.rela.REL.dedupeRows.v0.1"
}

///|
/// Authored keys only: candidate keys, arrival order and CID cannot choose a
/// tied representative. A top tie rejects the operation's entire output.
fn dedupe_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) else {
    return Ok(None)
  }
  guard pending.kind is @relation.FailOnTopTie else { return Ok(None) }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(ForeignOccurrence(site.step))
  }
  guard step.operation is @pipeline.Unary(operation) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @relation.operation(operation) != @relation.DedupeRows ||
    @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body ||
    @relation.dedupe_order_count(operation) == 0 ||
    @pipeline.input_occurrence_count(step) != 1 {
    return Err(ForeignOccurrence(site.step))
  }
  guard step.input is Some(input) else {
    return Err(ForeignOccurrence(site.step))
  }
  let connection = @pipeline.input_occurrence_at(step, 0).unwrap()
  if connection.role != @pipeline.Primary || connection.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(DedupeTopTie({ site, step, input, operation, })))
}
