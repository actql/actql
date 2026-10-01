///|
pub(all) struct Limits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
  max_tokens : Int
  max_key_fields : Int
  max_input_roles : Int
}

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
  tokens : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  WrongCarrier(@carrier.Kind)
  IncompleteInputContract
  Task(@environment.ModelTaskIssueKind)
  InputKeyOwnerMismatch
  CandidateKeyRequired
  AmbiguousCandidateKey
  InvalidKeyTuple
  UnknownKeyField(String)
  InvalidKeyType(String)
  KeyRoleCollision(String)
  UnknownInputRole(String)
  MissingInputRole(String)
  InputTypeMismatch(String)
  ForbiddenModelInput
  Syntax(@syntax.Issue)
  Expression(@expression.IssueKind)
  Guard(@relation.IssueKind)
}

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
}

///|
pub(all) enum ResultMode {
  Outcomes
  Fail
} derive(Eq, Debug)

///|
pub struct KeyBinding {
  field : @schema.FieldName
  contract : @contract.Contract
}

///|
pub struct InputBinding {
  role : String
  source : @decode.Cursor
  expression : @expression.TypedExpression
}

///|
/// Checking binds existing evidence, not an observed unique-key or egress proof.
struct CheckedInfer {
  source : @decode.Cursor
  input : @carrier.Knowledge
  schema : @schema.Schema
  task : @environment.ModelTaskContract
  parameters : @parameter.Declarations?
  key_witness : @evidence.KeyedRelation
  keys : Array[KeyBinding]
  bindings : Array[InputBinding]
  output : @schema.Schema
  mode : ResultMode
  minimum_classification : @environment.DataClassification?
  max_items : @relation.CheckedCountValue?
  usage : Usage
}

///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut nodes : Int
  mut text : Int
  mut tokens : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({ source, kind, })
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
    Ok(n) => b.text -= n
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
fn[T] decoded(
  source : @decode.Cursor,
  value : Result[T, @decode.Issue],
) -> T raise Stop {
  match value {
    Ok(value) => value
    Err(_) => fail(source, InvalidBody)
  }
}

///|
pub fn source(value : CheckedInfer) -> @decode.Cursor {
  value.source
}

///|
pub fn input_records(value : CheckedInfer) -> @carrier.Knowledge {
  value.input
}

///|
pub fn input_schema(value : CheckedInfer) -> @schema.Schema {
  value.schema
}

///|
pub fn output_schema(value : CheckedInfer) -> @schema.Schema {
  value.output
}

///|
pub fn model_task(value : CheckedInfer) -> @environment.ModelTaskContract {
  value.task
}

///|
pub fn parameters(value : CheckedInfer) -> @parameter.Declarations? {
  value.parameters
}

///|
pub fn key_witness(value : CheckedInfer) -> @evidence.KeyedRelation {
  value.key_witness
}

///|
pub fn key_count(value : CheckedInfer) -> Int {
  value.keys.length()
}

///|
/// Authored key order is distinct from canonical schema and processing order.
pub fn key_at(value : CheckedInfer, index : Int) -> KeyBinding? {
  value.keys.get(index)
}

///|
pub fn input_binding_count(value : CheckedInfer) -> Int {
  value.bindings.length()
}

///|
pub fn input_binding_at(value : CheckedInfer, index : Int) -> InputBinding? {
  value.bindings.get(index)
}

///|
pub fn result_mode(value : CheckedInfer) -> ResultMode {
  value.mode
}

///|
pub fn minimum_classification(
  value : CheckedInfer,
) -> @environment.DataClassification? {
  value.minimum_classification
}

///|
pub fn max_items_guard(value : CheckedInfer) -> @relation.CheckedCountValue? {
  value.max_items
}

///|
pub fn usage(value : CheckedInfer) -> Usage {
  value.usage
}
