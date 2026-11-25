///|
pub(all) enum ClientCompiledRunPlanIssue {
  ForeignCompilation
  UnsupportedCompilation
  Projection(ClientInteractivePlanIssue)
} derive(Eq, Debug)

///|
// The Request already retains this compiler artifact before Run admission.
// Inspect its original owner/Plan without issuing authorization, a Run binding
// or a replacement compilation merely to measure optional static metadata.
fn client_pure_compilation_original_plan(
  original : PreparedClientProgram,
  compilation : ClientRunCompilation,
) -> Result[@publication.PublicationContract, ClientCompiledRunPlanIssue] {
  match compilation {
    Values(value) => {
      if !physical_equal(value.owner, original) {
        return Err(ForeignCompilation)
      }
      Ok(value.compiled_plan)
    }
    Tasks(value) => {
      if !physical_equal(value.owner, original) {
        return Err(ForeignCompilation)
      }
      Ok(value.compiled_plan)
    }
    Effects(_) => Err(UnsupportedCompilation)
  }
}

///|
/// Read the SAME Request's retained compiler artifact before any Run exists.
/// Its caller must already hold the original static projection construction.
pub fn client_pure_compilation_static_plan_view(
  compilation : ClientRunCompilation,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  inspect_installed? : Bool = false,
  debug_entry? : Bool = false,
) -> Result[String, ClientCompiledRunPlanIssue] {
  let plan = match
    client_pure_compilation_original_plan(prepared, compilation) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  issue_client_static_plan_view(
    prepared,
    plan,
    max_bytes,
    max_nodes,
    max_depth,
    inspect_installed,
    debug_entry~,
  ).map_err(issue => Projection(issue))
}

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

///|
fn capture_client_compiled_static_plan_original(
  compiled : ClientCompiledRun,
  original : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  inspect_installed : Bool,
) -> Result[(String, @publication.RunEvidenceValue), ClientCompiledRunPlanIssue] {
  if !client_compiled_run_matches(compiled, original) {
    return Err(ForeignCompilation)
  }
  let plan = match compiled.compilation {
    Values(compilation) => {
      if !physical_equal(compilation.owner, original) {
        return Err(Projection(ForeignCompilation))
      }
      compilation.compiled_plan
    }
    Tasks(compilation) => {
      if !physical_equal(compilation.owner, original) {
        return Err(Projection(ForeignCompilation))
      }
      compilation.compiled_plan
    }
    Effects(_) => return Err(UnsupportedCompilation)
  }
  let retained : Ref[@publication.RunEvidenceValue?] = Ref(None)
  let wire = match
    issue_client_static_plan_view(
      original,
      plan,
      max_bytes,
      max_nodes,
      max_depth,
      inspect_installed,
      retained_original=Some(retained),
    ) {
    Err(issue) => return Err(Projection(issue))
    Ok(value) => value
  }
  guard retained.val is Some(map) else { return Err(Projection(Encoding)) }
  Ok((wire, map))
}
