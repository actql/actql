///|
// Only artifacts emitted from the retained checked roots enter this walk. It
// translates source addressing to the existing op/body node addressing; it
// neither interprets a supplied expression nor supplies type/bound evidence.
fn evaluation_position(
  root : RootArtifact,
  root_index : Int,
  pointer : String,
  max_bytes : Int,
) -> (String, @identity.CanonicalValue)? {
  let prefix = "/roots/" + root_index.to_string() + "/source"
  if !pointer.has_prefix(prefix) || pointer.length() > max_bytes {
    return None
  }
  let mut source = @identity.object_field(root.value, "source").unwrap()
  let mut node = @identity.object_field(root.value, "node").unwrap()
  let mut node_pointer = "/roots/" + root_index.to_string() + "/node"
  let suffix = String::from_array(pointer.to_array()[prefix.length():])
  if !suffix.is_empty() {
    if !suffix.has_prefix("/") {
      return None
    }
    for encoded in suffix.split("/")[1:] {
      let encoded = encoded.to_owned()
      let key = encoded.replace(old="~1", new="/").replace(old="~0", new="~")
      let is_expression = @identity.object_field(node, "op")
        is Some(@identity.String(_))
      let selected = if is_expression { "body" } else { key }
      guard evaluation_child(source, key) is Some(next_source) &&
        evaluation_child(node, selected) is Some(next_node) else {
        return None
      }
      source = next_source
      node = next_node
      node_pointer += "/" + (if is_expression { "body" } else { encoded })
      if node_pointer.length() > max_bytes {
        return None
      }
    }
  }
  guard @identity.object_field(node, "op") is Some(@identity.String(operation)) &&
    ["try_number", "utf8_truncate", "nfkc", "case_fold"].contains(operation) &&
    @identity.object_field(source, operation) is Some(arguments) else {
    return None
  }
  Some((node_pointer, arguments))
}

///|
fn evaluation_child(
  value : @identity.CanonicalValue,
  key : String,
) -> @identity.CanonicalValue? {
  match value {
    @identity.Array(items) => {
      let mut index = 0
      if key.is_empty() {
        return None
      }
      for unit in key {
        let digit = unit.to_int() - 48
        if digit < 0 || digit > 9 || index > (2147483647 - digit) / 10 {
          return None
        }
        index = index * 10 + digit
      }
      @identity.array_at(items, index)
    }
    _ => @identity.object_field(value, key)
  }
}

///|
fn emit_text_evaluation_envelope(
  original : @expression_context.TextBoundResolution,
  step : String,
  pointer : String,
  arguments_cid : String,
  tests : @identity.CanonicalValue,
  filter_pointer : String?,
  cid : String?,
  limits : RegistryLimits,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let bound = @expression_context.text_bound_output(original)
  let input = @text_bounds.output_input(bound)
  let policy = @model_environment.text_time_policy(
    @expression_context.text_bound_policy(original),
  )
  let (points, bytes) = @text_bounds.input_extent(input)
  @encode.begin_object(out)
  @encode.key(out, "arguments_cid")
  @encode.string_value(out, arguments_cid)
  @encode.key(out, "demand_path")
  @encode.begin_array(out)
  if filter_pointer is Some(pointer) {
    @encode.begin_object(out)
    @encode.key(out, "pointer")
    @encode.string_value(out, pointer)
    @encode.key(out, "test")
    @encode.string_value(out, "true")
    @encode.end_object(out)
  }
  guard tests is @identity.Array(conditions) else {
    raise @encode.InvalidStructure
  }
  for i in 0..<@identity.array_count(conditions) {
    @identity.emit_value(@identity.array_at(conditions, i).unwrap(), out)
  }
  @encode.end_array(out)
  if cid is Some(cid) {
    @encode.key(out, "envelope_cid")
    @encode.string_value(out, cid)
  }
  @encode.key(out, "expression_pointer")
  @encode.string_value(out, pointer)
  @encode.key(out, "host_policy_profile_cid")
  @encode.string_value(out, @text_policy.cid(policy))
  @encode.key(out, "input")
  @encode.begin_object(out)
  @encode.key(out, "evidence_cid")
  @encode.string_value(
    out,
    @text_bounds.input_evidence_cid(
      input,
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    ),
  )
  @encode.key(out, "max_codepoints")
  @encode.number_value(out, points.to_double())
  @encode.key(out, "max_utf8_bytes")
  @encode.number_value(out, bytes.to_double())
  @encode.key(out, "source")
  @encode.string_value(out, @text_bounds.input_evidence_source(input))
  @encode.end_object(out)
  @encode.key(out, "max_output_bytes")
  @encode.number_value(out, @text_bounds.output_bytes(bound).to_double())
  @encode.key(out, "operation")
  @encode.string_value(
    out,
    match @text_bounds.output_operation(bound) {
      TryNumber => "try_number"
      Nfkc => "nfkc"
      CaseFold => "case_fold"
      Utf8Truncate(_) => "utf8_truncate"
      _ => raise @encode.InvalidStructure
    },
  )
  @encode.key(out, "semantic_step_id")
  @encode.string_value(out, step)
  @encode.key(out, "verification")
  @encode.string_value(
    out,
    if @text_bounds.input_origin(input) is RuntimePreflight {
      "unit_preflight"
    } else {
      "plan"
    },
  )
  @encode.key(out, "version")
  @encode.string_value(out, "actql-text-time-evaluation-envelope/0.1")
  @encode.end_object(out)
}

///|
fn prepare_fragment_evaluations(
  demands : @lower.DemandIndex,
  roots : Array[RootArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[GeneratedArtifact], RootArtifactIssue] {
  let index = @lower.demand_roots(demands)
  let ordered : Array[(String, GeneratedArtifact)] = []
  let mut bytes = max_bytes
  let mut nodes = max_nodes
  let mut work = max_nodes
  for root_index in 0..<roots.length() {
    let root = @lower.root_at(index, root_index).unwrap()
    if @lower.expression_text_bound_count(root.expression) == 0 {
      continue
    }
    let count = @typing.node_count(root.typed_expression)
    if count > work {
      return Err(OutputLimit)
    }
    work -= count
    for node_index in 0..<count {
      guard @lower.expression_text_bound_at(root.expression, node_index)
        is Some(original) else {
        continue
      }
      let output = @expression_context.text_bound_output(original)
      if !(@text_bounds.output_operation(output)
        is (TryNumber | Utf8Truncate(_) | Nfkc | CaseFold)) {
        return Err(GeneratedDecodeFailure)
      }
      let pointer = match
        @lower.demand_source_pointer(
          demands,
          root_index,
          node_index,
          max_bytes=bytes,
        ) {
        Ok(Some(pointer)) => pointer
        _ => return Err(OutputLimit)
      }
      guard evaluation_position(roots[root_index], root_index, pointer, bytes)
        is Some((node_pointer, arguments)) &&
        @identity.object_field(roots[root_index].value, "demand_paths")
        is Some(paths) &&
        @identity.object_field(paths, pointer) is Some(tests) else {
        return Err(GeneratedDecodeFailure)
      }
      let requirement = @expression_context.validation_site_requirement(
        @expression_context.text_bound_site(original),
      )
      let mut filter_pointer = None
      if requirement.filter is Some(filter) {
        if roots.length() > work {
          return Err(OutputLimit)
        }
        work -= roots.length()
        for earlier in 0..<root_index {
          if physical_equal(
              @lower.root_at(index, earlier).unwrap().typed_expression,
              filter.expression,
            ) {
            filter_pointer = Some("/roots/" + earlier.to_string() + "/source")
          }
        }
        if filter_pointer is None {
          return Err(GeneratedDecodeFailure)
        }
      }
      let limits : RegistryLimits = {
        max_body_bytes: bytes,
        max_body_nodes: nodes,
        max_body_depth: max_depth,
      }
      let artifact = try {
        let arguments_cid = @identity.cid_value(
          arguments, bytes, nodes, max_depth,
        )
        let preimage = @encode.hashing_writer(bytes, nodes, max_depth)
        emit_text_evaluation_envelope(
          original,
          root.step_id,
          pointer,
          arguments_cid,
          tests,
          filter_pointer,
          None,
          limits,
          preimage,
        )
        let cid = "sha256:" + @encode.finish_hash(preimage)
        let out = @encode.writer(bytes, nodes, max_depth)
        @encode.begin_object(out)
        @encode.key(out, "envelope")
        emit_text_evaluation_envelope(
          original,
          root.step_id,
          pointer,
          arguments_cid,
          tests,
          filter_pointer,
          Some(cid),
          limits,
          out,
        )
        @encode.key(out, "node_pointer")
        @encode.string_value(out, node_pointer)
        @encode.end_object(out)
        match
          canonicalize_generated_artifact(
            @encode.finish(out),
            bytes,
            nodes,
            max_depth,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      } catch {
        _ => return Err(OutputLimit)
      }
      bytes -= artifact.bytes
      nodes -= artifact.nodes
      // UTF-16 pointer ordering is the canonical ordering, independent of
      // node traversal order and escaped field-name source ordering.
      let mut position = ordered.length()
      while position > 0 {
        let prior = ordered[position - 1].0
        if pointer.length() > work || prior.length() > work - pointer.length() {
          return Err(OutputLimit)
        }
        work -= pointer.length() + prior.length()
        if @canonical.compare_utf16(prior, pointer) <= 0 {
          break
        }
        position -= 1
      }
      ordered.insert(position, (pointer, artifact))
    }
  }
  Ok(ordered.map(entry => entry.1))
}
