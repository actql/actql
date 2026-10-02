///|
/// The local owner of an obligation group, not a persistent identity or proof.
pub(all) enum OperationObligationScope {
  Body
  SequenceRows
  SequenceSemantics
  UnionFold(Int)
  NodeSelector
  StartSelector
  SourceSelector
  TargetSelector
} derive(Eq, Debug)

///|
/// Typed requirements remain separate from their resolution or runtime enforcement.
pub(all) enum OperationObligation {
  RelationRequirement(@relation.PendingValidation)
  JoinRequirement(@join.Obligation)
  AppendRequirement(@append.Obligation)
  NestRequirement(@nest.Obligation)
  SetRequirement(@set.Obligation)
  CrossJoinRequirement(@join.Obligation)
  IntervalJoinRequirement(@join.Obligation)
  AsOfRequirement(@join.Obligation)
  SequenceRowsRequirement(@relation.PendingValidation)
  SequenceRequirement(@relation.SequenceObligation)
  ValuesRequirement(@values.Obligation)
  SeriesRequirement(@series.Obligation)
  CalendarRequirement(@calendar.Obligation)
  WindowRequirement(@window.Obligation)
  ProjectionRequirement(@projection.GraphObligation)
  GraphRequirement(@graph.Obligation)
  MatchRequirement(@graph.MatchObligation)
  ReachRequirement(@graph.ReachObligation)
  SubgraphRequirement(@graph.SubgraphObligation)
  TraverseRequirement(@graph.TraverseObligation)
  ShortestRequirement(@graph.ShortestObligation)
  SelectorRequirement(@graph.SelectorObligation)
  EqualityRequirement(@graph.EqualityObligation)
  DiffRequirement(@graph.DeltaObligation)
  ApplyRequirement(@graph.ApplyObligation)
  StructuralRequirement(@graph.StructuralObligation)
  MeanRequirement(@graph.MeanObligation)
  ConstructionRequirement(@graph.ConstructionObligation)
  VectorRequirement(@vector.Obligation)
  NearestRequirement(@vector.NearestObligation)
  PoolRequirement(@vector.PoolObligation)
  RankingRequirement(@vector.RankingObligation)
  TextRankRequirement(@vector.TextRankObligation)
  EventRequirement(@event.Obligation)
}

///|
priv enum ObligationOwner {
  RelationOwner(@relation.CheckedOperation)
  JoinOwner(@join.CheckedJoin)
  AppendOwner(@append.CheckedAppend)
  NestOwner(@nest.CheckedNest)
  SetOwner(@set.CheckedSet)
  CrossJoinOwner(@join.CheckedCrossJoin)
  IntervalJoinOwner(@join.CheckedIntervalJoin)
  AsOfOwner(@join.CheckedAsOf)
  SequenceRowsOwner(@relation.CheckedSequence)
  SequenceOwner(@relation.CheckedSequence)
  ValuesOwner(@values.CheckedValues)
  SeriesOwner(@series.CheckedSeries)
  CalendarOwner(@calendar.CheckedCalendar)
  WindowOwner(@window.CheckedWindow)
  ProjectionOwner(@projection.CheckedProjection)
  GraphOwner(@graph.CheckedGraph)
  MatchOwner(@graph.CheckedMatch)
  ReachOwner(@graph.CheckedReach)
  SubgraphOwner(@graph.CheckedSubgraph)
  TraverseOwner(@graph.CheckedTraverse)
  ShortestOwner(@graph.CheckedShortest)
  SelectorOwner(@graph.CheckedSelector)
  EqualityOwner(@graph.CheckedEquality)
  DiffOwner(@graph.CheckedDiff)
  ApplyOwner(@graph.CheckedApply)
  StructuralOwner(@graph.CheckedStructural)
  MeanOwner(@graph.CheckedMean)
  PropertyConstructionOwner(@graph.CheckedPropertyConstruction)
  VectorOwner(@vector.CheckedVector)
  NearestOwner(@vector.CheckedNearest)
  PoolOwner(@vector.CheckedPool)
  RankingOwner(@vector.CheckedRanking)
  TextRankOwner(@vector.CheckedTextRank)
  EventOwner(@event.CheckedEvent)
}

///|
struct OperationObligations {
  scope : OperationObligationScope
  owner : ObligationOwner
}

///|
pub fn operation_obligations_scope(
  v : OperationObligations,
) -> OperationObligationScope {
  v.scope
}

///|
/// Original source of this exact obligation owner, including selector and union
/// fold owners. Reading provenance does not resolve or discharge an obligation.
pub fn operation_obligations_source(v : OperationObligations) -> @decode.Cursor {
  match v.owner {
    RelationOwner(c) => @relation.source(c)
    JoinOwner(c) => @join.source(c)
    AppendOwner(c) => @append.source(c)
    NestOwner(c) => @nest.source(c)
    SetOwner(c) => @set.source(c)
    CrossJoinOwner(c) => @join.cross_source(c)
    IntervalJoinOwner(c) => @join.interval_source(c)
    AsOfOwner(c) => @join.asof_source(c)
    SequenceRowsOwner(c) | SequenceOwner(c) => @relation.sequence_source(c)
    ValuesOwner(c) => @values.source(c)
    SeriesOwner(c) => @series.source(c)
    CalendarOwner(c) => @calendar.source(c)
    WindowOwner(c) => @window.source(c)
    ProjectionOwner(c) => @projection.source(c)
    GraphOwner(c) => @graph.source(c)
    MatchOwner(c) => @graph.match_source(c)
    ReachOwner(c) => @graph.reach_source(c)
    SubgraphOwner(c) => @graph.subgraph_source(c)
    TraverseOwner(c) => @graph.traverse_source(c)
    ShortestOwner(c) => @graph.shortest_source(c)
    SelectorOwner(c) => @graph.selector_source(c)
    EqualityOwner(c) => @graph.equality_source(c)
    DiffOwner(c) => @graph.diff_source(c)
    ApplyOwner(c) => @graph.apply_source(c)
    StructuralOwner(c) => @graph.structural_source(c)
    MeanOwner(c) => @graph.mean_options_source(@graph.mean_options(c))
    PropertyConstructionOwner(c) => @graph.property_construction_source(c)
    VectorOwner(c) => @vector.source(c)
    NearestOwner(c) =>
      @vector.nearest_source(
        @vector.nearest_pair_options(@vector.nearest_pair(c)),
      )
    PoolOwner(c) => @vector.pool_source(@vector.pooled_options(c))
    RankingOwner(c) => @vector.ranking_source(@vector.merged_ranking_options(c))
    TextRankOwner(c) => @vector.text_rank_source(@vector.text_rank_options(c))
    EventOwner(c) => @event.source(c)
  }
}

///|
/// The retained requirement location when available, otherwise its owner's
/// body. Invalid indices return None, not the owner's location. No path copy,
/// reparse or requirement-array reconstruction is needed for this O(1) read.
pub fn operation_obligation_source_at(
  v : OperationObligations,
  index : Int,
) -> @decode.Cursor? {
  guard operation_obligations_at(v, index) is Some(requirement) else {
    return None
  }
  match requirement {
    RelationRequirement(pending) | SequenceRowsRequirement(pending) =>
      Some(pending.source)
    _ => Some(operation_obligations_source(v))
  }
}

///|
/// Returns the retained selector owner, without reconstructing its checked state.
pub fn operation_obligations_selector(
  v : OperationObligations,
) -> @graph.CheckedSelector? {
  match v.owner {
    SelectorOwner(selector) => Some(selector)
    _ => None
  }
}

///|
/// Retain the exact admitted keyed constructor, not a structurally equal body.
pub fn operation_obligations_property_construction(
  v : OperationObligations,
) -> @graph.CheckedPropertyConstruction? {
  match v.owner {
    PropertyConstructionOwner(construction) => Some(construction)
    _ => None
  }
}

///|
/// Retain the exact checked MATCH owner; equal text is not owner identity.
pub fn operation_obligations_match(
  v : OperationObligations,
) -> @graph.CheckedMatch? {
  match v.owner {
    MatchOwner(operation) => Some(operation)
    _ => None
  }
}

///|
/// O(1) reads; callers can charge before visiting or retaining each entry.
pub fn operation_obligations_count(v : OperationObligations) -> Int {
  match v.owner {
    RelationOwner(c) => @relation.pending_validation_count(c)
    JoinOwner(c) => @join.pending_validation_count(c)
    AppendOwner(c) => @append.pending_validation_count(c)
    NestOwner(c) => @nest.pending_validation_count(c)
    SetOwner(c) => @set.pending_validation_count(c)
    CrossJoinOwner(c) => @join.cross_pending_validation_count(c)
    IntervalJoinOwner(c) => @join.interval_pending_validation_count(c)
    AsOfOwner(c) => @join.asof_pending_validation_count(c)
    SequenceRowsOwner(c) => @relation.sequence_pending_validation_count(c)
    SequenceOwner(c) => @relation.sequence_obligation_count(c)
    ValuesOwner(c) => @values.pending_validation_count(c)
    SeriesOwner(c) => @series.pending_validation_count(c)
    CalendarOwner(c) => @calendar.pending_validation_count(c)
    WindowOwner(c) => @window.pending_validation_count(c)
    ProjectionOwner(c) => @projection.graph_pending_count(c)
    GraphOwner(c) => @graph.pending_validation_count(c)
    MatchOwner(c) => @graph.match_pending_count(c)
    ReachOwner(c) => @graph.reach_pending_count(c)
    SubgraphOwner(c) => @graph.subgraph_pending_count(c)
    TraverseOwner(c) => @graph.traverse_pending_count(c)
    ShortestOwner(c) => @graph.shortest_pending_count(c)
    SelectorOwner(c) => @graph.selector_pending_count(c)
    EqualityOwner(c) => @graph.equality_pending_count(c)
    DiffOwner(c) => @graph.diff_pending_count(c)
    ApplyOwner(c) => @graph.apply_pending_count(c)
    StructuralOwner(c) => @graph.structural_pending_count(c)
    MeanOwner(c) => @graph.mean_pending_count(c)
    PropertyConstructionOwner(c) =>
      @graph.property_construction_pending_count(c)
    VectorOwner(c) => @vector.pending_validation_count(c)
    NearestOwner(c) => @vector.nearest_pending_count(c)
    PoolOwner(c) => @vector.pool_pending_count(c)
    RankingOwner(c) => @vector.merged_ranking_pending_count(c)
    TextRankOwner(c) => @vector.text_rank_pending_count(c)
    EventOwner(c) => @event.pending_validation_count(c)
  }
}

///|
pub fn operation_obligations_at(
  v : OperationObligations,
  index : Int,
) -> OperationObligation? {
  match v.owner {
    RelationOwner(c) =>
      @relation.pending_validation_at(c, index).map(x => RelationRequirement(x))
    JoinOwner(c) =>
      @join.pending_validation_at(c, index).map(x => JoinRequirement(x))
    AppendOwner(c) =>
      @append.pending_validation_at(c, index).map(x => AppendRequirement(x))
    NestOwner(c) =>
      @nest.pending_validation_at(c, index).map(x => NestRequirement(x))
    SetOwner(c) =>
      @set.pending_validation_at(c, index).map(x => SetRequirement(x))
    CrossJoinOwner(c) =>
      @join.cross_pending_validation_at(c, index).map(x => {
        CrossJoinRequirement(x)
      })
    IntervalJoinOwner(c) =>
      @join.interval_pending_validation_at(c, index).map(x => {
        IntervalJoinRequirement(x)
      })
    AsOfOwner(c) =>
      @join.asof_pending_validation_at(c, index).map(x => AsOfRequirement(x))
    SequenceRowsOwner(c) =>
      @relation.sequence_pending_validation_at(c, index).map(x => {
        SequenceRowsRequirement(x)
      })
    SequenceOwner(c) =>
      @relation.sequence_obligation_at(c, index).map(x => SequenceRequirement(x))
    ValuesOwner(c) =>
      @values.pending_validation_at(c, index).map(x => ValuesRequirement(x))
    SeriesOwner(c) =>
      @series.pending_validation_at(c, index).map(x => SeriesRequirement(x))
    CalendarOwner(c) =>
      @calendar.pending_validation_at(c, index).map(x => CalendarRequirement(x))
    WindowOwner(c) =>
      @window.pending_validation_at(c, index).map(x => WindowRequirement(x))
    ProjectionOwner(c) =>
      @projection.graph_pending_at(c, index).map(x => ProjectionRequirement(x))
    GraphOwner(c) =>
      @graph.pending_validation_at(c, index).map(x => GraphRequirement(x))
    MatchOwner(c) =>
      @graph.match_pending_at(c, index).map(x => MatchRequirement(x))
    ReachOwner(c) =>
      @graph.reach_pending_at(c, index).map(x => ReachRequirement(x))
    SubgraphOwner(c) =>
      @graph.subgraph_pending_at(c, index).map(x => SubgraphRequirement(x))
    TraverseOwner(c) =>
      @graph.traverse_pending_at(c, index).map(x => TraverseRequirement(x))
    ShortestOwner(c) =>
      @graph.shortest_pending_at(c, index).map(x => ShortestRequirement(x))
    SelectorOwner(c) =>
      @graph.selector_pending_at(c, index).map(x => SelectorRequirement(x))
    EqualityOwner(c) =>
      @graph.equality_pending_at(c, index).map(x => EqualityRequirement(x))
    DiffOwner(c) =>
      @graph.diff_pending_at(c, index).map(x => DiffRequirement(x))
    ApplyOwner(c) =>
      @graph.apply_pending_at(c, index).map(x => ApplyRequirement(x))
    StructuralOwner(c) =>
      @graph.structural_pending_at(c, index).map(x => StructuralRequirement(x))
    MeanOwner(c) =>
      @graph.mean_pending_at(c, index).map(x => MeanRequirement(x))
    PropertyConstructionOwner(c) =>
      @graph.property_construction_pending_at(c, index).map(x => {
        ConstructionRequirement(x)
      })
    VectorOwner(c) =>
      @vector.pending_validation_at(c, index).map(x => VectorRequirement(x))
    NearestOwner(c) =>
      @vector.nearest_pending_at(c, index).map(x => NearestRequirement(x))
    PoolOwner(c) =>
      @vector.pool_pending_at(c, index).map(x => PoolRequirement(x))
    RankingOwner(c) =>
      @vector.merged_ranking_pending_at(c, index).map(x => RankingRequirement(x))
    TextRankOwner(c) =>
      @vector.text_rank_pending_at(c, index).map(x => TextRankRequirement(x))
    EventOwner(c) =>
      @event.pending_validation_at(c, index).map(x => EventRequirement(x))
  }
}

///|
/// No nested owner is flattened into an unbounded temporary array. A single
/// shortest endpoint has no selector group; selected endpoints retain their side.
pub fn operation_obligation_group_count(operation : CheckedOperation) -> Int {
  match operation {
    // Acquisition closure and call-slot preflight belong to the model owner,
    // not the pure operation obligation inventory.
    Infer(_) => 0
    Sequence(_) | Subgraph(..) | Traverse(..) => 2
    Shortest(checked~, ..) => {
      let mut n = 1
      if @graph.shortest_endpoint(checked, Left) is Selected(_) {
        n += 1
      }
      if @graph.shortest_endpoint(checked, Right) is Selected(_) {
        n += 1
      }
      n
    }
    GraphUnion(c) => @graph.union_count(c)
    Unary(_)
    | WindowGroup(_)
    | Join(checked=_, ..)
    | Append(checked=_, ..)
    | Nest(checked=_, ..)
    | Set(checked=_, ..)
    | CrossJoin(checked=_, ..)
    | IntervalJoin(checked=_, ..)
    | AsOfJoin(checked=_, ..)
    | Values(_)
    | TimeSeries(_)
    | Calendar(_)
    | Window(_)
    | Projection(_)
    | Graph(_)
    | GraphMatch(_)
    | Reach(_)
    | GraphEquality(checked=_, ..)
    | GraphDiff(checked=_, ..)
    | GraphApply(checked=_, ..)
    | GraphStructural(checked=_, ..)
    | GraphMean(_)
    | PropertyGraphConstruction(..)
    | Vector(_)
    | Nearest(checked=_, ..)
    | Pool(_)
    | Ranking(_)
    | TextRank(checked=_, ..)
    | Event(_) => 1
  }
}

///|
pub fn operation_obligation_group_at(
  operation : CheckedOperation,
  index : Int,
) -> OperationObligations? {
  if index < 0 || index >= operation_obligation_group_count(operation) {
    return None
  }
  Some(
    match operation {
      Infer(_) => return None
      Unary(c) | WindowGroup(c) => { scope: Body, owner: RelationOwner(c), }
      Join(checked=c, ..) => { scope: Body, owner: JoinOwner(c), }
      Append(checked=c, ..) => { scope: Body, owner: AppendOwner(c), }
      Nest(checked=c, ..) => { scope: Body, owner: NestOwner(c), }
      Set(checked=c, ..) => { scope: Body, owner: SetOwner(c), }
      CrossJoin(checked=c, ..) => { scope: Body, owner: CrossJoinOwner(c), }
      IntervalJoin(checked=c, ..) =>
        { scope: Body, owner: IntervalJoinOwner(c), }
      AsOfJoin(checked=c, ..) => { scope: Body, owner: AsOfOwner(c), }
      Values(c) => { scope: Body, owner: ValuesOwner(c), }
      TimeSeries(c) => { scope: Body, owner: SeriesOwner(c), }
      Calendar(c) => { scope: Body, owner: CalendarOwner(c), }
      Window(c) => { scope: Body, owner: WindowOwner(c), }
      Projection(c) => { scope: Body, owner: ProjectionOwner(c), }
      Graph(c) => { scope: Body, owner: GraphOwner(c), }
      GraphMatch(c) => { scope: Body, owner: MatchOwner(c), }
      Reach(c) => { scope: Body, owner: ReachOwner(c), }
      GraphEquality(checked=c, ..) => { scope: Body, owner: EqualityOwner(c), }
      GraphDiff(checked=c, ..) => { scope: Body, owner: DiffOwner(c), }
      GraphApply(checked=c, ..) => { scope: Body, owner: ApplyOwner(c), }
      GraphStructural(checked=c, ..) =>
        { scope: Body, owner: StructuralOwner(c), }
      GraphMean(c) => { scope: Body, owner: MeanOwner(c), }
      PropertyGraphConstruction(checked=c, ..) =>
        { scope: Body, owner: PropertyConstructionOwner(c), }
      Vector(c) => { scope: Body, owner: VectorOwner(c), }
      Nearest(checked=c, ..) => { scope: Body, owner: NearestOwner(c), }
      Pool(c) => { scope: Body, owner: PoolOwner(c), }
      Ranking(c) => { scope: Body, owner: RankingOwner(c), }
      TextRank(checked=c, ..) => { scope: Body, owner: TextRankOwner(c), }
      Event(c) => { scope: Body, owner: EventOwner(c), }
      Sequence(c) =>
        if index == 0 {
          { scope: SequenceRows, owner: SequenceRowsOwner(c), }
        } else {
          { scope: SequenceSemantics, owner: SequenceOwner(c), }
        }
      Subgraph(checked=c, ..) =>
        if index == 0 {
          { scope: Body, owner: SubgraphOwner(c), }
        } else {
          {
            scope: NodeSelector,
            owner: SelectorOwner(@graph.subgraph_nodes(c)),
          }
        }
      Traverse(checked=c, ..) =>
        if index == 0 {
          { scope: Body, owner: TraverseOwner(c), }
        } else {
          {
            scope: StartSelector,
            owner: SelectorOwner(@graph.traverse_start(c)),
          }
        }
      Shortest(checked=c, ..) =>
        if index == 0 {
          { scope: Body, owner: ShortestOwner(c), }
        } else {
          let left = @graph.shortest_endpoint(c, Left)
          let right = @graph.shortest_endpoint(c, Right)
          match (left, right, index) {
            (Selected(s), _, 1) =>
              { scope: SourceSelector, owner: SelectorOwner(s), }
            (_, Selected(s), _) =>
              { scope: TargetSelector, owner: SelectorOwner(s), }
            _ => return None
          }
        }
      GraphUnion(c) => {
        let fold = @graph.union_fold_at(c, index).unwrap()
        { scope: UnionFold(index), owner: StructuralOwner(fold), }
      }
    },
  )
}
