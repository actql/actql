///|
/// Contextual strategies required by this subset of operation obligations.
/// None does not discharge a different static, resource or runtime obligation.
pub(all) enum OperationOrderDemand {
  CompleteOrder
  StableSequence
  LagKey
  PrefixSequence
  AnalyticPositions
  NestedRows
} derive(Eq, Debug)

///|
pub fn operation_order_demand(v : OperationObligation) -> OperationOrderDemand? {
  match v {
    RelationRequirement(p) | SequenceRowsRequirement(p) =>
      match p.kind {
        SortOrderCompletion => Some(CompleteOrder)
        StableInputOrder => Some(StableSequence)
        LagCandidateKeyOrder => Some(LagKey)
        WatermarkPrefixOrder => Some(PrefixSequence)
        AnalyticPositionOrder => Some(AnalyticPositions)
        FailOnTopTie
        | BoundInteger(..)
        | ValidateReshapeRows
        | ExpansionEnvelope
        | AtomicRowAssertion
        | AssertionConsumption
        | AggregateDemand
        | GroupPartitioning
        | PivotPartitioning
        | BoundFill(_)
        | AnalyticPeerOrder
        | AnalyticFrameDemand
        | AnalyticEnvelope
        | BoundFrameOrder
        | TopKSelectionEnvelope
        | TopKPartitioning
        | AggregateEnvelope
        | NumericAggregateObservation
        | StatisticalAggregateLaw
        | BoundFraction(_)
        | WatermarkArithmetic
        | BoundFinite(_)
        | BoundDuration(_) => None
      }
    NestRequirement(p) =>
      match p {
        ResolveTotalOrder => Some(NestedRows)
        ResolveItemLimit
        | ResolveNestedEnvelope
        | ValidateOutputsBeforeConsumers
        | PropagatePolicyAndCompleteness
        | BindGuard(_) => None
      }
    JoinRequirement(_)
    | AppendRequirement(_)
    | SetRequirement(_)
    | CrossJoinRequirement(_)
    | IntervalJoinRequirement(_)
    | AsOfRequirement(_)
    | SequenceRequirement(_)
    | ValuesRequirement(_)
    | SeriesRequirement(_)
    | CalendarRequirement(_)
    | WindowRequirement(_)
    | MatchRequirement(_)
    | DiagnosticRequirement(_)
    | NormalizeRequirement(_)
    | DeltaRequirement(_)
    | ComponentsRequirement(_)
    | TraverseRequirement(_)
    | SelectorRequirement(_)
    | ConstructionRequirement(_)
    | VectorRequirement(_)
    | NearestRequirement(_)
    | PoolRequirement(_)
    | RankingRequirement(_)
    | TextRankRequirement(_)
    | EventRequirement(_) => None
  }
}
