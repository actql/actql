///|
pub(all) struct InferLimits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
  max_tokens : Int
  max_key_fields : Int
  max_input_roles : Int
}

///|
pub(all) struct InferUsage {
  work : Int
  nodes : Int
  text_bytes : Int
  tokens : Int
} derive(Eq, Debug)

///|
pub(all) enum InferIssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  WrongCarrier(@carrier.Kind)
  IncompleteInputContract
  Task(@model_environment.ModelTaskIssueKind)
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
  Syntax(@expression_syntax.Issue)
  Expression(@typing.IssueKind)
  Guard(@relation.IssueKind)
} derive(Eq, Debug)

///|
pub struct InferIssue {
  kind : InferIssueKind
  source : @decode.Cursor
}

///|
pub(all) enum InferResultMode {
  Outcomes
  Fail
} derive(Eq, Debug)

///|
pub struct InferKeyBinding {
  field : @row.FieldName
  contract : @contract.Contract
}

///|
pub struct InferInputBinding {
  role : String
  source : @decode.Cursor
  expression : @typing.TypedExpression
}

///|
/// Checking binds existing evidence, not an observed unique-key or egress proof.
struct CheckedInfer {
  source : @decode.Cursor
  input : @carrier.Knowledge
  schema : @row.Schema
  task : @model_environment.ModelTaskContract
  parameters : @parameter.Declarations?
  key_witness : KeyedRelation
  keys : Array[InferKeyBinding]
  bindings : Array[InferInputBinding]
  output : @row.Schema
  mode : InferResultMode
  minimum_classification : @model_environment.DataClassification?
  max_items : @relation.CheckedCountValue?
  usage : InferUsage
}

///|
priv struct InferBudget {
  limits : InferLimits
  mut work : Int
  mut nodes : Int
  mut text : Int
  mut tokens : Int
}

///|
priv suberror InferStop {
  InferStop(InferIssue)
}

///|
fn[T] infer_fail(
  source : @decode.Cursor,
  kind : InferIssueKind,
) -> T raise InferStop {
  raise InferStop({ source, kind, })
}

///|
fn infer_spend(
  b : InferBudget,
  source : @decode.Cursor,
  count? : Int = 1,
) -> Unit raise InferStop {
  if count < 0 || count > b.work {
    infer_fail(source, BudgetExceeded)
  }
  b.work -= count
}

///|
fn infer_charge(
  b : InferBudget,
  source : @decode.Cursor,
  text : String,
) -> Unit raise InferStop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(n) => b.text -= n
    Err(_) => infer_fail(source, BudgetExceeded)
  }
}

///|
fn[T] infer_decoded(
  source : @decode.Cursor,
  value : Result[T, @decode.Issue],
) -> T raise InferStop {
  match value {
    Ok(value) => value
    Err(_) => infer_fail(source, InvalidBody)
  }
}

///|
pub fn infer_source(value : CheckedInfer) -> @decode.Cursor {
  value.source
}

///|
pub fn infer_input_records(value : CheckedInfer) -> @carrier.Knowledge {
  value.input
}

///|
pub fn infer_input_schema(value : CheckedInfer) -> @row.Schema {
  value.schema
}

///|
pub fn infer_output_schema(value : CheckedInfer) -> @row.Schema {
  value.output
}

///|
pub fn infer_model_task(
  value : CheckedInfer,
) -> @model_environment.ModelTaskContract {
  value.task
}

///|
pub fn infer_parameters(value : CheckedInfer) -> @parameter.Declarations? {
  value.parameters
}

///|
pub fn infer_key_witness(value : CheckedInfer) -> KeyedRelation {
  value.key_witness
}

///|
pub fn infer_key_count(value : CheckedInfer) -> Int {
  value.keys.length()
}

///|
/// Authored key order is distinct from canonical schema and processing order.
pub fn infer_key_at(value : CheckedInfer, index : Int) -> InferKeyBinding? {
  value.keys.get(index)
}

///|
pub fn infer_input_binding_count(value : CheckedInfer) -> Int {
  value.bindings.length()
}

///|
pub fn infer_input_binding_at(
  value : CheckedInfer,
  index : Int,
) -> InferInputBinding? {
  value.bindings.get(index)
}

///|
pub fn infer_result_mode(value : CheckedInfer) -> InferResultMode {
  value.mode
}

///|
pub fn infer_minimum_classification(
  value : CheckedInfer,
) -> @model_environment.DataClassification? {
  value.minimum_classification
}

///|
pub fn infer_max_items_guard(
  value : CheckedInfer,
) -> @relation.CheckedCountValue? {
  value.max_items
}

///|
pub fn infer_usage(value : CheckedInfer) -> InferUsage {
  value.usage
}
