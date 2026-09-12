///|
/// Scalar domains still required after Parameter declaration admission.
pub(all) enum OperationScalarDemand {
  SafeInteger(String, minimum~ : Int64)
  Fraction(String)
  Finite(String)
  Duration(String)
  Milliseconds(String, signed~ : Bool)
} derive(Eq, Debug)

///|
pub fn operation_scalar_name(v : OperationScalarDemand) -> String {
  match v {
    SafeInteger(n, ..)
    | Fraction(n)
    | Finite(n)
    | Duration(n)
    | Milliseconds(n, ..) => n
  }
}

///|
/// Other obligations, including relational frame/fill checks, remain separate.
pub fn operation_scalar_demand(
  v : OperationObligation,
) -> OperationScalarDemand? {
  match v {
    RelationRequirement(p) | SequenceRowsRequirement(p) =>
      match p.kind {
        BoundInteger(name~, minimum~) => Some(SafeInteger(name, minimum~))
        BoundFraction(name) => Some(Fraction(name))
        BoundFinite(name) => Some(Finite(name))
        BoundDuration(name) => Some(Duration(name))
        SortOrderCompletion
        | StableInputOrder
        | FailOnTopTie
        | ValidateReshapeRows
        | ExpansionEnvelope
        | AtomicRowAssertion
        | AssertionConsumption
        | AggregateDemand
        | GroupPartitioning
        | PivotPartitioning
        | BoundFill(_)
        | AnalyticPeerOrder
        | AnalyticPositionOrder
        | AnalyticFrameDemand
        | AnalyticEnvelope
        | BoundFrameOrder
        | TopKSelectionEnvelope
        | TopKPartitioning
        | AggregateEnvelope
        | NumericAggregateObservation
        | StatisticalAggregateLaw
        | LagCandidateKeyOrder
        | WatermarkPrefixOrder
        | WatermarkArithmetic => None
      }
    WindowRequirement(v) =>
      match v {
        BindMilliseconds(name, domain) =>
          Some(Milliseconds(name, signed=domain == @window.SignedMilliseconds))
        ValidateTimeValues
        | CheckedWindowArithmetic
        | ResolveMembershipBound
        | ResolvePublicationResources => None
      }
    EventRequirement(v) =>
      match v {
        BindGap(name) => Some(Milliseconds(name, signed=false))
        ValidateEventValues
        | ValidateUniqueIdentities
        | ResolveTeaProfile
        | ResolveEventResources
        | WatermarkClassification
        | ConvertTimestampClock
        | FailOnTopTie
        | SessionArithmetic
        | SessionIdentity => None
      }
    SeriesRequirement(v) =>
      match v {
        BindStep(name) => Some(Milliseconds(name, signed=false))
        BindTimestamp(_)
        | ValidateRange
        | CheckedArithmetic
        | ResolveRowBound
        | ResolveResources => None
      }
    JoinRequirement(_)
    | AppendRequirement(_)
    | NestRequirement(_)
    | SetRequirement(_)
    | CrossJoinRequirement(_)
    | IntervalJoinRequirement(_)
    | AsOfRequirement(_)
    | SequenceRequirement(_)
    | ValuesRequirement(_)
    | CalendarRequirement(_)
    | ProjectionRequirement(_)
    | GraphRequirement(_)
    | MatchRequirement(_)
    | ReachRequirement(_)
    | SubgraphRequirement(_)
    | TraverseRequirement(_)
    | ShortestRequirement(_)
    | SelectorRequirement(_)
    | EqualityRequirement(_)
    | DiffRequirement(_)
    | ApplyRequirement(_)
    | StructuralRequirement(_)
    | MeanRequirement(_)
    | ConstructionRequirement(_)
    | VectorRequirement(_)
    | NearestRequirement(_)
    | PoolRequirement(_)
    | RankingRequirement(_)
    | TextRankRequirement(_) => None
  }
}
