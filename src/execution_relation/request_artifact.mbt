///|
/// Retains the checked request owner alongside its canonical identity. This
/// commits declared ceilings; it is not proof of inferred capacity or complete
/// expression-fragment admission.
priv struct RequestArtifact {
  request : @lower.FragmentRequest
  artifact : GeneratedArtifact
}

///|
fn prepare_request_artifact(
  request : @lower.FragmentRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RequestArtifact, RootArtifactIssue] {
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    return Err(InvalidLimits)
  }
  let text = try {
    let out = @encode.writer(max_bytes, max_nodes, max_depth)
    @lower.emit_fragment_request(request, out)
    @encode.finish(out)
  } catch {
    _ => return Err(OutputLimit)
  }
  match canonicalize_generated_artifact(text, max_bytes, max_nodes, max_depth) {
    Ok(artifact) => Ok({ request, artifact, })
    Err(issue) => Err(issue)
  }
}
