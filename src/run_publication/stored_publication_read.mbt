///|
pub(all) enum StoredPublicationReadIssue[E] {
  Read(E)
  Missing(String)
  Contract(PublicationContractIssue)
  References
  Bounds
}

///|
/// Read the complete dependency graph of one stored index into the existing
/// incremental commit validator. These admitted bodies are metadata, not a
/// grant, durability ACK or executable Run. The trusted Store caller keeps one
/// current snapshot and its original physical input loans through validation,
/// observed-commit confirmation and response transfer. Failure never writes or
/// substitutes a contract. All returned inputs remain owned by the preparation.
fn[E] load_stored_effect_free_publication(
  index : PublicationContract,
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
  read : (String) -> Result[String?, E],
  current : () -> Result[Unit, E],
  max_contracts : Int,
  max_total_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> Result[PublicationCommitPreparation, StoredPublicationReadIssue[E]] {
  if max_contracts < 8 ||
    max_total_bytes <= 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 ||
    max_workspace <= 0 {
    return Err(Bounds)
  }
  match current() {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  let projected = match project_public_index_read(index) {
    Ok(value) => value
    Err(_) => return Err(References)
  }
  if projected.namespace_id != namespace_id ||
    projected.authority_scope_cid != authority_scope_cid ||
    projected.run_definition_cid != definition_cid ||
    projected.durable_result_binding_cids.length() > max_contracts {
    return Err(References)
  }
  let retained : Map[String, PublicationContract] = Map([])
  let mut used = 0
  // This finite, invocation-local inventory only deduplicates immutable bodies.
  // It cannot retain authority, cache a physical current check or refill a loan.
  fn load(
    name : String,
    cid : String,
  ) -> Result[PublicationContract, StoredPublicationReadIssue[E]] {
    match current() {
      Err(issue) => return Err(Read(issue))
      Ok(_) => ()
    }
    if retained.get(cid) is Some(original) {
      if original.name != name {
        return Err(References)
      }
      return Ok(original)
    }
    if retained.length() >= max_contracts || !valid_contract_cid(cid) {
      return Err(Bounds)
    }
    let wire = match read(cid) {
      Ok(Some(value)) => value
      Ok(None) => return Err(Missing(cid))
      Err(issue) => return Err(Read(issue))
    }
    match current() {
      Err(issue) => return Err(Read(issue))
      Ok(_) => ()
    }
    let bytes = @utf8.encode(wire).length()
    if bytes > max_wire_bytes || bytes > max_total_bytes - used {
      return Err(Bounds)
    }
    let original = match
      admit_publication_contract(
        name, wire, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Contract(issue))
    }
    if original.identity != cid {
      return Err(References)
    }
    retained[cid] = original
    used += bytes
    Ok(original)
  }
  // Re-read even the supplied index by its own identity. A caller's admitted
  // candidate or a scalar successful lookup is not the stored complete chain.
  let stored_index = match load("public_index_entry", index.identity) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let root_names = [
    ("run_definition", definition_cid),
    ("run_invocation", projected.invocation_cid),
    ("result_manifest", projected.result_manifest_cid),
    ("publication_request", projected.publication_request_cid),
    ("publication_attempt", projected.publication_attempt_cid),
  ]
  let roots : Array[PublicationContract] = []
  for (name, cid) in root_names {
    match load(name, cid) {
      Ok(value) => roots.push(value)
      Err(issue) => return Err(issue)
    }
  }
  let (receipt_cid, captured_cid) = match
    public_index_run_observation_cids(stored_index) {
    Ok(value) => value
    Err(_) => return Err(References)
  }
  for
    (name, cid) in [
      ("run_receipt", receipt_cid),
      ("captured_run", captured_cid),
    ] {
    match load(name, cid) {
      Ok(value) => roots.push(value)
      Err(issue) => return Err(issue)
    }
  }
  let manifest = roots[2]
  let names = match manifest_result_names(manifest) {
    Ok(value) if value.length() <= max_contracts => value
    _ => return Err(Bounds)
  }
  let definitions : Array[PublicationContract] = []
  let artifacts : Array[PublicationContract] = []
  let derivations : Array[PublicationContract] = []
  let orderings : Array[PublicationContract] = []
  let retentions : Array[PublicationContract] = []
  let bindings : Array[PublicationContract] = []
  for name in names {
    guard result_read_definition_cid(manifest, name) is Ok(definition_cid) &&
      manifest_result_artifact_cid(manifest, name) is Some(artifact_cid) else {
      return Err(References)
    }
    let definition = match load("result_definition", definition_cid) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let artifact = match load("result_artifact", artifact_cid) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard contract_string(artifact, "ordering_evidence_cid")
      is Some(ordering_cid) &&
      contract_string(artifact, "effective_retention_policy_cid")
      is Some(retention_cid) else {
      return Err(References)
    }
    let ordering = match load("ordering_evidence", ordering_cid) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard ordering_derivation_cid(ordering) is Some(derivation_cid) else {
      return Err(References)
    }
    let derivation = match load("derivation_evidence", derivation_cid) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let retention = match load("result_retention_policy", retention_cid) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    definitions.push(definition)
    artifacts.push(artifact)
    orderings.push(ordering)
    derivations.push(derivation)
    if !retentions.any(value => value.identity == retention_cid) {
      retentions.push(retention)
    }
  }
  for cid in projected.durable_result_binding_cids {
    match load("durable_result_binding", cid) {
      Ok(value) => bindings.push(value)
      Err(issue) => return Err(issue)
    }
  }
  match current() {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  let preparation = start_effect_free_publication_commit_check(
    roots[0],
    roots[1],
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    bindings,
    manifest,
    roots[5],
    roots[6],
    roots[3],
    roots[4],
    stored_index,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
  )
  // All six inventories were created here and never exposed as mutable arrays.
  // The first complete validation is still required before a read view exists.
  let inputs = preparation.inputs.unwrap()
  preparation.inputs = Some({ ..inputs, origin: StoredInputs, })
  Ok(preparation)
}

///|
/// Resolve the actual public-index key and stored contract bodies through one
/// trusted same-snapshot namespace reader. None is a confirmed absent index,
/// not a missing Run or proof of nonexecution. The caller authenticates the
/// retained Run and current scope first; this function cannot mint either.
pub fn[E] read_stored_effect_free_publication(
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
  read : (String, String) -> Result[Bytes?, E],
  current : () -> Result[Unit, E],
  max_contracts : Int,
  max_total_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> Result[PublicationCommitPreparation?, StoredPublicationReadIssue[E]] {
  if max_contracts < 8 ||
    max_total_bytes <= 71 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 ||
    max_workspace <= 0 {
    return Err(Bounds)
  }
  let key = match
    publication_index_scope_storage_key(
      namespace_id, authority_scope_cid, definition_cid, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(References)
  }
  match current() {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  let selected = match read("public_index", key) {
    Ok(value) => value
    Err(issue) => return Err(Read(issue))
  }
  match current() {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  guard selected is Some(bytes) else { return Ok(None) }
  if bytes.length() != 71 {
    return Err(References)
  }
  let cid = @utf8.decode(bytes) catch { _ => return Err(References) }
  if !valid_contract_cid(cid) {
    return Err(References)
  }
  // Read the selected body's actual namespace once. The loader uses that same
  // immutable body at its index dependency, without another physical query.
  let index_bytes = match read("publication_contract", cid) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Missing(cid))
    Err(issue) => return Err(Read(issue))
  }
  match current() {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  if index_bytes.length() > max_wire_bytes ||
    index_bytes.length() > max_total_bytes - bytes.length() {
    return Err(Bounds)
  }
  let index_wire = @utf8.decode(index_bytes) catch {
    _ => return Err(References)
  }
  let index = match
    admit_publication_contract(
      "public_index_entry", index_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Contract(issue))
  }
  if index.identity != cid {
    return Err(References)
  }
  fn read_contract(
    wanted : String,
  ) -> Result[String?, StoredPublicationReadIssue[E]] {
    if wanted == cid {
      return Ok(Some(index_wire))
    }
    match read("publication_contract", wanted) {
      Ok(Some(body)) => {
        if body.length() > max_wire_bytes {
          return Err(Bounds)
        }
        let text = @utf8.decode(body) catch { _ => return Err(References) }
        Ok(Some(text))
      }
      Ok(None) => Ok(None)
      Err(issue) => Err(Read(issue))
    }
  }
  // Keep physical errors distinct from admission errors when adapting the raw
  // namespace port. Both remain refusal, never a confirmed missing dependency.
  match
    load_stored_effect_free_publication(
      index,
      namespace_id,
      authority_scope_cid,
      definition_cid,
      read_contract,
      () => current().map_err(issue => Read(issue)),
      max_contracts,
      max_total_bytes - bytes.length(),
      max_wire_bytes,
      max_nodes,
      max_depth,
      max_workspace,
    ) {
    Ok(value) => Ok(Some(value))
    Err(Read(issue)) => Err(issue)
    Err(Missing(cid)) => Err(Missing(cid))
    Err(Contract(issue)) => Err(Contract(issue))
    Err(References) => Err(References)
    Err(Bounds) => Err(Bounds)
  }
}
