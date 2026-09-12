///|
/// Evidence projection from one retained typed root and its shared demand facts.
/// This does not establish fragment admission or canonical byte identity.
struct RootEvidence {
  root : ExpressionRoot
  paths : Array[(String, Array[SourceDemandTest])]
}

///|
pub(all) struct RootEvidenceLimits {
  max_nodes : Int
  max_tests : Int
  max_pointer_bytes : Int
}

///|
pub(all) enum RootEvidenceIssue {
  InvalidEvidenceLimits
  MissingEvidenceRoot
  EvidenceLimit
  DemandAddress(DemandAddressIssue)
}

///|
pub fn prepare_root_evidence(
  index : DemandIndex,
  root_index : Int,
  limits : RootEvidenceLimits,
) -> Result[RootEvidence, RootEvidenceIssue] {
  if limits.max_nodes < 0 ||
    limits.max_tests < 0 ||
    limits.max_pointer_bytes < 0 {
    return Err(InvalidEvidenceLimits)
  }
  guard root_at(index.roots, root_index) is Some(root) else {
    return Err(MissingEvidenceRoot)
  }
  guard demand_root_at(index, root_index) is Some(demands) else {
    return Err(MissingEvidenceRoot)
  }
  let count = @typing.node_count(@typing.demand_expression(demands))
  if count > limits.max_nodes {
    return Err(EvidenceLimit)
  }
  let paths = []
  let mut bytes = limits.max_pointer_bytes
  let mut tests_left = limits.max_tests
  for node = 0; node < count; node = node + 1 {
    let pointer = match
      demand_source_pointer(index, root_index, node, max_bytes=bytes) {
      Ok(None) => continue // implicit CASE else has no source occurrence
      Ok(Some(pointer)) => pointer
      Err(e) => return Err(DemandAddress(e))
    }
    bytes -= @utf8.encode(pointer).length()
    let tests = match
      demand_source_tests(
        index,
        root_index,
        node,
        max_tests=tests_left,
        max_pointer_bytes=bytes,
      ) {
      Ok(tests) => tests
      Err(e) => return Err(DemandAddress(e))
    }
    tests_left -= tests.length()
    for condition in tests {
      bytes -= @utf8.encode(condition.pointer).length()
    }
    paths.push((pointer, tests))
  }
  Ok({ root, paths, })
}

///|
/// Complete root value using the caller's cumulative writer limits. Object
/// enumeration follows retained source/topology; canonical artifacts must apply
/// canonical object ordering before hashing, as for emit_root_source.
pub fn emit_root_evidence(
  evidence : RootEvidence,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "contract")
  @contract.emit_checked(expression_contract(evidence.root.expression), out)
  @encode.key(out, "demand_paths")
  @encode.begin_object(out)
  for (pointer, tests) in evidence.paths {
    @encode.key(out, pointer)
    @encode.begin_array(out)
    for condition in tests {
      @encode.begin_object(out)
      @encode.key(out, "pointer")
      @encode.string_value(out, condition.pointer)
      @encode.key(out, "test")
      @encode.string_value(
        out,
        match condition.predicate {
          @typing.IsTrue => "true"
          @typing.NotTrue => "not_true"
          @typing.IsNull => "null"
        },
      )
      @encode.end_object(out)
    }
    @encode.end_array(out)
  }
  @encode.end_object(out)
  @encode.key(out, "node")
  emit_expression(evidence.root.expression, out)
  @encode.key(out, "parameter_pointer")
  @encode.string_value(out, evidence.root.parameter_pointer)
  @encode.key(out, "source")
  emit_root_source(evidence.root, out)
  @encode.key(out, "step_id")
  @encode.string_value(out, evidence.root.step_id)
  @encode.end_object(out)
}
