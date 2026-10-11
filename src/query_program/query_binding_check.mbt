///|
pub(all) enum BindingPreparationIssue {
  Declarations(@stage_parameters.Issue)
  SourceDeclarations(@sourceviews.Issue)
  MissingSourceCatalog(@sourceviews.Declaration)
  SourceRegistration(@check_context.SourceRegistrationIssue)
  SourceProgram(@check_context.SourceViewProgramIssue)
  LocalProgram(@stage_results.LocalProgramIssue)
  Demand(BindingDemandIssue)
}

///|
pub(all) enum BindingDemandIssue {
  WorkLimit
  ForeignStage
  InvalidRange
  MissingImport
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
  match
    prepare_query_bindings_internal(program, context, limits, check_only=false) {
    Ok(Publication(wiring)) => Ok(wiring)
    Ok(_) => abort("mixed binding preparation modes")
    Err(issue) => Err(issue)
  }
}

///|
priv struct BindingTopology {
  topology : @stage_results.CheckedTopology
  sourceviews : @check_context.SourceViewCheckedTopology?
}

///|
priv enum BindingPreparation {
  Publication(@stage_results.ResultWiring)
  Topology(BindingTopology)
}

///|
fn check_query_bindings(
  program : @program.Program,
  context : Context,
  limits : Limits,
) -> Result[BindingTopology, BindingPreparationIssue] {
  match
    prepare_query_bindings_internal(program, context, limits, check_only=true) {
    Ok(Topology(topology)) => Ok(topology)
    Ok(_) => abort("mixed binding preparation modes")
    Err(issue) => Err(issue)
  }
}

///|
fn prepare_query_bindings_internal(
  program : @program.Program,
  context : Context,
  limits : Limits,
  check_only~ : Bool,
) -> Result[BindingPreparation, BindingPreparationIssue] {
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
      if check_only {
        match
          @check_context.check_sourceview_program(
            views,
            locals,
            pipeline_limits,
            model_tasks=context.model_tasks,
          ) {
          Ok((checked, _)) =>
            Ok(
              Topology({
                topology: @check_context.sourceview_checked_topology(checked),
                sourceviews: Some(checked),
              }),
            )
          Err(issue) => Err(SourceProgram(issue))
        }
      } else {
        match
          @check_context.prepare_sourceview_program(
            views,
            locals,
            pipeline_limits,
            model_tasks=context.model_tasks,
          ) {
          Ok((wiring, _)) => Ok(Publication(wiring))
          Err(issue) => Err(SourceProgram(issue))
        }
      }
    }
    None => {
      let views = match
        @sourceviews.collect(source, {
          max_work: limits.max_expression_work,
          max_order_keys: tree.max_nodes,
        }) {
        Ok(views) => views
        Err(issue) => return Err(SourceDeclarations(issue))
      }
      if @sourceviews.at(views, 0) is Some(declaration) {
        // The common declaration owner identifies the missing metadata. Do not
        // parse a Connector input as a Local Relation or fabricate its Carrier.
        return Err(MissingSourceCatalog(declaration))
      }
      if check_only {
        match
          @stage_results.check_local_program(
            source,
            {
              ..pipeline_limits,
              max_work: pipeline_limits.max_work - @sourceviews.work(views),
            },
            model_tasks=context.model_tasks,
          ) {
          Ok((topology, _)) => Ok(Topology({ topology, sourceviews: None, }))
          Err(issue) => Err(LocalProgram(issue))
        }
      } else {
        match
          @stage_results.prepare_local_program(
            source,
            {
              ..pipeline_limits,
              max_work: pipeline_limits.max_work - @sourceviews.work(views),
            },
            model_tasks=context.model_tasks,
          ) {
          Ok((wiring, _)) => Ok(Publication(wiring))
          Err(issue) => Err(LocalProgram(issue))
        }
      }
    }
  }
}
