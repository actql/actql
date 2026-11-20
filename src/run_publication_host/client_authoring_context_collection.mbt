///|
/// Original grammar annotation collection dimensions. Paths and names are
/// borrowed/observed, not materialized; business JSON nodes named meta are OUT.
/// These are construction DATA only. The caller funds the fixed observer and
/// all subsequent collection/writer/output overlap on its original Request.
pub(all) struct ClientAuthoringCollectionGeometry {
  items : Int
  path_utf16 : Int64
  max_path_utf16 : Int
  max_quoted_key_bytes : Int
  meta_nodes : Int
  meta_fields : Int
  source_depth : Int
  work : Int64
} derive(Eq, Debug)

///|
priv struct ClientAuthoringCollectionObserver {
  mut items : Int
  mut paths : Int64
  mut max_path : Int
  mut max_key : Int
  mut meta_nodes : Int
  mut meta_fields : Int
  mut remaining : Int64
  mut work : Int64
  depth : Int
}

///|
fn authoring_collection_charge(
  state : ClientAuthoringCollectionObserver,
  units : Int64,
) -> Unit raise @encode.EncodeFailure {
  if units < 0L || units > state.remaining {
    raise @encode.OutputLimit
  }
  state.work += units
  state.remaining -= units
}

///|
// Indexed field access never allocates an ObjectView or an input-sized Map.
fn authoring_collection_field(
  node : @decode.Cursor,
  key : String,
  state : ClientAuthoringCollectionObserver,
) -> @decode.Cursor? raise @encode.EncodeFailure {
  authoring_collection_charge(state, 1L)
  for index in 0..<@decode.object_length(node).unwrap_or(0) {
    let (name, child) = @decode.field_at(node, index).unwrap()
    authoring_collection_charge(
      state,
      1L + name.length().to_int64() + key.length().to_int64(),
    )
    if name == key {
      return Some(child)
    }
  }
  None
}

///|
fn authoring_index_units(index : Int) -> Int {
  let mut value = index
  let mut units = 1
  while value >= 10 {
    value = value / 10
    units += 1
  }
  units
}

///|
fn authoring_collection_key_units(
  key : String,
  state : ClientAuthoringCollectionObserver,
) -> Int64 raise @encode.EncodeFailure {
  authoring_collection_charge(state, key.length().to_int64())
  guard @encode.quoted_string_construction_extent(key) is Some((bytes, units)) else {
    raise @encode.InvalidUnicode
  }
  if bytes > 2147483647L {
    raise @encode.OutputLimit
  }
  state.max_key = Int::max(state.max_key, bytes.to_int())
  units + 2L // The same original path's surrounding '[' and ']'.
}

///|
fn authoring_collection_annotation(
  node : @decode.Cursor,
  stage : Int,
  field : String,
  index : Int,
  name : String?,
  state : ClientAuthoringCollectionObserver,
) -> Unit raise @encode.EncodeFailure {
  guard authoring_collection_field(node, "meta", state) is Some(meta) else {
    return
  }
  let mut path = if stage < 0 {
    1L // '$'
  } else {
    13L + authoring_index_units(stage).to_int64() // '$["stages"][' + index + ']'
  }
  if field != "" {
    path += authoring_collection_key_units(field, state)
    if index >= 0 {
      path += 2L + authoring_index_units(index).to_int64()
    } else if name is Some(name) {
      path += authoring_collection_key_units(name, state)
    } else {
      raise @encode.InvalidStructure
    }
  }
  if path > 2147483647L || state.items == 2147483647 {
    raise @encode.OutputLimit
  }
  // The first size observation only follows the admitted last-child spine.
  // Fund it before entry, then admit the full known node/field walk before
  // the existing no-copy geometry observer. Fields <= nodes-1 is structural.
  if state.remaining < state.depth.to_int64() + 1L {
    raise @encode.OutputLimit
  }
  let (nodes, spine_work) = @decode.observe_subtree_size(meta)
  authoring_collection_charge(state, spine_work)
  let ceiling = 2L * nodes.to_int64() + state.depth.to_int64() + 1L
  if state.remaining < ceiling {
    raise @encode.OutputLimit
  }
  let shape = @decode.observe_subtree_construction_geometry(meta)
  authoring_collection_charge(state, shape.work)
  if state.meta_nodes.to_int64() + shape.nodes.to_int64() > 2147483647L ||
    state.meta_fields.to_int64() + shape.fields.to_int64() > 2147483647L {
    raise @encode.OutputLimit
  }
  state.items += 1
  state.paths += path
  state.max_path = Int::max(state.max_path, path.to_int())
  state.meta_nodes += shape.nodes
  state.meta_fields += shape.fields
}

///|
fn authoring_collection_declarations(
  node : @decode.Cursor,
  stage : Int,
  field : String,
  state : ClientAuthoringCollectionObserver,
) -> Unit raise @encode.EncodeFailure {
  guard authoring_collection_field(node, field, state) is Some(declarations) else {
    return
  }
  for index in 0..<@decode.object_length(declarations).unwrap_or(0) {
    let (name, declaration) = @decode.field_at(declarations, index).unwrap()
    authoring_collection_charge(state, 1L)
    authoring_collection_annotation(
      declaration,
      stage,
      field,
      -1,
      Some(name),
      state,
    )
  }
}

///|
/// Observe the same finite grammar-owned locations as the existing issuer.
/// This is a constructor inventory, not a second validator or meta classifier
/// for arbitrary user values. It constructs no path String, item vector, Map,
/// metadata tree or wire. Known spent visits survive an exhausted observation.
pub fn observe_client_authoring_collection_geometry(
  owner : PreparedClientProgram,
  max_work : Int64,
) -> (
  Result[ClientAuthoringCollectionGeometry, ClientAuthoringContextIssue],
  Int64,
) {
  if max_work < 0L {
    return (Err(Encoding), 0L)
  }
  let root = @syntax.program_body(owner.source)
  // Existing collector keeps a stage prefix and one fixed declaration-field
  // path even when that group has no annotations. The longest fixed quoted
  // field is "bindings" (10 units); per-name paths are now built only for meta.
  let stages = @syntax.stages(owner.source).length()
  let prefix = if stages == 0 {
    1
  } else {
    13 + authoring_index_units(stages - 1)
  }
  let state : ClientAuthoringCollectionObserver = {
    items: 0,
    paths: 0L,
    max_path: Int::max(13, prefix + 11),
    max_key: 10,
    meta_nodes: 0,
    meta_fields: 0,
    remaining: max_work,
    work: 0L,
    depth: @decode.admission_usage(root).depth,
  }
  let result : Result[
    ClientAuthoringCollectionGeometry,
    ClientAuthoringContextIssue,
  ] = try {
    authoring_collection_annotation(root, -1, "", -1, None, state)
    for field in ["params", "bindings", "results"] {
      authoring_collection_declarations(root, -1, field, state)
    }
    for index, stage in @syntax.stages(owner.source) {
      let node = @syntax.stage_body(stage)
      authoring_collection_charge(state, 1L)
      authoring_collection_annotation(node, index, "", -1, None, state)
      for field in ["inputs", "results", "effects"] {
        authoring_collection_declarations(node, index, field, state)
      }
      if authoring_collection_field(node, "steps", state) is Some(steps) {
        for step in 0..<@decode.array_length(steps).unwrap_or(0) {
          authoring_collection_charge(state, 1L)
          authoring_collection_annotation(
            @decode.element_at(steps, step).unwrap(),
            index,
            "steps",
            step,
            None,
            state,
          )
        }
      }
    }
    Ok({
      items: state.items,
      path_utf16: state.paths,
      max_path_utf16: state.max_path,
      max_quoted_key_bytes: state.max_key,
      meta_nodes: state.meta_nodes,
      meta_fields: state.meta_fields,
      source_depth: state.depth,
      work: state.work,
    })
  } catch {
    _ => Err(Encoding)
  }
  (result, state.work)
}
