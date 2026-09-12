///|
/// Preparation is not an executable fragment: expression lowering, parameter
/// binding and operation-parameter admission still have to succeed.
struct Prepared {
  owner : @pipeline.CheckedPipeline
  nodes : Array[PreparedNode]
  input_ids : Array[String]
  usage : Usage
}

///|
struct PreparedNode {
  id : String
  payload : Payload
  inputs : Array[String]
  source : @decode.Cursor
}

///|
/// Retain checked payloads rather than reinterpreting source JSON. These are
/// not a second semantic IR, and must not be passed to an execution engine.
pub enum Payload {
  Values(@values.CheckedValues)
  Derive(@relation.CheckedOperation)
  Where(@relation.CheckedOperation)
  Select(@relation.CheckedOperation)
  Limit(@relation.CheckedOperation)
  Distinct(@relation.CheckedOperation)
}

///|
pub(all) struct Limits {
  max_nodes : Int
  max_references : Int
  max_work : Int
  max_identifier_bytes : Int
} derive(Eq, Debug)

///|
pub(all) struct Usage {
  nodes : Int
  references : Int
  work : Int
  identifier_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  OperationNotImplemented
  InvalidCheckedWiring
  IdentifierCollision
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
}

///|
pub fn pipeline(value : Prepared) -> @pipeline.CheckedPipeline {
  value.owner
}

///|
pub fn usage(value : Prepared) -> Usage {
  value.usage
}

///|
pub fn node_count(value : Prepared) -> Int {
  value.nodes.length()
}

///|
pub fn node_at(value : Prepared, index : Int) -> PreparedNode? {
  value.nodes.get(index)
}

///|
pub fn node_id(value : PreparedNode) -> String {
  value.id
}

///|
pub fn payload(value : PreparedNode) -> Payload {
  value.payload
}

///|
pub fn source(value : PreparedNode) -> @decode.Cursor {
  value.source
}

///|
pub fn input_ids(value : PreparedNode) -> Array[String] {
  value.inputs.copy()
}

///|
pub fn input_id(value : Prepared, index : Int) -> String? {
  value.input_ids.get(index)
}

///|
pub fn operation(value : PreparedNode) -> String {
  match value.payload {
    Values(_) => "REL.values"
    Derive(_) => "REL.derive"
    Where(_) => "REL.where"
    Select(_) => "REL.select"
    Limit(_) => "REL.limit"
    Distinct(_) => "REL.distinct"
  }
}

///|
fn classify(op : @pipeline.CheckedOperation) -> Payload? {
  match op {
    Values(v) => Some(Values(v))
    Unary(v) =>
      match @relation.operation(v) {
        Derive => Some(Derive(v))
        Filter => Some(Where(v))
        Select | Rename | Drop => Some(Select(v))
        Take => Some(Limit(v))
        Distinct =>
          if @relation.row_operation(v) is Some(@relation.DistinctRows) {
            Some(Distinct(v))
          } else {
            None
          }
        Sort
        | DedupeRows
        | JsonPick
        | Unnest
        | AssertRows
        | Unpivot
        | Group
        | Pivot
        | Analytic
        | TopK
        | TopKBy
        | Lag
        | WatermarkRows => None
      }
    Join(..)
    | Append(..)
    | Nest(..)
    | Set(..)
    | CrossJoin(..)
    | IntervalJoin(..)
    | AsOfJoin(..)
    | Sequence(_)
    | TimeSeries(_)
    | Calendar(_)
    | Window(_)
    | Projection(_)
    | Graph(_)
    | GraphMatch(_)
    | Reach(_)
    | Subgraph(..)
    | Traverse(..)
    | Shortest(..)
    | GraphEquality(..)
    | GraphDiff(..)
    | GraphApply(..)
    | GraphStructural(..)
    | GraphUnion(_)
    | GraphMean(_)
    | GraphConstruction(..)
    | Vector(_)
    | Nearest(..)
    | Pool(_)
    | Ranking(_)
    | TextRank(..)
    | Event(_)
    | WindowGroup(_) => None
  }
}

///|
pub fn prepare(
  checked : @pipeline.CheckedPipeline,
  limits : Limits,
) -> Result[Prepared, Issue] {
  let root = @pipeline.source(checked)
  if limits.max_nodes < 0 ||
    limits.max_references < 0 ||
    limits.max_work < 0 ||
    limits.max_identifier_bytes < 0 {
    return Err({ kind: InvalidLimits, source: root, })
  }
  let count = @pipeline.step_count(checked)
  let inputs = @pipeline.input_count(checked)
  if count > limits.max_nodes || inputs > limits.max_nodes - count {
    return Err({ kind: BudgetExceeded, source: root, })
  }
  let nodes : Array[PreparedNode] = []
  let input_ids : Array[String] = []
  let used : Map[String, Bool] = Map([])
  let mut work = 0
  let mut references = 0
  let mut bytes = 0
  for i = 0; i < inputs; i = i + 1 {
    if work >= limits.max_work {
      return Err({ kind: BudgetExceeded, source: root, })
    }
    work += 1
    let id = "input_" + i.to_string()
    if id.length() > limits.max_identifier_bytes - bytes {
      return Err({ kind: BudgetExceeded, source: root, })
    }
    bytes += id.length() // Generated identifiers are ASCII, on every target.
    used[id] = true
    input_ids.push(id)
  }
  for i = 0; i < count; i = i + 1 {
    if work >= limits.max_work {
      return Err({ kind: BudgetExceeded, source: root, })
    }
    work += 1
    guard @pipeline.step_at(checked, i) is Some(step) else {
      return Err({ kind: InvalidCheckedWiring, source: root, })
    }
    guard classify(step.operation) is Some(payload) else {
      return Err({ kind: OperationNotImplemented, source: step.source, })
    }
    if @pipeline.step_schema(step) is None {
      return Err({ kind: InvalidCheckedWiring, source: step.source, })
    }
    let (preferred, arity) = match payload {
      Values(_) => ("values", 0)
      Derive(_) => ("derive", 1)
      Where(_) => ("where", 1)
      Select(_) => ("select", 1)
      Limit(_) => ("limit", 1)
      Distinct(_) => ("distinct", 1)
    }
    let id = preferred + "_" + i.to_string()
    if used.contains(id) {
      return Err({ kind: IdentifierCollision, source: step.source, })
    }
    if id.length() > limits.max_identifier_bytes - bytes {
      return Err({ kind: BudgetExceeded, source: step.source, })
    }
    bytes += id.length()
    let refs : Array[String] = []
    let occurrences = @pipeline.input_occurrence_count(step)
    if occurrences != arity {
      return Err({ kind: InvalidCheckedWiring, source: step.source, })
    }
    for j = 0; j < occurrences; j = j + 1 {
      if work >= limits.max_work || references >= limits.max_references {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      work += 1
      references += 1
      guard @pipeline.input_occurrence_at(step, j) is Some(occurrence) else {
        return Err({ kind: InvalidCheckedWiring, source: step.source, })
      }
      if @pipeline.schema_at(checked, occurrence.target) is None {
        return Err({ kind: InvalidCheckedWiring, source: step.source, })
      }
      let resolved = match occurrence.target {
        Input(index) => input_ids.get(index)
        Step(index) => nodes.get(index).map(node => node.id)
      }
      guard resolved is Some(ref_) else {
        return Err({ kind: InvalidCheckedWiring, source: step.source, })
      }
      refs.push(ref_)
    }
    used[id] = true
    nodes.push({ id, payload, inputs: refs, source: step.source, })
  }
  Ok({
    owner: checked,
    nodes,
    input_ids,
    usage: { nodes: count + inputs, references, work, identifier_bytes: bytes, },
  })
}
