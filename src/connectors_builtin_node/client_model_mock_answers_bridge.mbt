///|
/// Model-only Node projection. The RelA bundle intentionally has no Model
/// dependency; its ordinary public Task reader and original bytes are intact.
#export_name("clientProgramReadMockAnswers")
pub fn client_program_read_mock_answers(
  task : @check_environment.PublicModelTaskDeclaration,
  wire : String,
  format : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  value_nodes : Int,
  value_depth : Int,
  value_text_bytes : Int,
  max_entries : Int,
  max_work : Int,
) -> Result[@model.ModelMockAnswers, @model.ModelMockAnswerIssue] {
  @model.read_model_mock_answer_document(task, wire, format, {
    document: { max_bytes, max_nodes, max_depth, max_members, },
    values: {
      max_nodes: value_nodes,
      max_depth: value_depth,
      max_text_bytes: value_text_bytes,
    },
    max_entries,
    max_work,
  })
}

///|
#export_name("clientProgramMockAnswerCount")
pub fn client_program_mock_answer_count(
  original : @model.ModelMockAnswers,
  task : @check_environment.PublicModelTaskDeclaration,
) -> Result[Int, @model.ModelMockAnswerIssue] {
  @model.model_mock_answer_count(original, task)
}

///|
#export_name("clientProgramMockAnswerDefault")
pub fn client_program_mock_answer_default(
  original : @model.ModelMockAnswers,
  task : @check_environment.PublicModelTaskDeclaration,
) -> Result[@admitted.CheckedValue?, @model.ModelMockAnswerIssue] {
  @model.model_mock_answer_default(original, task)
}

///|
#export_name("clientProgramMockAnswerAt")
pub fn client_program_mock_answer_at(
  original : @model.ModelMockAnswers,
  task : @check_environment.PublicModelTaskDeclaration,
  index : Int,
) -> Result[(String, @admitted.CheckedValue)?, @model.ModelMockAnswerIssue] {
  @model.model_mock_answer_at(original, task, index)
}

///|
#export_name("clientProgramRetireMockAnswers")
pub fn client_program_retire_mock_answers(
  original : @model.ModelMockAnswers,
  task : @check_environment.PublicModelTaskDeclaration,
) -> Result[Unit, @model.ModelMockAnswerIssue] {
  @model.retire_model_mock_answers(original, task)
}
