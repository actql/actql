///|
pub(all) enum Section {
  SchemaSnapshots
  ConnectorCapabilities
  MappingContracts
  SourceViews
  CommandContracts
  ModelTaskContracts
  ContractRegistry
  ConnectorCatalogs
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_members : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidEnvelope
  IdentityMismatch
  NonCanonicalBytes
  UnsortedEvidence(Section)
  DuplicateSnapshot(String)
  DuplicateContract(String)
} derive(Eq, Debug)

///|
priv struct Entry {
  cursor : @decode.Cursor
  cid : String
  bytes : Int
  nodes : Int
}

///|
struct WireEnvironment {
  root : @decode.Cursor
  policy : @decode.Cursor
  cid : String
  sections : Array[Array[Entry]]
  bytes : Int
  nodes : Int
  members : Int
}

///|
struct Member {
  owner : WireEnvironment
  section : Section
  index : Int
  entry : Entry
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn position(s : Section) -> Int {
  match s {
    SchemaSnapshots => 0
    ConnectorCapabilities => 1
    MappingContracts => 2
    SourceViews => 3
    CommandContracts => 4
    ModelTaskContracts => 5
    ContractRegistry => 6
    ConnectorCatalogs => 7
  }
}

///|
fn section_name(s : Section) -> String {
  match s {
    SchemaSnapshots => "schema_snapshots"
    ConnectorCapabilities => "connector_capabilities"
    MappingContracts => "mapping_contracts"
    SourceViews => "source_views"
    CommandContracts => "command_contracts"
    ModelTaskContracts => "model_task_contracts"
    ContractRegistry => "contract_registry"
    ConnectorCatalogs => "connector_catalogs"
  }
}

///|
fn required(
  object : @decode.ObjectView,
  name : String,
) -> @decode.Cursor raise Stop {
  match @decode.required(object, name) {
    Ok(v) => v
    Err(_) => raise Stop(InvalidEnvelope)
  }
}

///|
fn string(object : @decode.ObjectView, name : String) -> String raise Stop {
  match @decode.text(required(object, name)) {
    Ok(v) => v
    Err(_) => raise Stop(InvalidEnvelope)
  }
}

///|
fn hash(
  cursor : @decode.Cursor,
  limits : Limits,
  omit : Bool,
) -> (String, Int, Int) raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_cursor(cursor, writer, omit)
  let (digest, bytes, nodes) = @encode.finish_hash_usage(writer)
  ("sha256:" + digest, bytes, nodes)
}

///|
/// Outer shape, canonical bytes, identity and ordered member integrity only.
/// This type cannot stand for Catalog closure, policy admission or Host authority.
pub fn read(
  bytes : Bytes,
  expected_cid : String,
  limits : Limits,
) -> Result[WireEnvironment, Issue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_members < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if expected_cid.length() != 71 || !expected_cid.has_prefix("sha256:") {
    return Err(IdentityMismatch)
  }
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) =>
      return Err(
        match e.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidEnvelope
        },
      )
  }
  let root = match
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(v) => v
    Err(_) => return Err(BudgetExceeded)
  }
  try {
    let object = match
      @decode.closed_object(root, [
        "version", "evidence_bundle_cid", "host_policy_profile", "schema_snapshots",
        "connector_capabilities", "mapping_contracts", "source_views", "command_contracts",
        "model_task_contracts", "contract_registry", "connector_catalogs",
      ]) {
      Ok(v) => v
      Err(_) => raise Stop(InvalidEnvelope)
    }
    if string(object, "version") != "actql-check-environment/0.1" {
      raise Stop(InvalidEnvelope)
    }
    if string(object, "evidence_bundle_cid") != expected_cid {
      raise Stop(IdentityMismatch)
    }
    let policy = required(object, "host_policy_profile")
    if @decode.object_length(policy) is None {
      raise Stop(InvalidEnvelope)
    }
    let (full_hash, size, nodes) = hash(root, limits, false)
    if full_hash != "sha256:" + @sha.hex(bytes) {
      raise Stop(NonCanonicalBytes)
    }
    let (identity, _, _) = hash(root, limits, true)
    if identity != expected_cid {
      raise Stop(IdentityMismatch)
    }
    let sections = []
    let mut members = 0
    let snapshots : Map[String, Bool] = Map([])
    for
      section in [
        SchemaSnapshots,
        ConnectorCapabilities,
        MappingContracts,
        SourceViews,
        CommandContracts,
        ModelTaskContracts,
        ContractRegistry,
        ConnectorCatalogs,
      ] {
      let array = required(object, section_name(section))
      let count = match @decode.array_length(array) {
        Some(v) => v
        None => raise Stop(InvalidEnvelope)
      }
      if count > limits.max_members - members {
        raise Stop(BudgetExceeded)
      }
      members += count
      let entries = []
      let mut previous : String? = None
      for i in 0..<count {
        let cursor = @decode.element_at(array, i).unwrap()
        if @decode.object_length(cursor) is None {
          raise Stop(InvalidEnvelope)
        }
        let (cid, member_bytes, member_nodes) = hash(cursor, limits, false)
        if previous is Some(p) {
          if cid < p {
            raise Stop(UnsortedEvidence(section))
          }
          if section == ContractRegistry && cid == p {
            raise Stop(DuplicateContract(cid))
          }
        }
        previous = Some(cid)
        if section == SchemaSnapshots {
          let source_ref = string(
            @decode.open_object(cursor).unwrap(),
            "source_ref",
          )
          if source_ref == "" {
            raise Stop(InvalidEnvelope)
          }
          if snapshots.contains(source_ref) {
            raise Stop(DuplicateSnapshot(source_ref))
          }
          snapshots[source_ref] = true
        }
        entries.push({ cursor, cid, bytes: member_bytes, nodes: member_nodes, })
      }
      sections.push(entries)
    }
    Ok({ root, policy, cid: identity, sections, bytes: size, nodes, members, })
  } catch {
    Stop(e) => Err(e)
    @encode.OutputLimit => Err(BudgetExceeded)
    _ => Err(NonCanonicalBytes)
  }
}

///|
pub fn cid(v : WireEnvironment) -> String {
  v.cid
}

///|
pub fn usage(v : WireEnvironment) -> (Int, Int, Int) {
  (v.bytes, v.nodes, v.members)
}

///|
pub fn host_policy(v : WireEnvironment) -> @decode.Cursor {
  v.policy
}

///|
pub fn member_count(v : WireEnvironment, s : Section) -> Int {
  v.sections[position(s)].length()
}

///|
pub fn member_at(v : WireEnvironment, s : Section, i : Int) -> Member? {
  v.sections[position(s)]
  .get(i)
  .map(entry => { owner: v, section: s, index: i, entry, })
}

///|
pub fn member_environment(v : Member) -> WireEnvironment {
  v.owner
}

///|
pub fn member_section(v : Member) -> Section {
  v.section
}

///|
pub fn member_index(v : Member) -> Int {
  v.index
}

///|
pub fn member_cid(v : Member) -> String {
  v.entry.cid
}

///|
pub fn member_body(v : Member) -> @decode.Cursor {
  v.entry.cursor
}

///|
pub fn emit(
  v : WireEnvironment,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_cursor(v.root, writer, false)
}

///|
pub fn emit_member(
  v : Member,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_cursor(v.entry.cursor, writer, false)
}

///|
/// Reuse the exact canonical member measurement from envelope admission.
pub fn member_usage(value : Member) -> (Int, Int) {
  (value.entry.bytes, value.entry.nodes)
}
