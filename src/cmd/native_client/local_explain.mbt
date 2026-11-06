///|
// Static compiler-owned projection only. The same checked preparation and
// nominal compilation are passed to the existing PlanView/envelope Owner.
// This creates no Run, input observation, grant, Preview or execution.
fn local_static_plan_view(
  preparation : @local_host.NativeClientPreparation,
  max_bytes? : Int = 65536,
  max_nodes? : Int = 8192,
  max_depth? : Int = 64,
) -> String raise ClientStop {
  let acquisitions = match preparation {
    Computation(prepared) =>
      @run_host.prepared_client_acquisition_count(prepared)
    EffectComputation(prepared) =>
      @strategy.graph_captured_prefix(
        @strategy.checked_effect_computation_graph(
          @run_host.prepared_client_effect_computation_graph(prepared),
        ),
      )
  }
  if acquisitions != 0 {
    stop("LocalStaticSourcePlanUnavailable")
  }
  let manifests = @run_host.admit_client_compilation_manifests(
    @compiler_environment.compiler_grammar_manifest_wire(),
    @compiler_environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap_or_else(() => stop("LocalCompilerManifestUnavailable"))
  match preparation {
    Computation(prepared) => {
      let compiled = @run_host.issue_prepared_client_task_compilation(
        prepared,
        manifests,
        @run_host.prepared_client_values_sequence_limits(prepared),
        1000,
        1000,
        65536,
        8192,
        64,
      ).unwrap_or_else(() => stop("LocalStaticCompilationUnavailable"))
      @run_host.client_task_static_plan_view(
        prepared,
        compiled,
        max_bytes,
        max_nodes,
        max_depth,
        inspect_installed=false,
      ).unwrap_or_else(() => stop("LocalStaticPlanUnavailable"))
    }
    EffectComputation(prepared) => {
      // Read the same original checked computation without issuing a
      // normalization journal, allowed Run or checkpoint/Preview custody.
      let compiled = @run_host.issue_prepared_client_effect_compilation(
        prepared,
        manifests,
        @run_host.client_standard_values_sequence_limits(),
        1000,
        1000,
        65536,
        8192,
        64,
      ).unwrap_or_else(() => stop("LocalStaticCompilationUnavailable"))
      @run_host.client_effectful_static_plan_view(
        prepared, compiled, max_bytes, max_nodes, max_depth,
      ).unwrap_or_else(() => stop("LocalStaticEffectPlanUnavailable"))
    }
  }
}

///|
// Reuse the same static preparation for explicit configuration and the selected
// operational command. The caller supplies the original admitted Environment;
// this path does not issue a Run, acquire a Source or select an Engine.
fn local_explain_for_environment(
  environment : @checked.CheckEnvironment,
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  native_timing_begin(2)
  defer native_timing_end(2)
  let format = match @frontend.select_format(required(child, "format")) {
    Ok(value) => value
    Err(_) => stop("UnsupportedLocalSourceFormat")
  }
  let supplied = optional(child, "parameters-file").map(name => {
    local_input_cursor(local_input_text_file(input_root, name, 65536L))
  })
  let declarations = match optional(child, "parameter-declarations-file") {
    None => None
    Some(name) => {
      if format != Text && format != Sql {
        stop("external declarations require aql-text or sql")
      }
      let source = local_input_cursor(
        local_input_text_file(input_root, name, 65536L),
      )
      match
        @parameters.read_declarations(Some(source), {
          max_parameters: 1024,
          max_nodes: 8192,
          max_depth: 64,
          max_text_bytes: 65536,
        }) {
        Ok(value) => Some(value)
        Err(_) => stop("LocalDeclarationsNotAdmitted")
      }
    }
  }
  let context = match
    @frontend.bind_query_context(
      [],
      @checked.checking_environment_cid(environment),
      parameter_declarations=declarations,
      model_tasks=@checked.checking_environment_model_tasks(environment),
    ) {
    Ok(value) => value
    Err(_) => stop("InvalidLocalQueryContext")
  }
  let prepared = match
    @local_host.prepare_native_client_program(
      local_input_text_file(input_root, required(child, "program-file"), 65536L),
      format,
      environment,
      supplied,
      Some(context),
      [],
      @run_host.client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(issue) => local_stop_native_preparation(issue)
  }
  let wire = local_static_plan_view(prepared)
  local_explain_reply(wire, child.flags.get("json").unwrap_or(false))
}

///|
// The same selected Host/configuration/current observation used by Local check
// remains live across input reading and static compilation. Its command-local
// reporting key stays private and is never a signing or execution authority.
fn LocalCheckContext::explain(
  self : LocalCheckContext,
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  if !self.current() {
    stop("LocalCheckContextUnavailable")
  }
  let reply = local_explain_for_environment(self.environment, input_root, child)
  if !self.current() {
    stop("LocalCheckContextUnavailable")
  }
  reply
}
