///|
/// Extent whose coverage is required, not a claim of completed observation.
pub(all) enum CompletenessScope {
  InputExtent
  OperationResult
  BoundedQuery
  WindowResult
} derive(Eq, Debug)

///|
/// Owned static requirement. Runtime coverage is admitted at acquisition and
/// publication boundaries; this view cannot manufacture that evidence.
struct CompletenessRequirement {
  pipeline : CheckedPipeline
  target : Target
}

///|
pub(all) enum CompletenessDependencyRole {
  Operand(InputRole)
  ImportedProducer
} derive(Eq, Debug)

///|
pub struct CompletenessDependency {
  role : CompletenessDependencyRole
  requirement : CompletenessRequirement
  projection : @relation.CheckedOperation?
}

///|
pub fn completeness_requirement(
  pipeline : CheckedPipeline,
  target : Target,
) -> CompletenessRequirement? {
  guard carrier_at(pipeline, target) is Some(_) else { return None }
  Some({ pipeline, target, })
}

///|
pub fn completeness_pipeline(v : CompletenessRequirement) -> CheckedPipeline {
  v.pipeline
}

///|
pub fn completeness_target(v : CompletenessRequirement) -> Target {
  v.target
}

///|
pub fn completeness_belongs_to(
  v : CompletenessRequirement,
  pipeline : CheckedPipeline,
  target : Target,
) -> Bool {
  physical_equal(v.pipeline, pipeline) && v.target == target
}

///|
pub fn completeness_scope(v : CompletenessRequirement) -> CompletenessScope {
  match v.target {
    Input(_) => InputExtent
    Step(i) =>
      match v.pipeline.steps[i].operation {
        Unary(op) =>
          match @relation.operation(op) {
            Take | TopK | TopKBy => BoundedQuery
            Derive
            | Filter
            | Select
            | Rename
            | Drop
            | Sort
            | Distinct
            | DedupeRows
            | AssertRows
            | Group
            | Pivot
            | Unpivot
            | Unnest
            | Lag
            | Analytic
            | JsonPick
            | WatermarkRows => OperationResult
          }
        Window(_) | WindowGroup(_) => WindowResult
        Infer(_)
        | Join(..)
        | Append(..)
        | Nest(..)
        | Set(..)
        | CrossJoin(..)
        | IntervalJoin(..)
        | AsOfJoin(..)
        | Sequence(_)
        | Values(_)
        | TimeSeries(_)
        | Calendar(_)
        | Projection(_)
        | Graph(_)
        | GraphMatch(_)
        | Subgraph(..)
        | Traverse(..)
        | Shortest(..)
        | PropertyGraphConstruction(..)
        | Vector(_)
        | Nearest(..)
        | Pool(_)
        | Ranking(_)
        | TextRank(..)
        | Event(_) => OperationResult
      }
  }
}

///|
/// Direct edges only: no recursive walk, copied table or proof discharge.
pub fn completeness_dependency_count(v : CompletenessRequirement) -> Int {
  match v.target {
    Step(i) => input_occurrence_count(v.pipeline.steps[i])
    Input(i) => if v.pipeline.produced_inputs[i] is Some(_) { 1 } else { 0 }
  }
}

///|
/// Every typed operand occurrence remains a coverage dependency, including
/// right-side absence/membership inputs and repeated references.
pub fn completeness_dependency_at(
  v : CompletenessRequirement,
  index : Int,
) -> CompletenessDependency? {
  match v.target {
    Step(i) =>
      input_occurrence_at(v.pipeline.steps[i], index).map(edge => {
        role: Operand(edge.role),
        requirement: { pipeline: v.pipeline, target: edge.target, },
        projection: None,
      })
    Input(i) => {
      guard index == 0 && v.pipeline.produced_inputs[i] is Some(producer) else {
        return None
      }
      Some({
        role: ImportedProducer,
        requirement: { pipeline: producer.pipeline, target: producer.target, },
        projection: producer.projection,
      })
    }
  }
}
