///|
/// Bounds for the evidence closure, independent of relation payload limits.
pub(all) struct CapturedEffectDependencyLimits {
  max_entries : Int
  max_total_bytes : Int
  max_depth : Int
  max_references : Int
} derive(Eq, Debug)

///|
pub(all) enum CapturedEffectDependencyIssue {
  InvalidLimits
  EntryLimit
  ByteLimit
  ReferenceLimit
  DepthLimit
  DuplicateIdentity
  MissingDependency
  WrongDependencyKind
  DependencyCycle
  UnusedDependency
  InvalidBody
} derive(Eq, Debug)

///|
/// These references are derived by typed contract admission, never supplied
/// as an unverified edge list in a saved inventory.
priv struct CapturedEffectDependencyReference {
  kind : String
  identity : String
}

///|
/// Body admission establishes the identity and classifies every reference.
/// This internal value is not mutation authority or evidence of Store custody.
priv struct CapturedEffectDependencyNode {
  kind : String
  identity : String
  canonical_bytes : Int
  references : Array[CapturedEffectDependencyReference]
}

///|
fn dependency_key(kind : String, identity : String) -> String {
  kind + "\u0000" + identity
}

///|
fn validate_captured_effect_dependency_graph(
  nodes : Array[CapturedEffectDependencyNode],
  roots : Array[CapturedEffectDependencyReference],
  envelope_bytes : Int,
  limits : CapturedEffectDependencyLimits,
) -> Result[Unit, CapturedEffectDependencyIssue] {
  if limits.max_entries < 0 ||
    limits.max_entries > 4096 ||
    limits.max_total_bytes < 1 ||
    limits.max_total_bytes > 16777216 ||
    limits.max_depth < 1 ||
    limits.max_depth > 64 ||
    limits.max_references < 0 ||
    limits.max_references > 65536 ||
    envelope_bytes < 0 {
    return Err(InvalidLimits)
  }
  if nodes.length() > limits.max_entries || roots.length() > limits.max_entries {
    return Err(EntryLimit)
  }
  if envelope_bytes > limits.max_total_bytes {
    return Err(ByteLimit)
  }
  let indices : Map[String, Int] = Map([])
  let identities : Map[String, Bool] = Map([])
  let mut bytes = envelope_bytes
  // Roots are references too; many selected Results cannot evade the
  // traversal budget merely because they have no upstream edges.
  if roots.length() > limits.max_references {
    return Err(ReferenceLimit)
  }
  let mut references = roots.length()
  for index in 0..<nodes.length() {
    let node = nodes[index]
    if node.kind.is_empty() ||
      !valid_contract_cid(node.identity) ||
      node.canonical_bytes < 1 {
      return Err(InvalidBody)
    }
    let key = dependency_key(node.kind, node.identity)
    if indices.contains(key) {
      return Err(DuplicateIdentity)
    }
    if node.canonical_bytes > limits.max_total_bytes - bytes {
      return Err(ByteLimit)
    }
    bytes += node.canonical_bytes
    if node.references.length() > limits.max_references - references {
      return Err(ReferenceLimit)
    }
    references += node.references.length()
    indices[key] = index
    identities[node.identity] = true
  }
  let colors : Array[Int] = Array::make(nodes.length(), 0)
  let heights : Array[Int] = Array::make(nodes.length(), 0)
  fn visit(
    reference : CapturedEffectDependencyReference,
    depth : Int,
  ) -> Result[Int, CapturedEffectDependencyIssue] {
    guard indices.get(dependency_key(reference.kind, reference.identity))
      is Some(index) else {
      return Err(
        if identities.contains(reference.identity) {
          WrongDependencyKind
        } else {
          MissingDependency
        },
      )
    }
    let node = nodes[index]
    if node.kind != reference.kind {
      return Err(WrongDependencyKind)
    }
    if depth > limits.max_depth {
      return Err(DepthLimit)
    }
    if colors[index] == 1 {
      return Err(DependencyCycle)
    }
    if colors[index] == 2 {
      if heights[index] > limits.max_depth - depth {
        return Err(DepthLimit)
      }
      return Ok(heights[index])
    }
    colors[index] = 1
    let mut height = 0
    for child in node.references {
      let child_height = match visit(child, depth + 1) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if child_height + 1 > height {
        height = child_height + 1
      }
    }
    heights[index] = height
    colors[index] = 2
    Ok(height)
  }
  let root_ids : Map[String, Bool] = Map([])
  for root in roots {
    let key = dependency_key(root.kind, root.identity)
    if root_ids.contains(key) {
      return Err(DuplicateIdentity)
    }
    root_ids[key] = true
    match visit(root, 0) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  for color in colors {
    if color != 2 {
      return Err(UnusedDependency)
    }
  }
  Ok(())
}
