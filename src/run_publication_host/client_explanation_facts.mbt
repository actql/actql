///|
/// Compiler facts borrowed from the original checked operation. These Core
/// values are not a public wire envelope or permission to disclose expressions.
/// A Host projection must separately apply its current disclosure policy.
/// VALUES cardinality describes authored input, not executed/read/written rows.
pub enum ClientExplanationMeaning {
  InputOutput
  Values(row_count~ : Int, schema~ : @schema.Schema)
  Filter(@expression.TypedExpression)
  Projection(@relation.CheckedOperation)
  Join(@join.CheckedJoin)
  NotProjected
}

///|
/// An original-compilation read, not a Run, control boundary or resource owner.
/// Existing immutable checked values are borrowed; no row or expression tree
/// is copied, evaluated, rechecked or reconstructed from authored JSON.
pub struct ClientOperationExplanation {
  owner : PreparedClientProgram
  plan : @publication.PublicationContract
  stage : Int
  occurrence : Int
  input_only : Bool
  meaning : ClientExplanationMeaning
}

///|
/// Coordinates use the same original Plan and occurrence domain as the
/// existing logical map. This DATA introduces no new Story/Step identity.
pub(all) struct ClientExplanationOccurrence {
  compiled_plan_cid : String
  program_definition_cid : String
  parameter_values_cid : String
  stage_ordinal : Int
  occurrence_ordinal : Int
  input_only : Bool
} derive(Eq, Debug)

///|
pub fn client_task_operation_explanation(
  prepared : PreparedClientProgram,
  compiled : ClientTaskCompilation,
  stage : Int,
  occurrence : Int,
) -> Result[ClientOperationExplanation, ClientInteractivePlanIssue] {
  if !physical_equal(compiled.owner, prepared) {
    return Err(ForeignCompilation)
  }
  issue_client_operation_explanation(
    prepared,
    compiled.compiled_plan,
    stage,
    occurrence,
  )
}

///|
pub fn client_values_operation_explanation(
  prepared : PreparedClientProgram,
  compiled : ClientValuesCompilation,
  stage : Int,
  occurrence : Int,
) -> Result[ClientOperationExplanation, ClientInteractivePlanIssue] {
  if !physical_equal(compiled.owner, prepared) {
    return Err(ForeignCompilation)
  }
  issue_client_operation_explanation(
    prepared,
    compiled.compiled_plan,
    stage,
    occurrence,
  )
}

///|
fn issue_client_operation_explanation(
  prepared : PreparedClientProgram,
  plan : @publication.PublicationContract,
  stage : Int,
  occurrence : Int,
) -> Result[ClientOperationExplanation, ClientInteractivePlanIssue] {
  let checked = @strategy.graph_program(prepared.graph)
  guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
    return Err(MissingCheckedOccurrence)
  }
  let input_only = @pipeline.step_count(pipeline) == 0
  let meaning = if input_only {
    if occurrence != 0 ||
      @pipeline.input_count(pipeline) != 1 ||
      @pipeline.current(pipeline) != Some(@pipeline.Input(0)) {
      return Err(MissingCheckedOccurrence)
    }
    ClientExplanationMeaning::InputOutput
  } else {
    guard @pipeline.step_at(pipeline, occurrence) is Some(step) else {
      return Err(MissingCheckedOccurrence)
    }
    match step.operation {
      @pipeline.Values(values) =>
        ClientExplanationMeaning::Values(
          row_count=@relation_values.row_count(values),
          schema=@relation_values.output_schema(values),
        )
      @pipeline.Unary(operation) =>
        match @relation.operation(operation) {
          Filter => {
            guard @relation.binding_expression_at(operation, 0)
              is Some(predicate) else {
              return Err(MissingCheckedOccurrence)
            }
            ClientExplanationMeaning::Filter(predicate)
          }
          Select | Rename | Drop =>
            ClientExplanationMeaning::Projection(operation)
          _ => ClientExplanationMeaning::NotProjected
        }
      @pipeline.Join(checked~, ..) => ClientExplanationMeaning::Join(checked)
      // Absence of this explanation projection is not a language or runtime
      // refusal, an empty operation, or evidence of a completed computation.
      _ => ClientExplanationMeaning::NotProjected
    }
  }
  Ok({ owner: prepared, plan, stage, occurrence, input_only, meaning, })
}

///|
pub fn client_operation_explanation_occurrence(
  value : ClientOperationExplanation,
  prepared : PreparedClientProgram,
) -> Result[ClientExplanationOccurrence, ClientInteractivePlanIssue] {
  if !physical_equal(value.owner, prepared) {
    return Err(ForeignCompilation)
  }
  Ok({
    compiled_plan_cid: @publication.publication_contract_identity(value.plan),
    program_definition_cid: prepared_client_identity(prepared).program_definition_cid,
    parameter_values_cid: prepared_client_identity(prepared).parameter_values_cid,
    stage_ordinal: value.stage,
    occurrence_ordinal: value.occurrence,
    input_only: value.input_only,
  })
}

///|
pub fn client_operation_explanation_meaning(
  value : ClientOperationExplanation,
  prepared : PreparedClientProgram,
) -> Result[ClientExplanationMeaning, ClientInteractivePlanIssue] {
  if !physical_equal(value.owner, prepared) {
    return Err(ForeignCompilation)
  }
  Ok(value.meaning)
}
