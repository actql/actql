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
  MissingModelTasks
  InferRequiresAlias
  Infer(@evidence.InferIssueKind)
  Serialize(@content.ContentSerializationIssue)
  SerializeOrderUnproven
  UnresolvedOrder
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
  GuardBindingOwnerMismatch
  GuardBindingCountMismatch
  MissingGuardBinding(String)
  InvalidGuardValue(String)
  UnsupportedOperation(String)
  MissingPropertyProducerDefinition
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
  filter_refinement : @evidence.RefinedFilter?
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
pub fn input_occurrence_count(step : CheckedStep) -> Int {
  step.connections.entries.length()
}

///|
pub fn input_occurrence_at(step : CheckedStep, index : Int) -> InputOccurrence? {
  step.connections.entries.get(index)
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
  Serialize(CheckedSerialization)
  Infer(@evidence.CheckedInfer)
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
  GraphMatch(@graph.CheckedMatch)
  GraphBounds(@graph.CheckedGraphBounds)
  GraphDegree(@graph.CheckedDegree)
  GraphEquality(right~ : Target, checked~ : @graph.CheckedGraphEquality)
  GraphNormalize(@graph.CheckedNormalize)
  GraphDelta(right~ : Target, checked~ : @graph.CheckedDelta)
  GraphUnion(inputs~ : Array[Target], checked~ : @graph.CheckedUnion)
  GraphMean(inputs~ : Array[Target], checked~ : @graph.CheckedMean)
  GraphSubtraction(right~ : Target, checked~ : @graph.CheckedSubtraction)
  GraphComponents(@graph.CheckedComponents)
  Subgraph(selector~ : Target?, checked~ : @graph.CheckedSubgraph)
  Traverse(selector~ : Target?, checked~ : @graph.CheckedTraverse)
  GraphConstruction(
    inputs~ : Array[Target],
    checked~ : @graph.CheckedGraphConstruction
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
  input_orders : Array[LogicalOrder?]
  produced_inputs : Array[ProducedInput?]
  logical_orders : Array[LogicalOrder?]
  serialization_completions : Array[SortCompletion?]
  lag_orders : Array[SortCompletion?]
  analytic_orders : Array[AnalyticPositionOrder?]
  graph_counts : Array[GraphCount?]
  join_evidence : Array[JoinEvidence?]
  row_counts : Array[RowCount?]
  ranked_inputs : Array[@vector.RankingInput?]
  ranked_steps : Array[@vector.RankingInput]
  keyed_inputs : Array[@evidence.KeySet?]
  keyed_steps : Array[@evidence.KeySet?]
  literal_inputs : Array[@evidence.LiteralDomains?]
  literal_steps : Array[@evidence.LiteralDomains?]
  delta_inputs : Array[DeltaEvidence]
  delta_steps : Array[DeltaEvidence]
  source : @decode.Cursor
  initial_from : @decode.Cursor?
  inputs : Array[(String, @carrier.Carrier)]
  input_contracts : Array[InputContract]
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
  ProducedInput(ProducedInput)
  // Retained static declaration and selected Catalog owner, not execution authority.
  SourceViewInput(
    @stage.Stage,
    String,
    @decode.Cursor,
    @model_environment.SourceViewCarrier
  )
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
/// Original admission handle, distinct from derived Carrier/evidence views.
pub fn input_contract_at(
  value : CheckedPipeline,
  index : Int,
) -> InputContract? {
  value.input_contracts.get(index)
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
pub fn input_count(value : CheckedPipeline) -> Int {
  value.inputs.length()
}

///|
pub fn input_at(
  value : CheckedPipeline,
  index : Int,
) -> (String, @carrier.Carrier)? {
  value.inputs.get(index)
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
/// Values owns an input-free physical root. This reports checked operation
/// identity; it does not execute, capture or authorize the Program.
pub fn starts_with_values(value : CheckedPipeline) -> Bool {
  value.steps.get(0).map(step => step.operation is Values(_)).unwrap_or(false)
}

///|
/// Closed roots of the selected Local profile, not execution authority.
pub fn starts_with_selected_local_generator(value : CheckedPipeline) -> Bool {
  value.steps
  .get(0)
  .map(step => {
    match step.operation {
      Values(_) | TimeSeries(_) => true
      Calendar(checked) => @calendar.cardinality(checked) is AtMost(_)
      _ => false
    }
  })
  .unwrap_or(false)
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
  let normalized = match @canonical.normalize_nfc_lf(value) {
    Ok(value) => value
    Err(_) => fail(source, InvalidName(value))
  }
  name(b, source, normalized)
  normalized
}

///|
fn preflight(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
  depth? : Int = 0,
) -> Unit raise Stop {
  let original = begin_contract_preflight_read(b, source, root, depth)
  while original.state is Pending {
    advance_contract_preflight_read(original)
  }
  match original.state {
    Complete => clear_contract_preflight_read(original)
    Rejected(issue) => {
      clear_contract_preflight_read(original)
      raise Stop(issue)
    }
    _ => abort("original preflight was retired during its synchronous call")
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
  let original = begin_carrier_preflight_read(b, source, value)
  while original.state is Pending {
    advance_carrier_preflight_read(original)
  }
  match original.state {
    Complete => clear_carrier_preflight_read(original)
    Rejected(issue) => {
      clear_carrier_preflight_read(original)
      raise Stop(issue)
    }
    _ =>
      abort(
        "original Carrier preflight was retired during its synchronous call",
      )
  }
}

///|
fn schema(
  source : @decode.Cursor,
  target : Target,
  inputs : Array[(String, @carrier.Carrier)],
  steps : Array[CheckedStep],
  allow_conditional? : Bool = false,
) -> @schema.Schema raise Stop {
  let value = carrier(target, inputs, steps)
  match value {
    @carrier.Relation(rows) =>
      match @carrier.complete_schema(rows) {
        Some(schema) => {
          if !allow_conditional && !@schema.all_fields_required(schema) {
            fail(source, Operation(@relation.ConditionalInputNotImplemented))
          }
          schema
        }
        None => fail(source, IncompleteSchema)
      }
    _ => fail(source, WrongCarrier(@carrier.kind(value)))
  }
}
