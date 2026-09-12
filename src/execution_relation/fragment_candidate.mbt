///|
/// Complete generated map/filter fragment value, before sealed admission and
/// runtime obligation checks. No API accepts arbitrary AoA to construct this.
priv struct FragmentCandidate {
  contract : FragmentContract
  material : FragmentMaterial
  artifact : GeneratedArtifact
}

///|
fn emit_fragment_candidate_body(
  material : FragmentMaterial,
  limits : RegistryLimits,
  cid : String?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  // Current typed expression lowering has no profile-call variants. A future
  // profile extension must supply its occurrences, not inherit this empty list.
  @encode.key(out, "evaluations")
  @encode.begin_array(out)
  @encode.end_array(out)
  @encode.key(out, "expression_contract_cid")
  @encode.string_value(out, selected_expression_contract_cid)
  match cid {
    Some(cid) => {
      @encode.key(out, "fragment_cid")
      @encode.string_value(out, cid)
    }
    None => ()
  }
  @encode.key(out, "graph")
  @identity.emit_value(material.graph.value, out)
  @encode.key(out, "limits")
  emit_request_limits(material.request, limits, out)
  // Current relation_schema.Schema contains the complete field set. No open
  // input is synthesized from missing fields or later consumers.
  @encode.key(out, "output_open")
  @encode.bool_value(out, false)
  @encode.key(out, "output_schema")
  @encode.begin_object(out)
  let schema = @lower.fragment_pipeline_output_schema(
    @lower.fragment_request_pipeline(material.request.request),
  )
  for i = 0; i < @schema.field_count(schema); i = i + 1 {
    let field = @schema.field_at(schema, i).unwrap()
    @encode.key(out, @schema.reference_name(field.name))
    @contract.emit_checked(field.contract, out)
  }
  @encode.end_object(out)
  @encode.key(out, "request")
  @identity.emit_value(material.request.artifact.value, out)
  @encode.key(out, "roots")
  emit_fragment_material_roots(material, out)
  if material.ordered is Some(binding) {
    @encode.key(out, "row_kernel_evidence")
    emit_ordered_evidence(binding, limits.max_body_nodes, out)
  }
  @encode.key(out, "version")
  @encode.string_value(out, "actql-expression-fragment/0.1")
  @encode.end_object(out)
}

///|
fn prepare_fragment_candidate(
  contract : FragmentContract,
  material : FragmentMaterial,
  limits : RegistryLimits,
) -> Result[FragmentCandidate, RootArtifactIssue] {
  if limits.max_body_bytes < 0 ||
    limits.max_body_nodes < 1 ||
    limits.max_body_depth < 0 {
    return Err(InvalidLimits)
  }
  let text = try {
    let out = @encode.writer(
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    )
    emit_fragment_candidate_body(material, limits, None, out)
    @encode.finish(out)
  } catch {
    _ => return Err(OutputLimit)
  }
  let artifact = match
    canonicalize_generated_artifact(
      text,
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    ) {
    Ok(artifact) => artifact
    Err(issue) => return Err(issue)
  }
  Ok({ contract, material, artifact, })
}

///|
fn emit_fragment_candidate(
  candidate : FragmentCandidate,
  limits : RegistryLimits,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_fragment_candidate_body(
    candidate.material,
    limits,
    Some(candidate.artifact.cid),
    out,
  )
}
