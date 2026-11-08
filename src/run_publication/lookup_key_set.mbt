///|
fn compare_lookup_key_orders(a : Array[String], b : Array[String]) -> Int {
  for index in 0..<Int::min(a.length(), b.length()) {
    let compared = @canonical.compare_utf16(a[index], b[index])
    if compared != 0 {
      return compared
    }
  }
  a.length().compare(b.length())
}

///|
/// Existing typed equality keys, not capability envelopes or hash ordering.
/// Neither emitting nor receiving a reference identity can issue a reference.
fn emit_lookup_key_cell(
  value : @admitted.CheckedValue,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match value.value {
    @admitted.Reference(reference) =>
      @encode.string_value(writer, @admitted.reference_identity_cid(reference))
    _ => @admitted.emit_checked_wire_value(value, writer)
  }
}

///|
/// Constructor DATA for an already checked Source request owner. The caller
/// supplies actual typed request tuples and retains their original holdings.
/// No Source request, execution, reservation or permission is issued here.
pub fn issue_lookup_request_key_set(
  source_view_contract_cid : String,
  request_schema_cid : String,
  roles : Array[(String, @contract.Contract)],
  tuples : Array[Array[@admitted.CheckedValue]],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, AcquisitionRelationIssue] {
  if roles.is_empty() ||
    roles.length() > max_nodes ||
    tuples.length() > max_nodes {
    return Err(WrongEvidence)
  }
  let mut previous : String? = None
  for role_index, (name, contract) in roles {
    if name.is_empty() ||
      previous
      .map(prior => @canonical.compare_utf16(prior, name) >= 0)
      .unwrap_or(false) ||
      !@contract.key_comparable(contract, contract) {
      return Err(KeySetRole(role_index, name))
    }
    previous = Some(name)
  }
  let ordered : Array[(Array[String], Array[@admitted.CheckedValue])] = []
  for tuple_index, tuple in tuples {
    if tuple.length() != roles.length() {
      return Err(KeySetArity(tuple_index))
    }
    let keys = []
    for index, value in tuple {
      if !(@contract.type_equal(value.contract, roles[index].1, max_nodes) catch {
          _ => false
        }) {
        return Err(KeySetContract(tuple_index, index))
      }
      let key = match @admitted.typed_key_order_text(value) {
        Ok(key) => key
        Err(issue) => return Err(KeySetOrder(tuple_index, index, issue))
      }
      keys.push(key)
    }
    ordered.push((keys, tuple))
  }
  ordered.sort_by((a, b) => compare_lookup_key_orders(a.0, b.0))
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let body = try {
    @encode.begin_object(writer)
    @encode.key(writer, "key_roles")
    @encode.begin_array(writer)
    for (name, contract) in roles {
      @encode.begin_object(writer)
      @encode.key(writer, "request_role")
      @encode.string_value(writer, name)
      @encode.key(writer, "value_contract")
      @contract.emit_checked(contract, writer)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "request_schema_cid")
    @encode.string_value(writer, request_schema_cid)
    @encode.key(writer, "source_view_contract_cid")
    @encode.string_value(writer, source_view_contract_cid)
    @encode.key(writer, "tuples")
    @encode.begin_array(writer)
    let mut prior : Array[String]? = None
    for (order, tuple) in ordered {
      if prior
        .map(value => compare_lookup_key_orders(value, order) == 0)
        .unwrap_or(false) {
        continue
      }
      @encode.begin_array(writer)
      for cell in tuple {
        emit_lookup_key_cell(cell, writer)
      }
      @encode.end_array(writer)
      prior = Some(order)
    }
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-lookup-key-set/0.1")
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  seal_publication_contract(
    "request_key_set", body, max_bytes, max_nodes, max_depth,
  ).map_err(issue => Contract(issue))
}

///|
/// A receiving body uses the existing contract/value readers and typed order
/// law. JSON Schema uniqueItems alone cannot detect equivalent typed keys or
/// numeric ordering. This does not restore references from their CID cells.
fn lookup_key_set_order_valid(
  value : @json.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard canonical_value_wire(value, max_bytes, max_nodes, max_depth)
    is Some(wire) &&
    material_cursor(wire, max_bytes, max_nodes, max_depth) is Some(cursor) &&
    @decode.open_object(cursor) is Ok(object) &&
    @decode.lookup(object, "key_roles") is Some(roles_cursor) &&
    @decode.lookup(object, "tuples") is Some(tuples_cursor) &&
    @decode.array_length(roles_cursor) is Some(arity) &&
    arity > 0 &&
    @decode.array_length(tuples_cursor) is Some(count) &&
    @json.object_field(value, "tuples") is Some(@json.Array(canonical_tuples)) else {
    return false
  }
  let contracts : Array[@contract.Contract] = []
  let mut previous : String? = None
  for index in 0..<arity {
    guard @decode.element_at(roles_cursor, index) is Some(role_cursor) &&
      @decode.open_object(role_cursor) is Ok(role) &&
      @decode.lookup(role, "request_role") is Some(name_cursor) &&
      @decode.text(name_cursor) is Ok(name) &&
      !previous
      .map(prior => @canonical.compare_utf16(prior, name) >= 0)
      .unwrap_or(false) &&
      @decode.lookup(role, "value_contract") is Some(contract_cursor) &&
      @contract.read_checked(contract_cursor, {
        max_nodes,
        max_depth,
        max_text_bytes: max_bytes,
      })
      is Ok(contract) &&
      @contract.key_comparable(contract, contract) else {
      return false
    }
    contracts.push(contract)
    previous = Some(name)
  }
  let mut prior : Array[String]? = None
  for row in 0..<count {
    guard @decode.element_at(tuples_cursor, row) is Some(tuple) &&
      @decode.array_length(tuple) == Some(arity) &&
      @json.array_at(canonical_tuples, row)
      is Some(@json.Array(canonical_cells)) else {
      return false
    }
    let keys : Array[String] = []
    for column in 0..<arity {
      let contract = contracts[column]
      guard @decode.element_at(tuple, column) is Some(cell) else {
        return false
      }
      let key = match contract.shape {
        @contract.ResourceRef(..) | @contract.ContentRef(..) => {
          guard @decode.text(cell) is Ok(cid) && valid_contract_cid(cid) else {
            return false
          }
          cid
        }
        _ => {
          guard @admitted.admit(contract, cell, {
              max_nodes,
              max_depth,
              max_text_bytes: max_bytes,
            })
            is Ok(checked) &&
            @admitted.typed_key_order_text(checked) is Ok(key) else {
            return false
          }
          let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
            _ => return false
          }
          @admitted.emit_checked_wire_value(checked, writer) catch {
            _ => return false
          }
          let canonical = @encode.finish(writer) catch { _ => return false }
          guard @json.array_at(canonical_cells, column) is Some(original) &&
            canonical_value_wire(original, max_bytes, max_nodes, max_depth) ==
            Some(canonical) else {
            return false
          }
          key
        }
      }
      keys.push(key)
    }
    if prior
      .map(previous => compare_lookup_key_orders(previous, keys) >= 0)
      .unwrap_or(false) {
      return false
    }
    prior = Some(keys)
  }
  true
}
