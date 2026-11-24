///|
let prepared_file_publication_format : String = "actql-native-prepared-file-publication/0.1"

///|
fn prepared_file_publication_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let digit = value[index]
    if !((digit >= '0' && digit <= '9') || (digit >= 'a' && digit <= 'f')) {
      return false
    }
  }
  true
}

///|
fn prepared_file_publication_wire(
  request_cid : String,
  attempt_cid : String,
  receipt_cid : String,
  committed_at : String,
  generations : Array[String],
  max_bytes : Int,
  max_nodes : Int,
) -> Result[String, NativePublicationStoreIssue] {
  if generations.is_empty() ||
    committed_at.is_empty() ||
    committed_at.length() > 64 {
    return Err(InvalidConfiguration)
  }
  try {
    let writer = @encode.writer(max_bytes, max_nodes, 2)
    @encode.begin_array(writer)
    for
      field in [
        prepared_file_publication_format, request_cid, attempt_cid, receipt_cid,
        committed_at,
      ] {
      @encode.string_value(writer, field)
    }
    let seen : Map[String, Bool] = Map([])
    for generation in generations {
      if !prepared_file_publication_cid(generation) || seen.contains(generation) {
        return Err(InvalidConfiguration)
      }
      seen[generation] = true
      @encode.string_value(writer, generation)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidConfiguration)
  }
}

///|
/// Keep the exact publication occurrence recoverable before entering any
/// payload writer. The immutable private row follows the existing scoped key.
pub fn Store::retain_prepared_file_publication(
  self : Store,
  prepared : NativePreparedFilePublication,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    if self.closed {
      return Err(Closed)
    }
    if self.retiring {
      return Err(CleanupPending)
    }
    guard @publication.publication_contract_name(prepared.attempt) ==
      "publication_attempt" &&
      @publication.publication_contract_name(prepared.receipt) == "run_receipt" else {
      return Err(InvalidConfiguration)
    }
    let context = match
      @publication.project_publication_request_context(prepared.request) {
      Ok(value) => value
      Err(_) => return Err(InvalidConfiguration)
    }
    let key = match
      publication_commit_key(
        @publication.publication_index_scope_storage_key(
          context.namespace_id,
          context.authority_scope_cid,
          context.run_definition_cid,
          max_wire_bytes,
          max_nodes,
          max_depth,
        ),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let wire = match
      prepared_file_publication_wire(
        @publication.publication_contract_identity(prepared.request),
        @publication.publication_contract_identity(prepared.attempt),
        @publication.publication_contract_identity(prepared.receipt),
        prepared.committed_at,
        prepared.material_generations,
        Int::min(max_wire_bytes, self.max_record_bytes),
        max_nodes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    for contract in [prepared.request, prepared.attempt, prepared.receipt] {
      match put_publication_contract(self, contract) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    self.retain_exact_publication_body(
      "prepared_publication_index",
      key,
      @utf8.encode(wire),
    )
  })
}

///|
/// Read only the original Run's private preparation and its exact contracts.
pub fn Store::inspect_prepared_effectful_publication(
  self : Store,
  namespace_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[NativePreparedFilePublication?, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    if self.closed {
      return Err(Closed)
    }
    if self.retiring {
      return Err(CleanupPending)
    }
    let key = match
      publication_commit_key(
        @publication.publication_index_scope_storage_key(
          namespace_id, authority_scope_cid, run_definition_cid, max_wire_bytes,
          max_nodes, max_depth,
        ),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match self.read_prepared_file_publication(key, max_wire_bytes, max_nodes) {
      Ok(None) => Ok(None)
      Ok(Some(prepared)) => {
        guard @publication.project_publication_request_context(prepared.request)
          is Ok(context) &&
          context.namespace_id == namespace_id &&
          context.authority_scope_cid == authority_scope_cid &&
          context.run_definition_cid == run_definition_cid else {
          return Err(StateCollision)
        }
        Ok(Some(prepared))
      }
      Err(issue) => Err(issue)
    }
  })
}

///|
fn Store::read_prepared_file_publication(
  self : Store,
  key : String,
  max_wire_bytes : Int,
  max_nodes : Int,
) -> Result[NativePreparedFilePublication?, NativePublicationStoreIssue] {
  let stored = match self.database.read("prepared_publication_index", key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Database(issue))
  }
  let max_bytes = Int::min(max_wire_bytes, self.max_record_bytes)
  guard stored.revision == 0L &&
    @source.parse_json_bytes_preserving(stored.body, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth: 2,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes,
      max_depth: 2,
      max_string_bytes: 71,
      max_total_string_bytes: max_bytes,
    })
    is Ok(cursor) &&
    @decode.elements(cursor) is Ok(elements) &&
    elements.length() > 5 else {
    return Err(StateCollision)
  }
  let fields = []
  for element in elements {
    guard @decode.text(element) is Ok(text) else { return Err(StateCollision) }
    fields.push(text)
  }
  let format = fields[0]
  let request_cid = fields[1]
  let attempt_cid = fields[2]
  let receipt_cid = fields[3]
  let committed_at = fields[4]
  let material_generations = fields[5:].to_owned()
  if format != prepared_file_publication_format ||
    !prepared_file_publication_cid(request_cid) ||
    !prepared_file_publication_cid(attempt_cid) ||
    !prepared_file_publication_cid(receipt_cid) {
    return Err(StateCollision)
  }
  guard prepared_file_publication_wire(
      request_cid, attempt_cid, receipt_cid, committed_at, material_generations,
      max_bytes, max_nodes,
    )
    is Ok(wire) &&
    @utf8.encode(wire) == stored.body else {
    return Err(StateCollision)
  }
  let request = match
    load_publication_contract(self, "publication_request", request_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let attempt = match
    load_publication_contract(self, "publication_attempt", attempt_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let receipt = match
    load_publication_contract(self, "run_receipt", receipt_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(Some({ request, attempt, receipt, committed_at, material_generations, }))
}
