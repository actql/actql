///|
/// Project one retained frontend failure. The Request owns the original
/// issue/document and backs this writer before entry; this performs no parse,
/// lowering, binding or semantic check. A filtered publication cannot disclose
/// a Source-dependent failure merely because the original lowerer saw it.
pub fn client_program_project_original_query_issue(
  issue : @frontend.Issue,
  environment : @checked.CheckEnvironment?,
  original_publication : @publication.PreparedPublishedQueryEnvironment?,
  visible_publication : String,
  context_ref : String,
  input_revision : String,
  input_bytes : Int,
  declarations_revision : String?,
  declarations_bytes : Int,
  parameters_revision : String?,
  parameters_bytes : Int,
  correlation_ref : String,
  source_namespace : ClientCheckSourceNamespace?,
  query_original? : @query_syntax.Query? = None,
) -> String {
  if source_namespace is Some(complete) &&
    (
      complete.context_ref != context_ref ||
      complete.source_revision != input_revision ||
      environment
      .map(value => {
        complete.environment_cid != @checked.checking_environment_cid(value)
      })
      .unwrap_or(false)
    ) {
    return check_failed_json("check_context_invalid", correlation_ref)
  }
  let findings : Array[CheckFinding] = []
  // This typed issue and the exact retained parsed shape prove that unrelated
  // hidden publications cannot influence the failing expression. Parameter
  // issues and any query with a Source/producer dependency keep the old gate.
  let independent = issue is QuerySyntax(_) ||
    issue is WrongQueryForm ||
    (
      issue is QueryLowering(Expression({ issue: UnknownReference, .. })) &&
      query_original
      .map(@query_syntax.is_standalone_reference_projection)
      .unwrap_or(false)
    )
  let absence = issue is QueryLowering(UnresolvedRelation(_))
  let same_publication = match (original_publication, environment) {
    (Some(value), Some(environment)) =>
      @publication.prepared_published_query_environment_publication_matches(
        value, environment, visible_publication,
      )
    _ => false
  }
  let stop = if !independent && !absence && !same_publication {
    findings.push(Unresolved("source_resolution"))
    Report
  } else {
    check_frontend_issue(
      findings,
      issue,
      BoundInput,
      if environment is Some(_) {
        source_namespace
      } else {
        None
      },
    )
  }
  check_outcome_json(findings, stop, context_ref, correlation_ref, {
    scope: BoundInput,
    structured_program: false,
    program_pointer: None,
    source_revision: input_revision,
    source_bytes: input_bytes,
    declarations_revision,
    declarations_bytes,
    parameters_revision,
    parameters_bytes,
  })
}
