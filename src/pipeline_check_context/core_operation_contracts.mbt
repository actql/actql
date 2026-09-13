///|
// A closed disposition, not an inference from output Carrier or a claim that
// the complete operation semantics have been selected. ClassificationOnly
// retains the common transfer root but adds no quantity-specific body here.
priv enum OperationCountContract {
  Values
  Relation
  Join
  Window
  Graph
  Ranking
  Series
  ClassificationOnly
}

///|
// No wildcard: a new checked operation or projection variant must choose its
// contract-selection disposition rather than silently becoming a leaf.
fn operation_count_contract(
  operation : @pipeline.CheckedOperation,
) -> OperationCountContract {
  match operation {
    @pipeline.Values(_) => Values
    @pipeline.Unary(_)
    | @pipeline.WindowGroup(_)
    | @pipeline.Append(..)
    | @pipeline.Nest(..)
    | @pipeline.Set(..) => Relation
    @pipeline.Join(..)
    | @pipeline.CrossJoin(..)
    | @pipeline.IntervalJoin(..)
    | @pipeline.AsOfJoin(..) => Join
    @pipeline.Window(_) => Window
    @pipeline.Graph(_)
    | @pipeline.GraphMatch(_)
    | @pipeline.Subgraph(..)
    | @pipeline.Traverse(..)
    | @pipeline.Shortest(..)
    | @pipeline.GraphStructural(..)
    | @pipeline.GraphUnion(_)
    | @pipeline.GraphConstruction(..) => Graph
    @pipeline.Projection(v) =>
      match @projection.operation(v) {
        @projection.NodeRows | @projection.EdgeRows => Graph
        @projection.Events | @projection.Vectors => ClassificationOnly
      }
    @pipeline.Nearest(..) | @pipeline.Ranking(_) | @pipeline.TextRank(..) =>
      Ranking
    @pipeline.TimeSeries(_) | @pipeline.Calendar(_) => Series
    @pipeline.Sequence(_)
    | @pipeline.Reach(_)
    | @pipeline.GraphEquality(..)
    | @pipeline.GraphDiff(..)
    | @pipeline.GraphApply(..)
    | @pipeline.GraphMean(_)
    | @pipeline.Vector(_)
    | @pipeline.Pool(_)
    | @pipeline.Event(_) => ClassificationOnly
  }
}

///|
fn core_operation_count_root(
  b : CoreContractBuilder,
  operation : @pipeline.CheckedOperation,
  stage : Int,
  visit : Int,
  step : Int,
) -> Unit raise CoreContractStop {
  let (site, body) = match operation_count_contract(operation) {
    Values => {
      core_contract_root(
        b,
        OperationValuesWireLaw(stage, visit, step),
        ValuesWireLaw,
      )
      core_contract_root(
        b,
        OperationValuesExecutionRules(stage, visit, step),
        ValuesExecutionRules,
      )
      (OperationCountLaw(stage, visit, step), ValuesCountLaw)
    }
    Relation =>
      (OperationRelationCountRules(stage, visit, step), RelationCountRules)
    Join => {
      if operation is @pipeline.IntervalJoin(..) {
        core_contract_root(
          b,
          OperationIntervalSearchRules(stage, visit, step),
          IntervalSearchRules,
        )
      }
      if operation is @pipeline.AsOfJoin(..) {
        core_contract_root(
          b,
          OperationAsOfSearchRules(stage, visit, step),
          AsOfSearchRules,
        )
      }
      (OperationJoinCountRules(stage, visit, step), JoinCountRules)
    }
    Window => (OperationWindowCountRules(stage, visit, step), WindowCountRules)
    Graph => (OperationGraphCountRules(stage, visit, step), GraphCountRules)
    Ranking =>
      (OperationRankingCountRules(stage, visit, step), RankingCountRules)
    Series => (OperationSeriesCountRules(stage, visit, step), SeriesCountRules)
    ClassificationOnly => return
  }
  core_contract_root(b, site, body)
}
