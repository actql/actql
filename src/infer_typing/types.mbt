///|
pub type Limits = @evidence.InferLimits

///|
pub type Usage = @evidence.InferUsage

///|
pub type IssueKind = @evidence.InferIssueKind

///|
pub type Issue = @evidence.InferIssue

///|
pub type ResultMode = @evidence.InferResultMode

///|
pub type KeyBinding = @evidence.InferKeyBinding

///|
pub type InputBinding = @evidence.InferInputBinding

///|
pub type CheckedInfer = @evidence.CheckedInfer

///|
pub fn source(value : CheckedInfer) -> @decode.Cursor {
  @evidence.infer_source(value)
}

///|
pub fn input_records(value : CheckedInfer) -> @carrier.Knowledge {
  @evidence.infer_input_records(value)
}

///|
pub fn input_schema(value : CheckedInfer) -> @schema.Schema {
  @evidence.infer_input_schema(value)
}

///|
pub fn output_schema(value : CheckedInfer) -> @schema.Schema {
  @evidence.infer_output_schema(value)
}

///|
pub fn model_task(value : CheckedInfer) -> @environment.ModelTaskContract {
  @evidence.infer_model_task(value)
}

///|
pub fn parameters(value : CheckedInfer) -> @parameter.Declarations? {
  @evidence.infer_parameters(value)
}

///|
pub fn key_witness(value : CheckedInfer) -> @evidence.KeyedRelation {
  @evidence.infer_key_witness(value)
}

///|
pub fn key_count(value : CheckedInfer) -> Int {
  @evidence.infer_key_count(value)
}

///|
pub fn key_at(value : CheckedInfer, index : Int) -> KeyBinding? {
  @evidence.infer_key_at(value, index)
}

///|
pub fn input_binding_count(value : CheckedInfer) -> Int {
  @evidence.infer_input_binding_count(value)
}

///|
pub fn input_binding_at(value : CheckedInfer, index : Int) -> InputBinding? {
  @evidence.infer_input_binding_at(value, index)
}

///|
/// Return the exact authored ModelTask role retained by one input binding.
/// Callers must not reconstruct this name from source fields.
pub fn input_binding_role(value : InputBinding) -> String {
  value.role
}

///|
pub fn result_mode(value : CheckedInfer) -> ResultMode {
  @evidence.infer_result_mode(value)
}

///|
pub fn minimum_classification(
  value : CheckedInfer,
) -> @environment.DataClassification? {
  @evidence.infer_minimum_classification(value)
}

///|
pub fn max_items_guard(value : CheckedInfer) -> @relation.CheckedCountValue? {
  @evidence.infer_max_items_guard(value)
}

///|
pub fn usage(value : CheckedInfer) -> Usage {
  @evidence.infer_usage(value)
}

///|
pub fn result_keys(
  value : CheckedInfer,
  limits : @evidence.TransferLimits,
) -> Result[@evidence.KeySetTransfer, @evidence.Issue] {
  @evidence.infer_result_keys(value, limits)
}

///|
/// Uses the shared checked inference and key-evidence owner.
pub fn check(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  keys : @evidence.KeySet?,
  tasks : @environment.ModelTasks,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedInfer, Issue] {
  @evidence.check_infer(source, input, keys, tasks, parameters, limits)
}
