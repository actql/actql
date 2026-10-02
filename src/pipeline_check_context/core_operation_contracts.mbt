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
  PropertyGraph
  Ranking
  Series
  ClassificationOnly
  Acquisition
}

///|
// No wildcard: a new checked operation or projection variant must choose its
// contract-selection disposition rather than silently becoming a leaf.
fn operation_count_contract(
  operation : @pipeline.CheckedOperation,
) -> OperationCountContract {
  match operation {
    @pipeline.Infer(_) => Acquisition
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
    @pipeline.Graph(_) => Graph
    @pipeline.PropertyGraphConstruction(..) => PropertyGraph
    @pipeline.GraphMatch(checked) =>
      if @graph.match_property_definition(checked) is Some(_) {
        PropertyGraph
      } else {
        Graph
      }
    @pipeline.Traverse(checked~, ..) =>
      if @graph.traverse_property_path_mode(checked) is Some(_) {
        PropertyGraph
      } else {
        Graph
      }
    @pipeline.Projection(v) =>
      match @projection.operation(v) {
        @projection.NodeRows | @projection.EdgeRows => Graph
        @projection.Events | @projection.Vectors => ClassificationOnly
      }
    @pipeline.Nearest(..) | @pipeline.Ranking(_) | @pipeline.TextRank(..) =>
      Ranking
    @pipeline.TimeSeries(_) | @pipeline.Calendar(_) => Series
    @pipeline.Sequence(_)
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
    Acquisition => {
      guard operation is @pipeline.Infer(infer) else {
        raise CoreContractStop(UnclosedModelAcquisition(stage, step))
      }
      let task = @evidence.infer_model_task(infer)
      let (_, _, task_cid) = @environment.model_task_identity(task)
      let (input_cid, output_cid) = @environment.model_task_schema_cids(task)
      // Keep each dependency role as an occurrence, even when bodies share a
      // CID. Selection retains identity; it does not authorize model egress.
      let pins = [
        task_cid,
        input_cid,
        output_cid,
        @environment.model_task_prompt_cid(task),
        @environment.model_task_data_handling_cid(task),
      ]
      let parent = ModelAcquisitionContract(task_cid)
      for role, cid in pins {
        let body = ModelAcquisitionContract(cid)
        core_contract_root(
          b,
          OperationModelContract(stage, visit, step, role),
          body,
        )
        if role != 0 {
          core_contract_edge(b)
          core_contract_dependency(b, parent, body)
        }
      }
      return
    }
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
    // The multi-definition keyed sum is in the distinct adopted contract,
    // not the legacy two-operand/derived-endpoint Graph count body.
    PropertyGraph =>
      (OperationGraphCountRules(stage, visit, step), PropertyGraphCountRules)
    Ranking =>
      (OperationRankingCountRules(stage, visit, step), RankingCountRules)
    Series => (OperationSeriesCountRules(stage, visit, step), SeriesCountRules)
    ClassificationOnly => return
  }
  core_contract_root(b, site, body)
}
