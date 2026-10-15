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
    Computation(prepared) => @run_host.prepared_client_acquisition_count(prepared)
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
        @run_host.client_standard_values_sequence_limits(),
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
