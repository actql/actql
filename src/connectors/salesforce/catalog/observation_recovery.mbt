///|
pub(all) enum CatalogObservationRecoveryIssue {
  InvalidInventory
  ResponseMismatch
  ForeignObservation
  Listing(ListingIssue)
  Sync(CatalogSyncIssue)
  Observation(CatalogObservationIssue)
} derive(Eq, Debug)

///|
/// Reproject retained provider bytes under the original exact observation.
/// This restores historical metadata only; it does not refresh permission,
/// schema, credential authority, or the right to dispatch a write.
pub fn recover_catalog_observation(
  expected_body : String,
  listing_bytes : Bytes,
  describe_bytes : Array[Bytes?],
  outcomes : Array[Int],
  binding : CatalogObservationBinding,
  list_use_cid : String,
  describe_use_cids : Array[String?],
  describe_response_sha256 : Array[String?],
  list_limits : ListLimits,
  describe_limits : DescribeLimits,
  max_observation_bytes : Int,
) -> Result[CatalogObservation, CatalogObservationRecoveryIssue] {
  let listing = match project_resource_listing(listing_bytes, list_limits) {
    Ok(value) => value
    Err(issue) => return Err(Listing(issue))
  }
  let count = listing.selected.length()
  if describe_bytes.length() != count ||
    outcomes.length() != count ||
    describe_use_cids.length() != count ||
    describe_response_sha256.length() != count {
    return Err(InvalidInventory)
  }
  let sync = begin_catalog_sync(listing)
  for index in 0..<count {
    let name = listing.selected[index].name
    match (describe_bytes[index], describe_response_sha256[index]) {
      (Some(bytes), Some(digest)) if @sha.hex(bytes) == digest => ()
      (None, None) => ()
      _ => return Err(ResponseMismatch)
    }
    let outcome = match (outcomes[index], describe_bytes[index]) {
      (1, Some(bytes)) =>
        catalog_sync_describe(sync, name, bytes, describe_limits)
      (2, _) => catalog_sync_unavailable(sync, name, PermissionDenied)
      (3, _) => catalog_sync_unavailable(sync, name, RateLimited)
      (4, _) => catalog_sync_unavailable(sync, name, ProviderUnavailable)
      (5, _) => catalog_sync_unavailable(sync, name, TransportInterrupted)
      (6, _) => catalog_sync_unavailable(sync, name, InvalidMetadata)
      (7, _) => catalog_sync_unavailable(sync, name, Cancelled)
      (8, _) => catalog_sync_unavailable(sync, name, NotFound)
      _ => return Err(InvalidInventory)
    }
    match outcome {
      Ok(_) => ()
      Err(issue) => return Err(Sync(issue))
    }
  }
  match finish_catalog_sync(sync) {
    Ok(_) => ()
    Err(issue) => return Err(Sync(issue))
  }
  let observation = match
    prepare_catalog_observation(
      sync, binding, list_use_cid, describe_use_cids, describe_response_sha256, max_observation_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  if catalog_observation_json(observation) != expected_body {
    return Err(ForeignObservation)
  }
  Ok(observation)
}

///|
/// Reproject a retained describe-only observation of named Resources. The
/// result is incomplete by construction and is never a complete Catalog.
pub fn recover_named_catalog_observation(
  expected_body : String,
  names : Array[String],
  describe_bytes : Array[Bytes?],
  outcomes : Array[Int],
  binding : CatalogObservationBinding,
  describe_use_cids : Array[String?],
  describe_response_sha256 : Array[String?],
  describe_limits : DescribeLimits,
  max_observation_bytes : Int,
) -> Result[CatalogObservation, CatalogObservationRecoveryIssue] {
  let sync = match begin_named_catalog_sync(names) {
    Ok(value) => value
    Err(issue) => return Err(Listing(issue))
  }
  let count = names.length()
  if describe_bytes.length() != count ||
    outcomes.length() != count ||
    describe_use_cids.length() != count ||
    describe_response_sha256.length() != count {
    return Err(InvalidInventory)
  }
  for index in 0..<count {
    let name = names[index]
    match (describe_bytes[index], describe_response_sha256[index]) {
      (Some(bytes), Some(digest)) if @sha.hex(bytes) == digest => ()
      (None, None) => ()
      _ => return Err(ResponseMismatch)
    }
    let outcome = match (outcomes[index], describe_bytes[index]) {
      (1, Some(bytes)) =>
        catalog_sync_describe(sync, name, bytes, describe_limits)
      (2, _) => catalog_sync_unavailable(sync, name, PermissionDenied)
      (3, _) => catalog_sync_unavailable(sync, name, RateLimited)
      (4, _) => catalog_sync_unavailable(sync, name, ProviderUnavailable)
      (5, _) => catalog_sync_unavailable(sync, name, TransportInterrupted)
      (6, _) => catalog_sync_unavailable(sync, name, InvalidMetadata)
      (7, _) => catalog_sync_unavailable(sync, name, Cancelled)
      (8, _) => catalog_sync_unavailable(sync, name, NotFound)
      _ => return Err(InvalidInventory)
    }
    match outcome {
      Ok(_) => ()
      Err(issue) => return Err(Sync(issue))
    }
  }
  match finish_catalog_sync(sync) {
    Ok(_) => ()
    Err(issue) => return Err(Sync(issue))
  }
  let observation = match
    prepare_catalog_observation(
      sync, binding, "", describe_use_cids, describe_response_sha256, max_observation_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  if catalog_observation_json(observation) != expected_body {
    return Err(ForeignObservation)
  }
  Ok(observation)
}
