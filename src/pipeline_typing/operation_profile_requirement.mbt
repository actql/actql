///|
/// Profile discharge is separate from value, resource, order and binding checks.
/// None means not a profile requirement, never permission to defer it to runtime.
pub fn operation_profile_requirement(
  v : OperationObligation,
) -> OperationProfile? {
  match v {
    GraphRequirement(o) =>
      match o {
        ResolveSgaProfile => Some(SGA)
        ValidateGraphData
        | ResolveGraphResources
        | ComponentIdentityOrder
        | BindPositiveCount(_, ..)
        | BindNonnegativeCount(_, ..)
        | BoundsReportOrder
        | EnforceOutputGuard => None
      }
    MatchRequirement(o) =>
      match o {
        ResolveMatchProfile => Some(SGA)
        ResolvePropertyGraphMatchProfile => Some(PropertyGraph)
        AdmitMatchGraphData
        | ValidateSelectedIdentityMembership
        | FilterSelectedEdgeTypes
        | EvaluateMatchPredicate
        | CanonicalMatchOrder
        | ResolveMatchResources => None
      }
    ReachRequirement(o) =>
      match o {
        ResolveReachProfile => Some(SGA)
        AdmitReachGraph
        | RequireReachStartMembership
        | JournalReachExpansion
        | BoundedMinimumDepthTraversal
        | CanonicalReachOrder
        | ResolveReachResources => None
      }
    SubgraphRequirement(o) =>
      match o {
        ResolveSubgraphProfile => Some(SGA)
        AdmitSubgraphInput
        | InduceSelectedEndpoints
        | FilterInducedEdges
        | PreserveSubgraphIdentitiesAndProperties
        | PreserveSubgraphPolicyAndScope
        | ResolveSubgraphResources => None
      }
    TraverseRequirement(o) =>
      match o {
        ResolveTraversalProfile => Some(SGA)
        ResolvePropertyGraphTraversalProfile => Some(PropertyGraph)
        AdmitTraversalGraph
        | RespectTraversalHopBounds
        | EvaluateTraversalHopPredicates
        | EmitMinimumNodeDepth
        | EnumerateSimplePaths
        | EnumeratePropertyPaths
        | DeduplicateExactPaths
        | CanonicalTraversalOrder
        | EnforceTraversalOutputGuard
        | BindTraversalOutputGuard(_, ..)
        | ResolveTraversalResources => None
      }
    ShortestRequirement(o) =>
      match o {
        ResolveShortestProfile => Some(SGA)
        AdmitShortestGraph
        | RequireEndpointMembership
        | ValidateAllNonnegativeFiniteWeights
        | FoldPathCostsWithOverrange
        | RejectSelectedOverrangeAtomically
        | SelectSimpleHopBoundedPaths
        | ApplyCanonicalPathTieBreaks
        | CanonicalShortestOutputOrder
        | EnforceShortestOutputGuard
        | BindShortestOutputGuard(_, ..)
        | ResolveShortestResources => None
      }
    EqualityRequirement(o) =>
      match o {
        ResolveSgaProfile => Some(SGA)
        AdmitBothGraphs
        | CompareTypedCanonicalGraphs
        | ResolveComparisonResources => None
      }
    DiffRequirement(o) =>
      match o {
        ResolveSgaProfile => Some(SGA)
        EmitDeltaVersion
        | AdmitSnapshotsUnderCommonContract
        | EmitGraphContractIdentity
        | BindBaseAndTargetIdentities
        | EmitCompleteBeforeAfterRecords
        | SortUniqueActionIdentities
        | ResolveDeltaResources => None
      }
    ApplyRequirement(o) =>
      match o {
        ResolveSgaProfile => Some(SGA)
        RequireExactlyOneDeltaRow
        | ValidateDeltaVersionAndClosedShape
        | MatchPinnedGraphContract
        | AdmitBaseUnderPinnedContract
        | MatchExactBaseIdentity
        | ValidateOrderedUniqueActions
        | ValidateExactBeforeRecords
        | ValidateAddRemoveUpdateExistence
        | ApplyNodeAndEdgeChangesTogether
        | ValidateResultEndpointsAndContract
        | MatchExactTargetIdentity
        | PreserveGraphPolicyDependencies
        | ResolveApplyResources => None
      }
    StructuralRequirement(o) =>
      match o {
        ResolveSgaProfile => Some(SGA)
        AdmitGraphsUnderCommonContract
        | CompareCompleteIdentityPayloads
        | RejectUnspecifiedConflicts
        | ApplyEveryAuthoredStrategy
        | KeepCompleteOneSidedUnionRecords
        | KeepOnlyLeftSubtractionRecords
        | CloseSubtractionEndpoints
        | ValidateCanonicalSetOperations
        | ValidateFiniteNumericResults
        | PreservePolicyDependencies
        | ResolveStructuralResources => None
      }
    MeanRequirement(o) =>
      match o {
        ResolveMeanProfile => Some(SGA)
        AdmitEveryMeanSample
        | CompareExactRationalSupport
        | RetainSupportedNodesBeforeEdges
        | RequirePositiveWeightLabelAgreement
        | ApplyEveryMeanPropertyPolicy
        | RoundExactWeightedMeansOnce
        | RejectNonfiniteMeanResults
        | CanonicalMeanIdentityOrder
        | PreserveMeanObservationAndPolicy
        | ResolveMeanResources => None
      }
    ConstructionRequirement(o) =>
      match o {
        ResolveSgaProfile => Some(SGA)
        ResolvePropertyGraphProfile => Some(PropertyGraph)
        AdmitGraphInputRows
        | CloseBothEndpointsAgainstDeclaredNodes
        | DeriveDistinctEndpointNodes
        | JournalEndpointCompletion
        | JournalLabelCompletion
        | CollapseEqualIdentityPayloads
        | RejectConflictingIdentityPayloads
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
    | ProjectionRequirement(_)
    | SelectorRequirement(_) => None
  }
}
