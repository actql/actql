///|
/// Scalar domains still required after Parameter declaration admission.
pub(all) enum OperationScalarDemand {
  SafeInteger(String, minimum~ : Int64)
  Fraction(String)
  Finite(String)
  Duration(String)
  Milliseconds(String, signed~ : Bool)
  Timestamp(String)
} derive(Eq, Debug)

///|
pub fn operation_scalar_name(v : OperationScalarDemand) -> String {
  match v {
    SafeInteger(n, ..)
    | Fraction(n)
    | Finite(n)
    | Duration(n)
    | Milliseconds(n, ..) => n
    Timestamp(n) => n
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
        BindTimestamp(name) => Some(Timestamp(name))
        ValidateRange
        | CheckedArithmetic
        | ResolveRowBound
        | ResolveResources => None
      }
    CalendarRequirement(v) =>
      match v {
        BindTimestamp(name) => Some(Timestamp(name))
        ValidateCalendarValues
        | ValidateBoundaryDomain
        | ResolveResources
        | ValidateBoundRange => None
      }
    JoinRequirement(v)
    | CrossJoinRequirement(v)
    | IntervalJoinRequirement(v)
    | AsOfRequirement(v) =>
      match v {
        BindGuard(name) => Some(SafeInteger(name, minimum=1L))
        BindTolerance(name) => Some(Milliseconds(name, signed=false))
        ResolveCardinality
        | ResolveOutputLimit
        | PreserveRowOrder
        | StableIdentity(_)
        | ValidateCardinality(_)
        | RejectNullKeys
        | ValidateExactlyOneRightRow
        | ResolveProductBound
        | PreserveLeftMajorProductOrder
        | ValidateIntervalEndpoints
        | ValidateSafeIntegerClocks
        | ResolveSearchWork
        | ValidateAsOfValues
        | ResolveAsOfOrder
        | RejectAsOfTies
        | JournalAsOfKeyCompletion(_)
        | ValidateAsOfKey(_, _)
        | ResolveTeaProfile => None
      }
    NestRequirement(v) =>
      match v {
        BindGuard(name) => Some(SafeInteger(name, minimum=1L))
        ResolveTotalOrder
        | ResolveItemLimit
        | ResolveNestedEnvelope
        | ValidateOutputsBeforeConsumers
        | PropagatePolicyAndCompleteness => None
      }
    SequenceRequirement(v) =>
      match v {
        BindWithin(name) => Some(Milliseconds(name, signed=false))
        ValidateEventValues
        | UniqueEventIdentity
        | AscendingEventOrder
        | BoundedMatchSearch
        | AtomicMatchLimits
        | TeaProfile => None
      }
    TraverseRequirement(v) =>
      match v {
        BindTraversalOutputGuard(name) => Some(SafeInteger(name, minimum=1L))
        AdmitTraversalGraph
        | RespectTraversalHopBounds
        | FilterTraversalLabels
        | EnumeratePropertyPaths
        | DeduplicateExactPaths
        | MinimumEligibleNodeDepth
        | CanonicalTraversalOrder
        | EnforceTraversalOutputGuard
        | ResolveTraversalResources
        | ResolvePropertyGraphTraversalProfile => None
      }
    DiagnosticRequirement(v) =>
      match v {
        BindDiagnosticThreshold(name) => Some(SafeInteger(name, minimum=0L))
        AdmitDiagnosticGraph
        | ResolveDiagnosticResources
        | EnforceDiagnosticRelationRows => None
      }
    ComponentsRequirement(v) =>
      match v {
        BindComponentAuthorGuard(name) => Some(SafeInteger(name, minimum=1L))
        AdmitComponentGraph
        | EnforceComponentInputNodes
        | ResolveComponentResources
        | EnforceComponentOutputRows
        | EnforceComponentAuthorGuard => None
      }
    AppendRequirement(_)
    | NormalizeRequirement(_)
    | DeltaRequirement(_)
    | SetRequirement(_)
    | ValuesRequirement(_)
    | MatchRequirement(_)
    | SubgraphRequirement(_)
    | PropertyEqualityRequirement(_)
    | SelectorRequirement(_)
    | ConstructionRequirement(_)
    | VectorRequirement(_)
    | NearestRequirement(_)
    | PoolRequirement(_)
    | RankingRequirement(_)
    | TextRankRequirement(_) => None
  }
}
