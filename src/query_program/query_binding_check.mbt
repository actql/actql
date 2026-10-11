///|
pub(all) enum BindingPreparationIssue {
  Declarations(@stage_parameters.Issue)
  SourceRegistration(@check_context.SourceRegistrationIssue)
  SourceProgram(@check_context.SourceViewProgramIssue)
  LocalProgram(@stage_results.LocalProgramIssue)
}

///|
// Check the complete lowered source before deciding which bindings are demanded.
// SourceViewInput registration comes from the actual Catalog and original Stage;
// a schema attachment cannot stand in for an admitted source. The returned
// wiring retains conditional producer evidence and outstanding obligations.
// This call does not acquire rows, bind parameter values, reserve execution,
// close all validation/profile debts, or issue a public checked Program/Run.
fn prepare_query_bindings(
  program : @program.Program,
  context : Context,
  limits : Limits,
) -> Result[@stage_results.ResultWiring, BindingPreparationIssue] {
  let tree = limits.program.tree
  let source = match
    @stage_parameters.prepare(program, {
      max_parameters: tree.max_nodes,
      max_nodes: tree.max_nodes,
      max_depth: tree.max_depth,
      max_text_bytes: tree.max_total_string_bytes,
    }) {
    Ok(source) => source
    Err(issue) => return Err(Declarations(issue))
  }
  let pipeline_limits : @stage_results.LocalProgramLimits = {
    max_stages: limits.program.max_stages,
    max_steps: tree.max_nodes,
    max_results: tree.max_nodes,
    max_work: limits.max_expression_work,
    max_nodes: tree.max_nodes,
    max_tokens: tree.max_nodes,
    max_text_bytes: tree.max_total_string_bytes,
    max_depth: tree.max_depth,
  }
  match context.source_catalog {
    Some(catalog) => {
      let (views, locals) = match
        @check_context.prepare_source_registrations(
          source,
          catalog,
          {
            max_work: limits.max_expression_work,
            max_nodes: tree.max_nodes,
            max_text_bytes: tree.max_total_string_bytes,
            max_depth: tree.max_depth,
          },
          max_inputs=tree.max_nodes,
          max_views=tree.max_nodes,
          max_order_keys=tree.max_nodes,
        ) {
        Ok(registered) => registered
        Err(issue) => return Err(SourceRegistration(issue))
      }
      match
        @check_context.prepare_sourceview_program(
          views,
          locals,
          pipeline_limits,
          model_tasks=context.model_tasks,
        ) {
        Ok((wiring, _)) => Ok(wiring)
        Err(issue) => Err(SourceProgram(issue))
      }
    }
    None =>
      match
        @stage_results.prepare_local_program(
          source,
          pipeline_limits,
          model_tasks=context.model_tasks,
        ) {
        Ok((wiring, _)) => Ok(wiring)
        Err(issue) => Err(LocalProgram(issue))
      }
  }
}
