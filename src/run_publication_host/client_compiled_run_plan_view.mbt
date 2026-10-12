///|
pub(all) enum ClientCompiledRunPlanIssue {
  ForeignCompilation
  UnsupportedCompilation
  Projection(ClientInteractivePlanIssue)
} derive(Eq, Debug)

///|
/// Capture the original logical map while its compiler-issued Run owner is
/// still retained. This never compiles or executes another Program. Save the
/// returned original with admission; historical lookup must read those bytes,
/// not use a newly prepared owner to reconstruct missing map evidence.
/// A projection is metadata, not authority to inspect or control a Run.
pub fn client_compiled_run_static_plan_view(
  compiled : ClientCompiledRun,
  original : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  inspect_installed? : Bool = false,
) -> Result[String, ClientCompiledRunPlanIssue] {
  if !client_compiled_run_matches(compiled, original) {
    return Err(ForeignCompilation)
  }
  let view = match compiled.compilation {
    Values(compilation) =>
      client_values_static_plan_view(
        original,
        compilation,
        max_bytes,
        max_nodes,
        max_depth,
        inspect_installed~,
      )
    Tasks(compilation) =>
      client_task_static_plan_view(
        original,
        compilation,
        max_bytes,
        max_nodes,
        max_depth,
        inspect_installed~,
      )
    Effects(_) => return Err(UnsupportedCompilation)
  }
  view.map_err(issue => Projection(issue))
}
