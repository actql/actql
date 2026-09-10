///|
pub(all) struct Limits {
  max_steps : Int
  max_work : Int
  max_text_bytes : Int
  max_nodes : Int
  max_tokens : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) struct Usage {
  work : Int
  text_bytes : Int
  nodes : Int
  tokens : Int
} derive(Eq, Debug)

///|
/// Indices in the retained input list or authored step array; not semantic IDs.
pub(all) enum Target {
  Input(Int)
  Step(Int)
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  RowBoundOverflow
  InvalidBody
  InvalidName(String)
  DuplicateName(String)
  UnknownName(String)
  MissingCurrent
  MissingKeyEvidence
  KeyEvidence(@evidence.IssueKind)
  WrongCarrier(@carrier.Kind)
  IncompleteSchema
  GeneratorRequiresAlias
  GeneratorFrom
  Values(@values.IssueKind)
  TimeSeries(@series.IssueKind)
  Calendar(@calendar.IssueKind)
  Window(@window.IssueKind)
  Projection(@projection.IssueKind)
  Graph(@graph.IssueKind)
  GraphMatch(@graph.MatchIssueKind)
  Vector(@vector.IssueKind)
  Event(@event.IssueKind)
  MissingWindowEvidence
  MissingDeltaContract
  InvalidDeltaContractBinding
  UnsupportedOperation(String)
  InvalidMetadata
  ReservedMetadataKey(String)
  Operation(@relation.IssueKind)
  Join(@join.IssueKind)
  Append(@append.IssueKind)
  Nest(@nest.IssueKind)
  Set(@set.IssueKind)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
  path : Array[@decode.PathSegment]
  span : @span.Span
  range : @text.Range?
}

///|
pub struct CheckedStep {
  source : @decode.Cursor
  input : Target?
  binding_name : String?
  metadata : @decode.Cursor?
  operation : CheckedOperation
  output : @carrier.Carrier
  connections : Connections
  window : WindowEvidence?
}

///|
pub(all) enum InputRole {
  Primary
  Left
  Right
  Sample(Int)
} derive(Eq, Debug)

///|
pub struct InputOccurrence {
  role : InputRole
  target : Target
}

///|
struct Connections {
  entries : Array[InputOccurrence]
}

///|
pub fn input_occurrences(step : CheckedStep) -> Array[InputOccurrence] {
  step.connections.entries.copy()
}

///|
pub fn step_schema(step : CheckedStep) -> @schema.Schema? {
  match step.output {
    @carrier.Relation(rows) => @carrier.complete_schema(rows)
    _ => None
  }
}

///|
/// Main input is stored on CheckedStep; binary operations retain their right input.
pub enum CheckedOperation {
  Unary(@relation.CheckedOperation)
  Join(right~ : Target, checked~ : @join.CheckedJoin)
  Append(right~ : Target, checked~ : @append.CheckedAppend)
  Nest(right~ : Target, checked~ : @nest.CheckedNest)
  Set(right~ : Target, checked~ : @set.CheckedSet)
  CrossJoin(right~ : Target, checked~ : @join.CheckedCrossJoin)
  IntervalJoin(right~ : Target, checked~ : @join.CheckedIntervalJoin)
  AsOfJoin(right~ : Target, checked~ : @join.CheckedAsOf)
  Sequence(@relation.CheckedSequence)
  Values(@values.CheckedValues)
  TimeSeries(@series.CheckedSeries)
  Calendar(@calendar.CheckedCalendar)
  Window(@window.CheckedWindow)
  Projection(@projection.CheckedProjection)
  Graph(@graph.CheckedGraph)
  GraphMatch(@graph.CheckedMatch)
  Reach(@graph.CheckedReach)
  Subgraph(selector~ : Target?, checked~ : @graph.CheckedSubgraph)
  Traverse(selector~ : Target?, checked~ : @graph.CheckedTraverse)
  Shortest(
    source_selector~ : Target?,
    target_selector~ : Target?,
    checked~ : @graph.CheckedShortest
  )
  GraphEquality(right~ : Target, checked~ : @graph.CheckedEquality)
  GraphDiff(right~ : Target, checked~ : @graph.CheckedDiff)
  GraphApply(right~ : Target, checked~ : @graph.CheckedApply)
  GraphStructural(right~ : Target, checked~ : @graph.CheckedStructural)
  GraphMean(@graph.CheckedMean)
  GraphConstruction(
    nodes~ : Target?,
    edges~ : Target,
    checked~ : @graph.CheckedConstruction
  )
  Vector(@vector.CheckedVector)
  Nearest(queries~ : Target, checked~ : @vector.CheckedNearest)
  Pool(@vector.CheckedPool)
  Ranking(@vector.CheckedRanking)
  TextRank(queries~ : Target, checked~ : @vector.CheckedTextRank)
  Event(@event.CheckedEvent)
  WindowGroup(@relation.CheckedOperation)
}

///|
struct WindowEvidence {
  starts : Array[@schema.FieldName]
  ends : Array[@schema.FieldName]
}

///|
pub fn window_evidence(step : CheckedStep) -> WindowEvidence? {
  step.window
}

///|
/// Select one surviving start/end pair. Use window_aliases for all witnesses.
pub fn window_fields(
  value : WindowEvidence,
) -> (@schema.FieldName, @schema.FieldName) {
  (value.starts[0], value.ends[0])
}

///|
/// Return detached arrays of all surviving start and end aliases.
pub fn window_aliases(
  value : WindowEvidence,
) -> (Array[@schema.FieldName], Array[@schema.FieldName]) {
  (value.starts.copy(), value.ends.copy())
}

///|
struct CheckedPipeline {
  logical_orders : Array[LogicalOrder?]
  graph_counts : Array[GraphCount?]
  join_evidence : Array[JoinEvidence?]
  row_counts : Array[RowCount?]
  ranked_inputs : Array[@vector.RankingInput?]
  ranked_steps : Array[@vector.RankingInput]
  keyed_inputs : Array[@evidence.KeySet?]
  keyed_steps : Array[@evidence.KeySet?]
  delta_inputs : Array[DeltaEvidence]
  delta_steps : Array[DeltaEvidence]
  source : @decode.Cursor
  initial_from : @decode.Cursor?
  inputs : Array[(String, @carrier.Carrier)]
  steps : Array[CheckedStep]
  names : Map[String, Target]
  current : Target?
  output : @carrier.Carrier?
  parameters : @parameter.Declarations?
  usage : Usage
}

///|
/// A key declaration retains its own Relation contract and admission obligations.
pub(all) enum InputContract {
  CarrierInput(@carrier.Carrier)
  KeyedInput(@evidence.KeyedRelation)
  CandidateKeysInput(@evidence.KeySet)
  RankingInput(@vector.RankingInput)
  RelationEvidenceInput(RelationEvidence)
}

///|
pub fn input_key(
  value : CheckedPipeline,
  index : Int,
) -> @evidence.KeyedRelation? {
  if index < 0 || index >= value.keyed_inputs.length() {
    None
  } else {
    value.keyed_inputs[index].bind(single_candidate)
  }
}

///|
pub fn source(value : CheckedPipeline) -> @decode.Cursor {
  value.source
}

///|
pub fn initial_from(value : CheckedPipeline) -> @decode.Cursor? {
  value.initial_from
}

///|
pub fn inputs(value : CheckedPipeline) -> Array[(String, @carrier.Carrier)] {
  value.inputs.copy()
}

///|
pub fn step_count(value : CheckedPipeline) -> Int {
  value.steps.length()
}

///|
pub fn step_at(value : CheckedPipeline, index : Int) -> CheckedStep? {
  if index < 0 || index >= value.steps.length() {
    None
  } else {
    Some(value.steps[index])
  }
}

///|
pub fn lookup(value : CheckedPipeline, name : String) -> Target? {
  value.names.get(name)
}

///|
pub fn current(value : CheckedPipeline) -> Target? {
  value.current
}

///|
pub fn output_schema(value : CheckedPipeline) -> @schema.Schema? {
  match value.output {
    Some(@carrier.Relation(rows)) => @carrier.complete_schema(rows)
    _ => None
  }
}

///|
pub fn output_carrier(value : CheckedPipeline) -> @carrier.Carrier? {
  value.output
}

///|
/// Checked lookup without copying the input list. Coordinates remain local to
/// this pipeline and carry no authority outside it.
pub fn schema_at(value : CheckedPipeline, target : Target) -> @schema.Schema? {
  match carrier_at(value, target) {
    Some(@carrier.Relation(rows)) => @carrier.complete_schema(rows)
    _ => None
  }
}

///|
pub fn carrier_at(
  value : CheckedPipeline,
  target : Target,
) -> @carrier.Carrier? {
  match target {
    Input(i) =>
      if i < 0 || i >= value.inputs.length() {
        None
      } else {
        Some(value.inputs[i].1)
      }
    Step(i) =>
      if i < 0 || i >= value.steps.length() {
        None
      } else {
        Some(value.steps[i].output)
      }
  }
}

///|
pub fn parameters(value : CheckedPipeline) -> @parameter.Declarations? {
  value.parameters
}

///|
pub fn usage(value : CheckedPipeline) -> Usage {
  value.usage
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    source,
    path: @decode.cursor_path(source),
    span: @decode.cursor_span(source),
    range: None,
  })
}

///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut text : Int
  mut nodes : Int
  mut tokens : Int
}

///|
fn spend(b : Budget, source : @decode.Cursor, amount : Int) -> Unit raise Stop {
  if amount < 0 || amount > b.work {
    fail(source, BudgetExceeded)
  }
  b.work -= amount
}

///|
fn charge(
  b : Budget,
  source : @decode.Cursor,
  text : String,
) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
fn name(b : Budget, source : @decode.Cursor, value : String) -> Unit raise Stop {
  spend(b, source, 1)
  charge(b, source, value)
  if value == "" || @canonical.normalize_nfc_lf(value) != Ok(value) {
    fail(source, InvalidName(value))
  }
}

///|
fn read_name(b : Budget, source : @decode.Cursor) -> String raise Stop {
  let value = match @decode.text(source) {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
  name(b, source, value)
  value
}

///|
fn preflight(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
  depth? : Int = 0,
) -> Unit raise Stop {
  let work = [(root, depth)]
  while work.pop() is Some((c, depth)) {
    spend(b, source, 1)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        spend(b, source, count)
        for i in 0..<count {
          let f = @contract.field_at(fields, i).unwrap()
          charge(b, source, f.name)
          work.push((f.contract, depth + 1))
        }
      }
      @contract.ResourceRef(resource_kind~) => charge(b, source, resource_kind)
      @contract.ArtifactRef(media_type=Some(media)) => charge(b, source, media)
      _ => ()
    }
  }
}

///|
fn rows_preflight(
  b : Budget,
  source : @decode.Cursor,
  rows : @carrier.Knowledge,
) -> Unit raise Stop {
  spend(b, source, 1)
  let n = @carrier.field_count(rows)
  spend(b, source, n)
  for i in 0..<n {
    let f = @carrier.field_at(rows, i).unwrap()
    charge(b, source, @schema.reference_name(f.name))
    if f.contract is Some(c) {
      preflight(b, source, c, depth=1)
    }
  }
}

///|
fn carrier(
  target : Target,
  inputs : Array[(String, @carrier.Carrier)],
  steps : Array[CheckedStep],
) -> @carrier.Carrier {
  match target {
    Input(i) => inputs[i].1
    Step(i) => steps[i].output
  }
}

///|
fn carrier_preflight(
  b : Budget,
  source : @decode.Cursor,
  value : @carrier.Carrier,
) -> Unit raise Stop {
  match value {
    @carrier.Relation(rows) => rows_preflight(b, source, rows)
    @carrier.Opaque(_) => spend(b, source, 1)
    @carrier.GraphValue(graph) => {
      spend(b, source, 1)
      preflight(b, source, @carrier.graph_identity(graph))
      if @carrier.graph_label_contract(graph) is Some(c) {
        preflight(b, source, c)
      }
      rows_preflight(b, source, @carrier.graph_node_properties(graph))
      rows_preflight(b, source, @carrier.graph_edge_properties(graph))
      if @carrier.graph_names(graph) is Some(names) {
        let (node, src, dst, label) = @carrier.graph_row_fields(names)
        let fields = [node, src, dst]
        if label is Some(label) {
          fields.push(label)
        }
        spend(b, source, fields.length())
        for field in fields {
          charge(b, source, @schema.reference_name(field))
        }
      }
      if @carrier.graph_labels(graph) is Some(labels) {
        spend(b, source, labels.length())
        for label in labels {
          charge(b, source, label)
        }
      }
    }
    @carrier.EventValue(events) => {
      rows_preflight(b, source, events.records)
      spend(b, source, 2)
      charge(b, source, @schema.reference_name(events.identity.name))
      charge(b, source, @schema.reference_name(events.time.name))
    }
    @carrier.VectorValue(vectors) => {
      rows_preflight(b, source, @carrier.vector_records(vectors))
      let ids = @carrier.vector_identities(vectors)
      spend(b, source, ids.length())
      for field in ids {
        charge(b, source, @schema.reference_name(field.name))
      }
      spend(b, source, 1)
      charge(
        b,
        source,
        @schema.reference_name(@carrier.vector_components(vectors).name),
      )
    }
  }
}

///|
fn schema(
  source : @decode.Cursor,
  target : Target,
  inputs : Array[(String, @carrier.Carrier)],
  steps : Array[CheckedStep],
) -> @schema.Schema raise Stop {
  let value = carrier(target, inputs, steps)
  match value {
    @carrier.Relation(rows) =>
      match @carrier.complete_schema(rows) {
        Some(schema) => schema
        None => fail(source, IncompleteSchema)
      }
    _ => fail(source, WrongCarrier(@carrier.kind(value)))
  }
}
