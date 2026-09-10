///|
pub(all) enum Operation {
  Derive
  Filter
  Select
  Rename
  Drop
  Sort
  Take
  Distinct
  DedupeRows
  JsonPick
  Unnest
  AssertRows
  Unpivot
  Group
  Pivot
  Analytic
} derive(Eq, Debug)

///|
pub(all) enum Form {
  DeriveMap
  DeriveArray
  Predicate
  Projection
  RowOperation
  Reshape
  Aggregation
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_work : Int
  max_text_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_tokens : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  InvalidBody
  EmptyBody
  InvalidName(String)
  DuplicateOutput(String)
  UnknownField(String)
  InputCollision(String)
  ExpectedBoolean
  InvalidOrder
  NotAuthorOrderable(String)
  NotKeyComparable(String)
  InvalidCount
  UnknownParameter(String)
  ExpectedObject
  ExpectedArray
  ShapeEvidenceRequired
  IncompatibleColumn(String)
  InvalidAggregate(String)
  InvalidAggregateOption(String)
  InvalidAggregateArgument(String)
  ForbiddenAggregateValue
  InvalidFill
  InvalidFrame
  FillValue(@value.Issue)
  BudgetExceeded
  Syntax(@syntax.Issue)
  Expression(@typing.IssueKind)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  // Retained context; path/span/range are the diagnostic location.
  source : @decode.Cursor
  path : Array[@decode.PathSegment]
  span : @span.Span
  range : @text.Range?
}

///|
pub(all) enum ReferenceTarget {
  InputField(@schema.FieldName)
  PriorSlot(Int)
} derive(Eq, Debug)

///|
pub struct Reference {
  occurrence : @syntax.FieldReference
  target : ReferenceTarget
}

///|
pub struct Binding {
  name : String?
  source : @decode.Cursor
  expression : @typing.TypedExpression
  references : Array[Reference]
}

///|
pub struct ProjectionField {
  output : @schema.FieldName
  input : @schema.FieldName
}

///|
struct CheckedOperation {
  operation : Operation
  form : Form
  source : @decode.Cursor
  input : @schema.Schema
  output : @schema.Schema
  parameters : @parameter.Declarations?
  bindings : Array[Binding]
  projection : Array[ProjectionField]
  row_operation : RowOperation?
  reshape : Reshape?
  group : CheckedGroup?
  pivot : CheckedPivot?
  analytic : CheckedAnalytic?
  pending : Array[PendingValidation]
  work_used : Int
  text_bytes_used : Int
  nodes_used : Int
  tokens_used : Int
}

///|
pub fn operation(value : CheckedOperation) -> Operation {
  value.operation
}

///|
pub fn form(value : CheckedOperation) -> Form {
  value.form
}

///|
pub fn input_schema(value : CheckedOperation) -> @schema.Schema {
  value.input
}

///|
pub fn output_schema(value : CheckedOperation) -> @schema.Schema {
  value.output
}

///|
pub fn source(value : CheckedOperation) -> @decode.Cursor {
  value.source
}

///|
pub fn parameters(value : CheckedOperation) -> @parameter.Declarations? {
  value.parameters
}

///|
pub fn binding_count(value : CheckedOperation) -> Int {
  value.bindings.length()
}

///|
pub fn binding_at(value : CheckedOperation, index : Int) -> Binding? {
  if index < 0 || index >= value.bindings.length() {
    None
  } else {
    let b = value.bindings[index]
    Some({ ..b, references: references(b), })
  }
}

///|
pub fn references(value : Binding) -> Array[Reference] {
  value.references.copy()
}

///|
/// Authored select order; rename/drop expand in canonical input-name order.
pub fn projection(value : CheckedOperation) -> Array[ProjectionField] {
  value.projection.copy()
}

///|
pub fn work_used(value : CheckedOperation) -> Int {
  value.work_used
}

///|
pub fn text_bytes_used(value : CheckedOperation) -> Int {
  value.text_bytes_used
}

///|
pub fn nodes_used(value : CheckedOperation) -> Int {
  value.nodes_used
}

///|
pub fn tokens_used(value : CheckedOperation) -> Int {
  value.tokens_used
}

///|
priv struct Budget {
  mut work : Int
  mut text : Int
  mut nodes : Int
  mut tokens : Int
  limits : Limits
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  let (path, span, range) = match kind {
    Syntax(issue) => (issue.path.copy(), issue.span, issue.range)
    FillValue(@value.ValueIssue(_, path~, span~)) => (path.copy(), span, None)
    FillValue(@value.Decode(issue)) => (issue.path.copy(), issue.span, None)
    _ => (@decode.cursor_path(source), @decode.cursor_span(source), None)
  }
  raise Stop({ source, kind, path, span, range, })
}

///|
fn[T] unknown_reference(
  source : @decode.Cursor,
  occurrence : @syntax.FieldReference,
) -> T raise Stop {
  raise Stop({
    source,
    kind: UnknownField(occurrence.name),
    path: @syntax.location_path(occurrence.location),
    span: @syntax.location_span(occurrence.location),
    range: occurrence.location.range,
  })
}

///|
fn spend(
  b : Budget,
  source : @decode.Cursor,
  count? : Int = 1,
) -> Unit raise Stop {
  if count < 0 || count > b.work {
    fail(source, BudgetExceeded)
  }
  b.work -= count
}

///|
fn charge(
  b : Budget,
  source : @decode.Cursor,
  text : String,
) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(size) => b.text -= size
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
fn[T] decoded(
  result : Result[T, @decode.Issue],
  source : @decode.Cursor,
) -> T raise Stop {
  match result {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
}

///|
fn field_name(
  b : Budget,
  source : @decode.Cursor,
  name : String,
) -> Unit raise Stop {
  let bytes = b.text
  spend(b, source)
  charge(b, source, name)
  match
    @contract.object_contract(
      [(name, @contract.primitive(NumberType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=bytes,
    ) {
    Ok(_) => ()
    Err(_) => fail(source, InvalidName(name))
  }
}

///|
fn object_type(
  b : Budget,
  source : @decode.Cursor,
  fields : Array[(String, @contract.Contract)],
) -> @contract.Contract raise Stop {
  let bytes = b.text
  spend(b, source, count=fields.length())
  for (name, _) in fields {
    charge(b, source, name)
  }
  match
    @contract.object_contract(
      fields,
      nullable=false,
      max_fields=fields.length(),
      max_name_bytes=bytes,
    ) {
    Ok(c) => c
    Err(_) => fail(source, InvalidBody)
  }
}

///|
// Entire input contracts are admitted before projection or shadowing. This is
// resource preflight, not revalidation of opaque admitted contract invariants.
fn preflight(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
  depth? : Int = 0,
) -> Unit raise Stop {
  let work = [(root, depth)]
  while work.pop() is Some((c, depth)) {
    spend(b, source)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        spend(b, source, count~)
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
fn schema_preflight(
  b : Budget,
  source : @decode.Cursor,
  schema : @schema.Schema,
) -> Unit raise Stop {
  spend(b, source)
  let count = @schema.field_count(schema)
  spend(b, source, count~)
  for i in 0..<count {
    let f = @schema.field_at(schema, i).unwrap()
    charge(b, source, @schema.reference_name(f.name))
    preflight(b, source, f.contract, depth=1)
  }
}

///|
fn schema_type(
  b : Budget,
  source : @decode.Cursor,
  fields : Array[(@schema.FieldName, @contract.Contract)],
) -> @schema.Schema raise Stop {
  let bytes = b.text
  spend(b, source, count=fields.length())
  for (name, _) in fields {
    charge(b, source, @schema.reference_name(name))
  }
  match
    @schema.from_fields(
      fields,
      max_fields=fields.length(),
      max_name_bytes=bytes,
    ) {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
}

///|
fn reference_target(
  name : String,
  value : ReferenceTarget,
) -> @schema.FieldName {
  match value {
    InputField(name) => name
    PriorSlot(_) => @schema.Unqualified(name)
  }
}

///|
fn input_reference(
  b : Budget,
  source : @decode.Cursor,
  name : String,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
) -> @schema.FieldName raise Stop {
  spend(b, source)
  charge(b, source, name)
  if name.has_prefix("left.") || name.has_prefix("right.") {
    let parts = name.split(".").to_array()
    if parts.length() != 2 {
      fail(source, InvalidName(name))
    }
    field_name(b, source, parts[1].to_owned())
  } else {
    field_name(b, source, name)
  }
  match visible.get(name) {
    Some((_, target)) => reference_target(name, target)
    None => fail(source, UnknownField(name))
  }
}
