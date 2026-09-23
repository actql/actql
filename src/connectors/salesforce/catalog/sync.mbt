///|
/// An external read failure is evidence of an incomplete observation, never
/// proof that the named resource does not exist.
pub(all) enum DescribeFailure {
  PermissionDenied
  RateLimited
  ProviderUnavailable
  TransportInterrupted
  InvalidMetadata
  Cancelled
} derive(Eq, Debug)

///|
pub(all) enum ResourceDescribeOutcome {
  Pending
  Described(ResourceMetadata)
  Unavailable(DescribeFailure)
}

///|
pub(all) enum CatalogSyncIssue {
  AlreadyFinished
  WrongResource
  NoPendingResource
  Incomplete
  Describe(DescribeIssue)
} derive(Eq, Debug)

///|
/// A single bounded catalog-sync occurrence. The adapter supplies HTTP bytes
/// and physical failures; this state owner decides completeness and identity.
pub struct CatalogSync {
  listing : ResourceListing
  outcomes : Array[ResourceDescribeOutcome]
  mut next_index : Int
  mut finished : Bool
}

///|
pub fn begin_catalog_sync(listing : ResourceListing) -> CatalogSync {
  let selected = []
  for entry in listing.selected {
    selected.push(entry)
  }
  let owned_listing = { ..listing, selected, }
  let outcomes = []
  for _ in owned_listing.selected {
    outcomes.push(Pending)
  }
  { listing: owned_listing, outcomes, next_index: 0, finished: false, }
}

///|
pub fn catalog_sync_next(v : CatalogSync) -> String? {
  if v.finished || v.next_index >= v.listing.selected.length() {
    None
  } else {
    Some(v.listing.selected[v.next_index].name)
  }
}

///|
fn check_sync_next(
  v : CatalogSync,
  name : String,
) -> Result[Int, CatalogSyncIssue] {
  if v.finished {
    return Err(AlreadyFinished)
  }
  if v.next_index >= v.listing.selected.length() {
    return Err(NoPendingResource)
  }
  if v.listing.selected[v.next_index].name != name {
    return Err(WrongResource)
  }
  Ok(v.next_index)
}

///|
/// A malformed describe completes this resource as unavailable and preserves
/// the issue for the caller. It cannot be silently skipped or retried under
/// the same observation after another resource has advanced.
pub fn catalog_sync_describe(
  v : CatalogSync,
  name : String,
  bytes : Bytes,
  limits : DescribeLimits,
) -> Result[Unit, CatalogSyncIssue] {
  let index = match check_sync_next(v, name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match project_describe(bytes, name, limits) {
    Ok(resource) => {
      let listed = v.listing.selected[index]
      if (resource.queryable && !listed.queryable) ||
        (resource.createable && !listed.createable) ||
        (resource.updateable && !listed.updateable) {
        v.outcomes[index] = Unavailable(InvalidMetadata)
        v.next_index += 1
        return Err(Describe(ResourceMismatch))
      }
      v.outcomes[index] = Described(resource)
      v.next_index += 1
      Ok(())
    }
    Err(issue) => {
      v.outcomes[index] = Unavailable(InvalidMetadata)
      v.next_index += 1
      Err(Describe(issue))
    }
  }
}

///|
pub fn catalog_sync_unavailable(
  v : CatalogSync,
  name : String,
  failure : DescribeFailure,
) -> Result[Unit, CatalogSyncIssue] {
  let index = match check_sync_next(v, name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  v.outcomes[index] = Unavailable(failure)
  v.next_index += 1
  Ok(())
}

///|
/// Cancellation is explicit: the next and all remaining resources are
/// incomplete, even if earlier describes succeeded.
pub fn cancel_catalog_sync(v : CatalogSync) -> Result[Unit, CatalogSyncIssue] {
  if v.finished {
    return Err(AlreadyFinished)
  }
  while v.next_index < v.outcomes.length() {
    v.outcomes[v.next_index] = Unavailable(Cancelled)
    v.next_index += 1
  }
  Ok(())
}

///|
pub fn finish_catalog_sync(v : CatalogSync) -> Result[Unit, CatalogSyncIssue] {
  if v.finished {
    return Err(AlreadyFinished)
  }
  if v.next_index != v.outcomes.length() {
    return Err(Incomplete)
  }
  v.finished = true
  Ok(())
}

///|
pub fn catalog_sync_is_complete(v : CatalogSync) -> Bool {
  if !v.finished || v.listing.truncated {
    return false
  }
  for outcome in v.outcomes {
    match outcome {
      Described(_) => ()
      _ => return false
    }
  }
  true
}

///|
/// Per-resource admission remains possible in a partial listing when that
/// resource itself was listed and fully described. Other resources stay
/// unconfirmed. This function does not establish current execution authority.
pub fn catalog_sync_resource(
  v : CatalogSync,
  name : String,
) -> Result[ResourceMetadata, ResourceSelectionIssue] {
  if !v.finished {
    return Err(DescribeRequired)
  }
  for index in 0..<v.listing.selected.length() {
    if v.listing.selected[index].name == name {
      return match v.outcomes[index] {
        Described(resource) => Ok(resource)
        _ => Err(DescribeRequired)
      }
    }
  }
  Err(if v.listing.truncated { ListingTruncated } else { NotVisible })
}

///|
pub fn catalog_sync_outcome(
  v : CatalogSync,
  name : String,
) -> ResourceDescribeOutcome? {
  for index in 0..<v.listing.selected.length() {
    if v.listing.selected[index].name == name {
      return Some(v.outcomes[index])
    }
  }
  None
}
