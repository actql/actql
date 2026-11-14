///|
// Immutable semantic preparation DATA only. The closed original Run/Read
// caller funds index/validation before entry, then actual geometry before
// issuance. It is no Resource owner, capacity token, read grant or ACK.
struct PreparedCapturedEffectDependencyInventory {
  bodies : Array[CapturedEffectDependencyBody]
  roots : Array[CapturedEffectDependencyBody]
  limits : CapturedEffectDependencyLimits
  geometry : @encode.EncodingConstructionGeometry
}

///|
fn emit_prepared_dependency_inventory(
  bodies : Array[CapturedEffectDependencyBody],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  for body in bodies {
    @encode.construction_work_step(writer, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "body")
    // Typed admission already owns this exact canonical value. A second
    // full parse of body.wire supplies no additional semantic obligation.
    @json.emit_value(body.value, writer)
    @encode.key(writer, "cid")
    @encode.string_value(writer, body.node.identity)
    @encode.key(writer, "kind")
    @encode.string_value(writer, body.node.kind)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
}

///|
// All closure/ref/depth rules remain exact. Public normal limits retain
//4096/16MiB. These larger bounds describe only this actually funded group.
pub fn prepare_captured_effect_dependency_inventory(
  bodies : Array[CapturedEffectDependencyBody],
  roots : Array[CapturedEffectDependencyBody],
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Result[
  PreparedCapturedEffectDependencyInventory,
  CapturedEffectDependencyIssue,
] {
  let entries = Int::max(bodies.length(), roots.length())
  let limits : CapturedEffectDependencyLimits = {
    max_entries: entries,
    max_total_bytes: 2147483647,
    max_depth: 64,
    max_references: 65536,
  }
  if !work(bodies.length()) || !work(roots.length()) {
    return Err(ReferenceLimit)
  }
  let held = bodies.copy()
  let held_roots = roots.copy()
  match
    validate_selected_captured_effect_dependency_bodies(
      held,
      held_roots,
      0,
      limits,
      prepared=true,
      work=Some(work),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let writer = @encode.work_construction_census_writer(
    2147483647, max_nodes, max_depth, work,
  ) catch {
    _ => return Err(InvalidLimits)
  }
  let geometry = try {
    emit_prepared_dependency_inventory(held, writer)
    @encode.finish_construction_measurement(writer)
  } catch {
    _ => return Err(ByteLimit)
  }
  // The exact final envelope includes all body text and metadata; Root/Read
  // policy and numeric growth must cover this SAME measured geometry.
  Ok({
    bodies: held,
    roots: held_roots,
    limits: { ..limits, max_total_bytes: geometry.bytes, },
    geometry,
  })
}

///|
pub fn prepared_captured_effect_dependency_inventory_geometry(
  value : PreparedCapturedEffectDependencyInventory,
) -> @encode.EncodingConstructionGeometry {
  value.geometry
}

///|
pub fn issue_prepared_captured_effect_dependency_inventory(
  value : PreparedCapturedEffectDependencyInventory,
  work : (Int) -> Bool,
) -> Result[CapturedEffectDependencyInventory, CapturedEffectDependencyIssue] {
  let geometry = value.geometry
  let writer = @encode.work_writer(
    geometry.bytes,
    geometry.nodes,
    geometry.depth,
    work,
  ) catch {
    _ => return Err(InvalidLimits)
  }
  // Owned ordering/key vectors were funded alongside the measured writer.
  // CID is a fixed SHA256 spelling; the composite preserves CID-then-kind
  // order exactly and the metered in-place sort allocates no sort scratch.
  let ordered : Array[(String, CapturedEffectDependencyBody)] = []
  let wire = try {
    for body in value.bodies {
      @encode.construction_work_step(writer, body.node.identity.length())
      @encode.construction_work_step(writer, body.node.kind.length() + 1)
      ordered.push((body.node.identity + "\u0000" + body.node.kind, body))
    }
    @encode.sort_construction_fields(ordered, writer)
    @encode.begin_array(writer)
    for (_, body) in ordered {
      @encode.construction_work_step(writer, 1)
      @encode.begin_object(writer)
      @encode.key(writer, "body")
      @json.emit_value(body.value, writer)
      @encode.key(writer, "cid")
      @encode.string_value(writer, body.node.identity)
      @encode.key(writer, "kind")
      @encode.string_value(writer, body.node.kind)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    let (wire, bytes, nodes, depth) = @encode.finish_text_usage(writer)
    if bytes != geometry.bytes ||
      nodes != geometry.nodes ||
      depth != geometry.depth {
      return Err(InvalidBody)
    }
    wire
  } catch {
    _ => return Err(ByteLimit)
  }
  let bodies = ordered.map(pair => pair.1)
  // Graph/body checks were completed on these immutable privately copied
  // originals. Sorting changes no edge; final exact size still binds all data.
  let mut body_bytes = 0
  for body in bodies {
    if body.node.canonical_bytes > geometry.bytes - body_bytes {
      return Err(ByteLimit)
    }
    body_bytes += body.node.canonical_bytes
  }
  if body_bytes > value.limits.max_total_bytes {
    return Err(ByteLimit)
  }
  Ok({ bodies, roots: value.roots, wire, })
}

///|
// Borrowed exact metadata for the caller's original numeric constructor
// quote. This traverses no body tree or wire and conveys no authority.
pub fn captured_effect_dependency_body_index_geometry(
  body : CapturedEffectDependencyBody,
) -> (Int, Int64) {
  let mut units = body.node.kind.length().to_int64() +
    body.node.identity.length().to_int64() +
    1L
  for reference in body.node.references {
    units += reference.kind.length().to_int64() +
      reference.identity.length().to_int64() +
      1L
  }
  (body.node.references.length(), units)
}

///|
/// Compare immutable semantic root DATA only. Physical Source/Result custody
/// and current authorization are independent, fresh obligations at each use.
pub fn captured_effect_dependency_inventory_matches_roots(
  inventory : CapturedEffectDependencyInventory,
  roots : Array[CapturedEffectDependencyBody],
  work? : ((Int) -> Bool)? = None,
) -> Bool {
  let expected : Map[String, String] = Map([])
  let found : Map[String, Bool] = Map([])
  for root in inventory.roots {
    if !dependency_validation_key_work(
        work,
        root.node.kind,
        root.node.identity,
        2,
      ) {
      return false
    }
    let key = dependency_key(root.node.kind, root.node.identity)
    match expected.get(key) {
      Some(wire) => if wire != root.wire { return false }
      None => expected[key] = root.wire
    }
  }
  for root in roots {
    if !dependency_validation_key_work(
        work,
        root.node.kind,
        root.node.identity,
        2,
      ) ||
      !dependency_validation_work(work, root.wire.length()) {
      return false
    }
    let key = dependency_key(root.node.kind, root.node.identity)
    guard expected.get(key) == Some(root.wire) else { return false }
    found[key] = true
  }
  found.length() == expected.length()
}
