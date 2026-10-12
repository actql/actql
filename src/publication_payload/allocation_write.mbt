///|
/// An exact trusted Host read from the original allocation namespace. This is
/// not evidence of exclusive directory acquisition or current authorization.
struct PublicationPayloadAllocationObservation {
  request : PublicationPayloadRequest
  revision : Int64
  body : Bytes
  allocation : PublicationPayloadAllocation
}

///|
/// A physical allocation write, bound to the same original unowned Writing
/// record. It neither advances that record nor creates another payload Owner.
struct PublicationPayloadAllocationWrite {
  record : PublicationPayloadRecord
  record_revision : Int
  previous : PublicationPayloadAllocationObservation?
  allocation : PublicationPayloadAllocation
  body : Bytes
}

///|
pub fn admit_observed_publication_payload_allocation(
  request : PublicationPayloadRequest,
  store_authority : String,
  storage_namespace : String,
  material_identity : String,
  physical_revision : Int64,
  body : Bytes,
) -> Result[PublicationPayloadAllocationObservation, PublicationPayloadIssue] {
  if store_authority != request.store_authority_cid ||
    storage_namespace != publication_payload_allocation_namespace() ||
    material_identity != request.material_generation_cid ||
    physical_revision < 0L {
    return Err(StateCollision)
  }
  match admit_publication_payload_allocation(request, body) {
    Err(issue) => Err(issue)
    Ok(allocation) =>
      Ok({ request, revision: physical_revision, body, allocation, })
  }
}

///|
fn allocation_writable(record : PublicationPayloadRecord) -> Bool {
  record.state == Writing &&
  record.ownership is None &&
  record.generation is None &&
  record.opaque_ownership_cid is None &&
  record.opaque_generation_cid is None
}

///|
fn prepare_allocation_write(
  record : PublicationPayloadRecord,
  previous : PublicationPayloadAllocationObservation?,
  allocation : PublicationPayloadAllocation,
) -> Result[PublicationPayloadAllocationWrite, PublicationPayloadIssue] {
  if !allocation_writable(record) {
    return Err(InvalidTransition)
  }
  if previous is Some(observed) &&
    (
      observed.request.request_cid != record.request.request_cid ||
      observed.revision == 9223372036854775807L
    ) {
    return Err(StateCollision)
  }
  Ok({
    record,
    record_revision: record.revision,
    previous,
    allocation,
    body: encode_publication_payload_allocation(
      allocation.name,
      allocation.ownership,
    ),
  })
}

///|
/// Preserve the Native allocation intent ordering and ordinal calculation.
/// None must come from the original Store's actual not-found observation, not
/// an incomplete list or an SDK assertion. The Host must recheck its original
/// Store and current authorization before attempting this exact physical CAS.
pub fn prepare_publication_payload_allocation_intent_write(
  record : PublicationPayloadRecord,
  previous : PublicationPayloadAllocationObservation?,
) -> Result[PublicationPayloadAllocationWrite, PublicationPayloadIssue] {
  let ordinal = match previous {
    None => 1L
    Some(observed) =>
      match
        next_publication_payload_allocation_ordinal(
          record.request,
          observed.allocation.name,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  prepare_allocation_write(record, previous, {
    name: prepare_publication_payload_allocation_name(record.request, ordinal),
    ownership: None,
  })
}

///|
/// Bind the original exclusive physical acquisition to its observed intent.
/// No pathname inspection can replace that acquisition. Preparing bytes alone
/// does not make ownership durable or permit opening a child directory/file.
pub fn prepare_publication_payload_allocation_ownership_write(
  record : PublicationPayloadRecord,
  intent : PublicationPayloadAllocationObservation,
  physical_ownership : PublicationPayloadOwnership,
) -> Result[PublicationPayloadAllocationWrite, PublicationPayloadIssue] {
  if intent.allocation.ownership is Some(_) {
    return Err(StateCollision)
  }
  prepare_allocation_write(record, Some(intent), {
    name: intent.allocation.name,
    ownership: Some(physical_ownership),
  })
}

///|
pub fn validate_publication_payload_allocation_write(
  write : PublicationPayloadAllocationWrite,
) -> Result[Unit, PublicationPayloadIssue] {
  if !allocation_writable(write.record) ||
    write.record.revision != write.record_revision {
    return Err(StateCollision)
  }
  Ok(())
}

///|
pub fn publication_payload_allocation_write_request(
  write : PublicationPayloadAllocationWrite,
) -> PublicationPayloadRequest {
  write.record.request
}

///|
pub fn publication_payload_allocation_write_previous_revision(
  write : PublicationPayloadAllocationWrite,
) -> Int64? {
  write.previous.map(observed => observed.revision)
}

///|
pub fn publication_payload_allocation_write_previous_body(
  write : PublicationPayloadAllocationWrite,
) -> Bytes? {
  write.previous.map(observed => observed.body)
}

///|
pub fn publication_payload_allocation_write_body(
  write : PublicationPayloadAllocationWrite,
) -> Bytes {
  write.body
}

///|
pub fn publication_payload_allocation_write_value(
  write : PublicationPayloadAllocationWrite,
) -> PublicationPayloadAllocation {
  write.allocation
}

///|
/// Private Host transport of the exact original namespace, CAS and bytes.
/// This envelope is neither an identity preimage nor a public Client contract.
pub fn publication_payload_allocation_write_json(
  write : PublicationPayloadAllocationWrite,
) -> Result[String, PublicationPayloadIssue] {
  match validate_publication_payload_allocation_write(write) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let writer = @encode.writer(65536, 32, 2) catch {
    _ => return Err(InvalidRecord)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "allocation_body")
    @encode.string_value(writer, @utf8.decode_lossy(write.body))
    @encode.key(writer, "expected_revision")
    match write.previous {
      None => @encode.null_value(writer)
      Some(previous) =>
        @encode.string_value(writer, previous.revision.to_string())
    }
    @encode.key(writer, "material_generation_cid")
    @encode.string_value(writer, write.record.request.material_generation_cid)
    @encode.key(writer, "namespace")
    @encode.string_value(writer, publication_payload_allocation_namespace())
    @encode.key(writer, "previous_body")
    match write.previous {
      None => @encode.null_value(writer)
      Some(previous) =>
        @encode.string_value(writer, @utf8.decode_lossy(previous.body))
    }
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, write.record.request.store_authority_cid)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidRecord)
  }
}

///|
/// Read-only confirmation of one original physical write, including lost ACK.
/// A different or later generation cannot resolve it. The caller still owns
/// uncertain acquisition/cleanup and must fence current Host authorization.
/// This never writes the Store, advances the payload, or authorizes retry.
pub fn confirm_observed_publication_payload_allocation_write(
  write : PublicationPayloadAllocationWrite,
  observed : PublicationPayloadAllocationObservation,
) -> Result[PublicationPayloadAllocationObservation, PublicationPayloadIssue] {
  match validate_publication_payload_allocation_write(write) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let successor = match write.previous {
    None => 0L
    Some(previous) => previous.revision + 1L
  }
  if observed.request.request_cid != write.record.request.request_cid ||
    observed.revision != successor ||
    observed.body != write.body {
    return Err(StateCollision)
  }
  Ok(observed)
}
