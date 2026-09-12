///|
/// Generated from retained checked evidence, never from supplied artifact JSON.
/// Identity alone does not prove complete fragment admission.
priv struct RootArtifact {
  evidence : @lower.RootEvidence
  value : @identity.CanonicalValue
  cid : String
  bytes : Int
  nodes : Int
}

///|
priv enum RootArtifactIssue {
  InvalidLimits
  OutputLimit
  GeneratedDecodeFailure
  CanonicalizationFailure
}

///|
fn prepare_root_artifact(
  evidence : @lower.RootEvidence,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RootArtifact, RootArtifactIssue] {
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    return Err(InvalidLimits)
  }
  // Only our own bounded encoder output enters this codec adapter. The
  // temporary JSON is not used to resolve source, types, references or demand.
  let text = try {
    let out = @encode.writer(max_bytes, max_nodes, max_depth)
    @lower.emit_root_evidence(evidence, out)
    @encode.finish(out)
  } catch {
    _ => return Err(OutputLimit)
  }
  let json = @json.parse(text, max_nesting_depth=max_depth) catch {
    _ => return Err(GeneratedDecodeFailure)
  }
  // UTF-16 units of strings/keys cannot exceed the already bounded UTF-8 JSON
  // bytes. Keep the shared canonicalizer as the sole normalization/sort owner.
  let value = @identity.from_json(json, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(CanonicalizationFailure)
  }
  let usage = try {
    let out = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
    @identity.emit_value(value, out)
    @encode.finish_hash_usage(out)
  } catch {
    _ => return Err(OutputLimit)
  }
  Ok({
    evidence,
    value,
    cid: "sha256:" + usage.0,
    bytes: usage.1,
    nodes: usage.2,
  })
}
