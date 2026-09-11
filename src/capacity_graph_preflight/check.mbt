///|
pub type Measure = @input.Measure

///|
pub type Limits = @input.Limits

///|
pub type Issue = @input.Issue

///|
pub type GraphInputs = @input.GraphInputs

///|
pub using @input {
  check,
  check_complete,
  unconsumed_limit_count,
  checked_pipeline,
  checked_sources,
  selected_policy,
  input_limit,
  usage,
}
