///|
/// Existing semantic and sequence engines, one original preparation owner.
/// The fixed adapter calls completion only AFTER this constructor call returns.
pub fn[I] prepare_closed_values_body(
  owner : ClientClosedValuesPreparation[I],
  environment : @checked.CheckEnvironment,
  publication_environment : @source_publication.PreparedPublishedQueryEnvironment,
  contracts : ClientInstalledSequenceContracts,
  manifests : @publication_host.ClientCompilationManifests,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring || owner.prepared is Some(_) || owner.work is Some(_) {
    return Err(WrongPhase)
  }
  if owner.program is None {
    match parse_closed_values_document(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard owner.program is Some(program) &&
    owner.shape is Some(shape) &&
    owner.lexical is Some(facts) else {
    return Err(WrongPhase)
  }
  let catalog = match
    @source_publication.prepared_published_required_catalog(
      publication_environment, environment,
    ) {
    Err(_) => return Err(Policy)
    Ok(value) => value
  }
  let catalog_work = @checked.source_catalog_usage(catalog).work
  guard closed_values_context_phase_layout(
      facts,
      shape.fields,
      shape.rows,
      catalog,
      catalog_work,
    )
    is Some(context) &&
    closed_values_compiler_phase_layout(
      shape.fields,
      shape.rows,
      facts.node_upper,
      facts.longest_quoted_utf16,
      facts.depth_upper,
    )
    is Some(compiler) &&
    closed_values_execution_plan_controls_layout() is Some(plan) &&
    closed_values_plan_proof_layout(shape.fields, facts.longest_quoted_utf16)
    is Some(proof) &&
    closed_values_compilation_layout(facts, shape.fields, shape.rows)
    is Some(compilation) &&
    closed_values_sum_layouts([
      context.retained,
      compiler.retained,
      plan.retained,
      proof.retained,
      compilation.retained,
    ])
    is Some(retained_units) &&
    closed_values_sum_layouts([
      context.temporary,
      compiler.temporary,
      compiler.failure,
      plan.temporary,
      proof.temporary,
    ])
    is Some(temporary_units) &&
    @execution.preparation_representation_cost(retained_units)
    is Some(retained_add) &&
    @execution.preparation_representation_cost(temporary_units)
    is Some(semantic_execution) &&
    @execution.preparation_representation_cost(compilation.temporary)
    is Some(compilation_execution) else {
    return Err(Policy)
  }
  // Semantic and installed-plan constructors return before compilation starts.
  // Their returned original payloads remain in R. Only their private scratch
  // lifetimes are disjoint; this is a phase peak, not a second allowance.
  let execution_add = if semantic_execution > compilation_execution {
    semantic_execution
  } else {
    compilation_execution
  }
  // parse_closed_values_document has returned. Program/Cursor/shared source
  // dependencies remain in cumulative R; parser/shape/private containers do
  // not escape that call. Preserve the previous E debit, not cumulative work.
  guard client_closed_values_initial_control_capacity(
      owner.policy,
      module_containers=owner.module_containers,
    )
    is Some((_, controls)) &&
    closed_values_execution_peak(owner.execution_quote, execution_add, controls)
    is Some(execution) else {
    return Err(Policy)
  }
  if retained_add > 9223372036854775807L - owner.retained_quote {
    return Err(Policy)
  }
  let retained = owner.retained_quote + retained_add
  match
    reserve_closed_values_phase(
      owner.capacity,
      input,
      CheckLowerAndPlan,
      retained,
      execution,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => {
      owner.retained_quote = retained
      owner.execution_quote = execution
    }
  }
  let standard = @publication_host.client_standard_program_preparation_limits()
  let prepared = match
    @publication_host.prepare_parsed_effect_free_client_program(
      program,
      environment,
      None,
      {
        ..standard,
        checking: {
          ..standard.checking,
          input: {
            source: {
              max_input_bytes: facts.input_bytes,
              max_nodes: facts.node_upper,
              max_depth: facts.depth_upper,
            },
            tree: {
              max_nodes: facts.node_upper,
              max_depth: facts.depth_upper,
              max_string_bytes: facts.longest_quoted_utf16,
              max_total_string_bytes: facts.quoted_utf16_units,
            },
            max_stages: 1,
          },
        },
      },
      source_catalog=Some(catalog),
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  owner.prepared = Some(prepared)
  let installed = contracts.original
  // This existing fixed supplier still retains its raw sequence preparation.
  // Actual module construction cannot move here until the complete constructor
  // overlap, selected output mode and factory have their original funding.
  let source_free = match
    source_free_installed_managed_preparation_owned(
      Pure(prepared),
      contracts,
      installed.values_body,
      installed.fragment_body,
      installed.ordered_body,
      false,
    ) {
    Some(value) => value
    None => return Err(Installed(Unsupported))
  }
  owner.source_free = Some(source_free)
  let artifact = match
    @publication_host.issue_prepared_client_values_compilation(
      prepared,
      manifests,
      @publication_host.prepared_client_values_sequence_limits(prepared),
      compilation.max_facts,
      compilation.max_witnesses,
      compilation.max_wire_bytes,
      compilation.max_nodes,
      compilation.max_depth,
    ) {
    Err(issue) => return Err(Compilation(issue))
    Ok(value) => value
  }
  owner.compilation = Some(artifact)
  // No shrink here: constructor locals and previous phase owners can remain
  // live until this exact call unwinds. The next fixed call performs the cut.
  Ok(())
}
