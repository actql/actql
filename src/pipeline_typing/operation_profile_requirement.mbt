///|
/// Profile discharge is separate from value, resource, order and binding checks.
/// None means not a profile requirement, never permission to defer it to runtime.
pub fn operation_profile_requirement(
  v : OperationObligation,
) -> OperationProfile? {
  match v {
    MatchRequirement(o) =>
      match o {
        ResolveGraphMatchProfile => Some(Graph)
        AdmitMatchGraphData
        | ValidateSelectedIdentityMembership
        | FilterSelectedEdgeTypes
        | EvaluateMatchPredicate
        | CanonicalMatchOrder
        | ResolveMatchResources => None
      }
    DiagnosticRequirement(o) =>
      match o {
        AdmitDiagnosticGraph => Some(Graph)
        ResolveDiagnosticResources
        | EnforceDiagnosticRelationRows
        | BindDiagnosticThreshold(_) => None
      }
    PropertyEqualityRequirement(o) =>
      match o {
        AdmitBothGraphs => Some(Graph)
        CompareCompleteGraphValues | ResolvePropertyEqualityResources => None
      }
    NormalizeRequirement(o) =>
      match o {
        AdmitNormalizeGraph => Some(Graph)
        ResolveNormalizeResources => None
      }
    DeltaRequirement(o) =>
      match o {
        AdmitDeltaGraphs => Some(Graph)
        ResolveDeltaResources
        | EnforceDeltaRelationRows
        | AdmitExactlyOneDeltaRow
        | AdmitDeltaActions
        | VerifyDeltaBaseBeforeTarget => None
      }
    SubtractionRequirement(o) =>
      match o {
        AdmitSubtractionInputs => Some(Graph)
        PreserveSubtractionIdentities
        | CheckSubtractionEdgeEndpoints
        | ApplySubtractionPropertyStrategies
        | InduceSubtractionEndpoints
        | CanonicalSubtractionOrder
        | ResolveSubtractionResources => None
      }
    UnionRequirement(o) =>
      match o {
        AdmitUnionInputs => Some(Graph)
        PreserveUnionIdentities
        | CheckUnionEdgeEndpoints
        | ApplyUnionPropertyStrategies
        | CanonicalUnionOrder
        | ResolveUnionResources => None
      }
    ComponentsRequirement(o) =>
      match o {
        AdmitComponentGraph => Some(Graph)
        EnforceComponentInputNodes
        | ResolveComponentResources
        | EnforceComponentOutputRows
        | EnforceComponentAuthorGuard
        | BindComponentAuthorGuard(_) => None
      }
    SubgraphRequirement(o) =>
      match o {
        ResolveSubgraphProfile => Some(Graph)
        AdmitSubgraphInput
        | InduceSelectedEndpoints
        | FilterInducedEdges
        | PreserveSubgraphIdentitiesAndProperties
        | PreserveSubgraphPolicyAndScope
        | ResolveSubgraphResources => None
      }
    TraverseRequirement(o) =>
      match o {
        ResolveGraphTraversalProfile => Some(Graph)
        AdmitTraversalGraph
        | RespectTraversalHopBounds
        | FilterTraversalLabels
        | EnumeratePropertyPaths
        | DeduplicateExactPaths
        | MinimumEligibleNodeDepth
        | CanonicalTraversalOrder
        | EnforceTraversalOutputGuard
        | BindTraversalOutputGuard(_, ..)
        | ResolveTraversalResources => None
      }
    ConstructionRequirement(o) =>
      match o {
        ResolveGraphProfile => Some(Graph)
        AdmitGraphInputRows
        | RejectDuplicateDefinitionKeys
        | ExcludeNullKeysAndMissingEndpoints
        | ResolveGraphConstructionResources => None
      }
    VectorRequirement(o) =>
      match o {
        ResolveVecaProfile => Some(VecA)
        ValidateVectorValues
        | ValidateUniqueIdentities
        | ResolveVectorResources
        | NormalizeArithmetic
        | ScoreArithmetic
        | ScoreOrder
        | BindQuery(_, ..)
        | MatchDimensions => None
      }
    NearestRequirement(o) =>
      match o {
        ResolveNearestProfile => Some(VecA)
        ValidateNearestRoleBindings(_, ..)
        | MatchNearestDimensions
        | AdmitQuantizedVectorComponents
        | ValidateBothUniqueIdentities
        | EvaluateExactNearestScores
        | RestoreSemanticIdentityValues
        | OrderQueriesByIdentity
        | OrderCandidatesByDescendingScoreThenIdentity
        | AssignContiguousOneBasedRanks
        | JournalVectorFieldCompletion(_, ..)
        | JournalIdentityFieldCompletion(_, ..)
        | ValidateNearestKey(_, ..)
        | ResolveNearestResources
        | PreserveSimilarityAuthorityBoundary => None
      }
    PoolRequirement(o) =>
      match o {
        ResolvePoolProfile => Some(VecA)
        ValidateDeclaredPoolKey(_, ..)
        | JournalPoolMemberIdentity
        | EncodePoolMemberKeyByScalarLengths
        | OrderPoolMembersByEncodedIdentity
        | AdmitPoolVectorComponents
        | ValidatePoolMemberIdentityGlobally
        | MatchPoolDimensions
        | OrderPoolMembersByIdentity
        | QuantizeBeforeAndAfterPoolFold
        | EvaluateDeterministicPoolFold
        | OrderPoolGroupsByIdentity
        | ValidatePositiveSafeMemberCounts
        | ResolvePoolResources => None
      }
    RankingRequirement(o) =>
      match o {
        ResolveRankingProfile => Some(VecA)
        ValidateCompleteRankingInputs
        | ValidateUniqueQueryCandidatePerInput
        | ValidatePositiveSafeContiguousRanks
        | AuthenticateCapturedScoreDeclarations
        | ValidateDeclaredScoreRanges
        | ValidateBusinessTieAgreement
        | ApplyRankWindowAfterAdmission
        | EvaluateRankingPolicyWithFiniteIntermediates
        | OrderRankingByScoreAndSemanticIdentity
        | AssignFusedContiguousRanks
        | ResolveRankingResources
        | DeriveOutputScoreEnvelope => None
      }
    TextRankRequirement(o) =>
      match o {
        ResolveTextRankProfile => Some(TextRankProfile)
        ValidateCompleteTextInputs
        | ValidateGlobalStringIdentities(_, ..)
        | NormalizeAndTokenizeWithPinnedUnicode
        | ResolveTokenizerAndNormalizedTextCeilings
        | ComputeStatisticsFromAdmittedCorpusOnly
        | EvaluatePinnedBm25AndCorrectlyRoundedLogarithm
        | FoldTermsInCanonicalOrder
        | RejectNonFiniteTextScores
        | ExcludeZeroScoresAndHandleEmptyInputs
        | OrderTextScoresAndSemanticIdentities
        | AssignContiguousTextRanks
        | ResolveStatisticsScoringAndOutputResources => None
      }
    EventRequirement(o) =>
      match o {
        ResolveTeaProfile => Some(TEA)
        ValidateEventValues
        | ValidateUniqueIdentities
        | ResolveEventResources
        | WatermarkClassification
        | ConvertTimestampClock
        | FailOnTopTie
        | BindGap(_, ..)
        | SessionArithmetic
        | SessionIdentity => None
      }
    SequenceRequirement(o) =>
      match o {
        TeaProfile => Some(TEA)
        ValidateEventValues
        | UniqueEventIdentity
        | AscendingEventOrder
        | BoundedMatchSearch
        | AtomicMatchLimits
        | BindWithin(_, ..) => None
      }
    JoinRequirement(o)
    | CrossJoinRequirement(o)
    | IntervalJoinRequirement(o)
    | AsOfRequirement(o) =>
      match o {
        ResolveTeaProfile => Some(TEA)
        ResolveCardinality
        | ResolveOutputLimit
        | PreserveRowOrder
        | StableIdentity(_, ..)
        | ValidateCardinality(_, ..)
        | RejectNullKeys
        | BindGuard(_, ..)
        | ValidateExactlyOneRightRow
        | ResolveProductBound
        | PreserveLeftMajorProductOrder
        | ValidateIntervalEndpoints
        | ValidateSafeIntegerClocks
        | ResolveSearchWork
        | ValidateAsOfValues
        | ResolveAsOfOrder
        | RejectAsOfTies
        | JournalAsOfKeyCompletion(_, ..)
        | ValidateAsOfKey(_, ..)
        | BindTolerance(_, ..) => None
      }
    RelationRequirement(_)
    | SequenceRowsRequirement(_)
    | AppendRequirement(_)
    | NestRequirement(_)
    | SetRequirement(_)
    | ValuesRequirement(_)
    | SeriesRequirement(_)
    | CalendarRequirement(_)
    | WindowRequirement(_)
    | SelectorRequirement(_) => None
  }
}
