///|
/// Preparation is not an executable fragment: expression lowering, parameter
/// binding and operation-parameter admission still have to succeed.
struct Prepared {
  owner : @pipeline.CheckedPipeline
  nodes : Array[PreparedNode]
  input_ids : Array[String]
  input_schemas : Array[@schema.Schema]
  usage : Usage
}

///|
struct PreparedNode {
  id : String
  projection_id : String?
  order_id : String?
  aggregation_id : String?
  payload : Payload
  inputs : Array[String]
  input_targets : Array[@pipeline.Target]
  output_schema : @schema.Schema
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
  Dedupe(@relation.CheckedOperation)
  Sort(@relation.CheckedOperation)
  CountGroup(@relation.CheckedOperation)
  InnerJoin(@join.CheckedJoin)
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
/// Canonical keyed-distinct prefix, reserved by the same collision allocator.
pub fn projection_node_id(value : PreparedNode) -> String? {
  value.projection_id
}

///|
pub fn order_node_id(value : PreparedNode) -> String? {
  value.order_id
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
    Dedupe(_) => "REL.dedupeRows"
    Sort(_) => "REL.orderByStable"
    CountGroup(_) => "REL.groupBy"
    InnerJoin(_) => "REL.join"
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
        Distinct => Some(Distinct(v))
        DedupeRows => Some(Dedupe(v))
        Sort => Some(Sort(v))
        Group => Some(CountGroup(v))
        JsonPick
        | Unnest
        | AssertRows
        | Unpivot
        | Pivot
        | Analytic
        | TopK
        | TopKBy
        | Lag
        | WatermarkRows => None
      }
    Join(checked~, ..) =>
      if @join.kind(checked) == @join.Inner {
        Some(InnerJoin(checked))
      } else {
        None
      }
    Append(..)
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
  let input_schemas : Array[@schema.Schema] = []
  let used : Map[String, Bool] = Map([])
  let mut work = 0
  let mut references = 0
  let mut bytes = 0
  let mut expansions = 0
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
    guard @pipeline.schema_at(checked, @pipeline.Input(i)) is Some(schema) else {
      return Err({ kind: InvalidCheckedWiring, source: root, })
    }
    input_schemas.push(schema)
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
    guard @pipeline.step_schema(step) is Some(output_schema) else {
      return Err({ kind: InvalidCheckedWiring, source: step.source, })
    }
    let (preferred, arity) = match payload {
      Values(_) => ("values", 0)
      Derive(_) => ("derive", 1)
      Where(_) => ("where", 1)
      Select(_) => ("select", 1)
      Limit(_) => ("limit", 1)
      Distinct(_) => ("distinct", 1)
      Dedupe(_) => ("dedupe", 1)
      Sort(_) => ("sort", 1)
      CountGroup(_) => ("group", 1)
      InnerJoin(_) => ("join", 2)
    }
    let id = preferred + "_" + i.to_string()
    let projection_id = match payload {
      InnerJoin(_) => {
        if expansions >= limits.max_nodes - count - inputs ||
          references >= limits.max_references ||
          work >= limits.max_work {
          return Err({ kind: BudgetExceeded, source: step.source, })
        }
        let prefix = "join_raw_" + i.to_string()
        if used.contains(prefix) || prefix == id {
          return Err({ kind: IdentifierCollision, source: step.source, })
        }
        if prefix.length() > limits.max_identifier_bytes - bytes {
          return Err({ kind: BudgetExceeded, source: step.source, })
        }
        bytes += prefix.length()
        expansions += 1
        references += 1
        work += 1
        used[prefix] = true
        Some(prefix)
      }
      Distinct(op) => {
        let width = @schema.field_count(@relation.output_schema(op))
        if width > limits.max_work - work {
          return Err({ kind: BudgetExceeded, source: step.source, })
        }
        work += width
        if @relation.projection(op).is_empty() {
          None
        } else {
          if expansions >= limits.max_nodes - count - inputs ||
            references >= limits.max_references ||
            work >= limits.max_work {
            return Err({ kind: BudgetExceeded, source: step.source, })
          }
          let prefix = "select_" + i.to_string()
          if used.contains(prefix) || prefix == id {
            return Err({ kind: IdentifierCollision, source: step.source, })
          }
          if prefix.length() > limits.max_identifier_bytes - bytes {
            return Err({ kind: BudgetExceeded, source: step.source, })
          }
          bytes += prefix.length()
          expansions += 1
          references += 1
          work += 1
          used[prefix] = true
          Some(prefix)
        }
      }
      Values(_)
      | Derive(_)
      | Where(_)
      | Select(_)
      | Limit(_)
      | Dedupe(_)
      | Sort(_)
      | CountGroup(_) => None
    }
    let order_id = if payload is Limit(_) &&
      take_completion(checked, i) is Some(_) {
      if expansions >= limits.max_nodes - count - inputs ||
        references >= limits.max_references ||
        work >= limits.max_work {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      let prefix = "sort_" + i.to_string()
      if used.contains(prefix) || prefix == id {
        return Err({ kind: IdentifierCollision, source: step.source, })
      }
      if prefix.length() > limits.max_identifier_bytes - bytes {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      bytes += prefix.length()
      expansions += 1
      references += 1
      work += 1
      used[prefix] = true
      Some(prefix)
    } else {
      None
    }
    if used.contains(id) {
      return Err({ kind: IdentifierCollision, source: step.source, })
    }
    let aggregation_id = if payload is CountGroup(_) {
      if expansions >= limits.max_nodes - count - inputs ||
        references >= limits.max_references ||
        work >= limits.max_work {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      let prefix = "aggregate_" + i.to_string()
      if used.contains(prefix) || prefix == id {
        return Err({ kind: IdentifierCollision, source: step.source, })
      }
      if prefix.length() > limits.max_identifier_bytes - bytes {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      bytes += prefix.length()
      expansions += 1
      references += 1
      work += 1
      used[prefix] = true
      Some(prefix)
    } else {
      None
    }
    if id.length() > limits.max_identifier_bytes - bytes {
      return Err({ kind: BudgetExceeded, source: step.source, })
    }
    bytes += id.length()
    let refs : Array[String] = []
    let input_targets : Array[@pipeline.Target] = []
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
      input_targets.push(occurrence.target)
    }
    used[id] = true
    nodes.push({
      id,
      projection_id,
      order_id,
      aggregation_id,
      payload,
      inputs: refs,
      input_targets,
      output_schema,
      source: step.source,
    })
  }
  Ok({
    owner: checked,
    nodes,
    input_ids,
    input_schemas,
    usage: {
      nodes: count + inputs + expansions,
      references,
      work,
      identifier_bytes: bytes,
    },
  })
}
