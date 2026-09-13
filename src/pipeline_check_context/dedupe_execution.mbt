///|
/// A future check, not evidence that input rows or their representatives passed.
/// The input target belongs to site.pipeline; producer and admission dependencies
/// remain owned by the enclosing profile chain.
pub struct DedupeTopTieCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
}

///|
pub(all) enum OperationExecutionCheck {
  WindowExecution(WindowExecutionCheck)
  AnalyticExecution(AnalyticExecutionCheck)
  AnalyticEnvelope(AnalyticEnvelopeCheck)
  ExpansionExecution(ExpansionExecutionCheck)
  JsonPickExecution(JsonPickExecutionCheck)
  LagExecution(LagExecutionCheck)
  TopKExecution(TopKExecutionCheck)
  GroupExecution(GroupExecutionCheck)
  RowAssertion(RowAssertionCheck)
  DedupeTopTie(DedupeTopTieCheck)
  ValuesPublication(ValuesPublicationCheck)
  JoinOutputLimit(JoinOutputCheck)
  JoinRowOrder(JoinRowOrderCheck)
  JoinInputValidation(JoinInputValidationCheck)
  JoinIdentity(JoinIdentityCheck)
  AppendRows(AppendRowsCheck)
  SetRows(SetRowsCheck)
  CrossJoinRows(CrossJoinRowsCheck)
  CrossJoinIdentity(CrossJoinIdentityCheck)
}

///|
pub(all) enum ExecutionCheckPhase {
  BeforeOperationInputUse
  BeforeOperationOutput
} derive(Eq, Debug)

///|
pub(all) enum ExecutionCheckFailure {
  RejectOperationOutput
} derive(Eq, Debug)

///|
pub fn operation_execution_phase(
  v : OperationExecutionCheck,
) -> ExecutionCheckPhase {
  match v {
    WindowExecution(v) =>
      match v.rule {
        AdmitTimeValues => BeforeOperationInputUse
        AssignMemberships => BeforeOperationOutput
      }
    AnalyticExecution(_) => BeforeOperationOutput
    AnalyticEnvelope(_) => BeforeOperationOutput
    ExpansionExecution(_) => BeforeOperationOutput
    JsonPickExecution(_) => BeforeOperationOutput
    LagExecution(_) => BeforeOperationOutput
    TopKExecution(_) => BeforeOperationOutput
    GroupExecution(_) => BeforeOperationOutput
    RowAssertion(_) => BeforeOperationOutput
    DedupeTopTie(_) => BeforeOperationOutput
    ValuesPublication(_) => BeforeOperationOutput
    JoinOutputLimit(_) => BeforeOperationOutput
    JoinRowOrder(_) => BeforeOperationOutput
    JoinInputValidation(_) => BeforeOperationInputUse
    JoinIdentity(_) => BeforeOperationInputUse
    CrossJoinIdentity(_) => BeforeOperationInputUse
    CrossJoinRows(v) =>
      match v.rule {
        CheckProductArithmetic | RequireExactlyOneRightRow =>
          BeforeOperationInputUse
        PreserveLeftMajorOrder => BeforeOperationOutput
      }
    AppendRows(v) =>
      match v.rule {
        AdmitBothInputs => BeforeOperationInputUse
        PreserveLeftThenRight
        | RetainIdentityAndCompleteness
        | EnforceOutputEnvelope(_) => BeforeOperationOutput
      }
    SetRows(v) =>
      match v.rule {
        AdmitBothInputs | RequireComparisonResources => BeforeOperationInputUse
        CompareCompleteTypedRows
        | PreserveEarliestLeftOccurrences
        | BoundOutputByLeftInput
        | RetainIdentityAndCompleteness => BeforeOperationOutput
      }
  }
}

///|
pub fn operation_execution_failure(
  v : OperationExecutionCheck,
) -> ExecutionCheckFailure {
  match v {
    WindowExecution(_) => RejectOperationOutput
    AnalyticExecution(_) => RejectOperationOutput
    AnalyticEnvelope(_) => RejectOperationOutput
    ExpansionExecution(_) => RejectOperationOutput
    JsonPickExecution(_) => RejectOperationOutput
    LagExecution(_) => RejectOperationOutput
    TopKExecution(_) => RejectOperationOutput
    GroupExecution(_) => RejectOperationOutput
    RowAssertion(_) => RejectOperationOutput
    DedupeTopTie(_) => RejectOperationOutput
    ValuesPublication(_) => RejectOperationOutput
    JoinOutputLimit(_) => RejectOperationOutput
    JoinRowOrder(_) => RejectOperationOutput
    JoinInputValidation(_) => RejectOperationOutput
    JoinIdentity(_) => RejectOperationOutput
    CrossJoinIdentity(_) => RejectOperationOutput
    CrossJoinRows(_) => RejectOperationOutput
    AppendRows(_) => RejectOperationOutput
    SetRows(_) => RejectOperationOutput
  }
}

///|
/// Interpretation rule, not backend registration or an execution receipt.
pub fn dedupe_top_tie_law(_v : DedupeTopTieCheck) -> String {
  "aoa.rela.REL.dedupeRows.v0.1"
}

///|
/// Authored keys only: candidate keys, arrival order and CID cannot choose a
/// tied representative. A top tie rejects the operation's entire output.
fn dedupe_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) else {
    return Ok(None)
  }
  guard pending.kind is @relation.FailOnTopTie else { return Ok(None) }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(ForeignOccurrence(site.step))
  }
  guard step.operation is @pipeline.Unary(operation) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @relation.operation(operation) != @relation.DedupeRows ||
    @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body ||
    @relation.dedupe_order_count(operation) == 0 ||
    @pipeline.input_occurrence_count(step) != 1 {
    return Err(ForeignOccurrence(site.step))
  }
  guard step.input is Some(input) else {
    return Err(ForeignOccurrence(site.step))
  }
  let connection = @pipeline.input_occurrence_at(step, 0).unwrap()
  if connection.role != @pipeline.Primary || connection.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(DedupeTopTie({ site, step, input, operation, })))
}
