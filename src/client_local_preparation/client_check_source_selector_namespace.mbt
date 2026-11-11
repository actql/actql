///|
/// Unfiltered SourceRequestContracts admitted for the exact installed range.
/// Host publication custody and current disclosure remain separate obligations.
pub struct ClientCheckSourceSelectorRange {
  priv environment : @checked.CheckEnvironment
  priv catalog : @environment.SourceRequestContracts
}

///|
pub fn client_program_check_source_selector_range(
  environment : @checked.CheckEnvironment,
  registrations : Array[@checked.CheckEnvironment],
) -> ClientCheckSourceSelectorRange? {
  source_selector_range(environment, registrations, None)
}

///|
/// Bind disclosure coverage to the SAME installed Catalog that the original
/// Request reuses. Equality of wire/CID cannot replace this nominal join.
pub fn client_program_check_prepared_source_selector_range(
  environment : @checked.CheckEnvironment,
  prepared : @publication.PreparedPublishedQueryEnvironment,
  registrations : Array[@checked.CheckEnvironment],
) -> ClientCheckSourceSelectorRange? {
  guard @publication.prepared_published_query_catalog(prepared, environment)
    is Ok(catalog) else {
    return None
  }
  source_selector_range(environment, registrations, Some(catalog))
}

///|
fn source_selector_range(
  environment : @checked.CheckEnvironment,
  registrations : Array[@checked.CheckEnvironment],
  original : @checked.PreparedSourceCatalog?,
) -> ClientCheckSourceSelectorRange? {
  if registrations.length() > 128 {
    return None
  }
  let mut remaining = 1000000
  let prepare = (owner : @checked.CheckEnvironment) => {
    let prepared = @checked.prepare_source_catalog(owner, {
      max_work: remaining,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 64,
    }).to_option()
    prepared.map(value => {
      remaining -= @checked.source_catalog_usage(value).work
      @checked.source_catalog_contracts(value)
    })
  }
  let catalog = match original {
    None => {
      guard prepare(environment) is Some(catalog) else { return None }
      catalog
    }
    Some(prepared) => {
      guard physical_equal(@checked.source_catalog_owner(prepared), environment) else {
        return None
      }
      // Reuse preserves every original reader dimension; current usage is
      // DATA, and a looser admitted depth cannot claim the old tighter bound.
      let limits = @checked.source_catalog_replay_limits(prepared)
      let spent = limits.max_work
      if spent > remaining ||
        limits.max_bytes > 1000000 ||
        limits.max_nodes > 100000 ||
        limits.max_depth > 64 {
        return None
      }
      remaining -= spent
      @checked.source_catalog_contracts(prepared)
    }
  }
  let count = @environment.source_request_usage(catalog).2
  if count > 1024 || count > remaining {
    return None
  }
  remaining -= count
  let expected : Map[String, Bool] = Map([])
  for index in 0..<count {
    let item = @environment.source_request_member(
      @environment.source_request_at(catalog, index).unwrap(),
    )
    expected[@environment.member_cid(item)] = false
  }
  for registration in registrations {
    guard prepare(registration) is Some(participant) else { return None }
    let count = @environment.source_request_usage(participant).2
    if count > remaining {
      return None
    }
    remaining -= count
    for index in 0..<count {
      let item = @environment.source_request_member(
        @environment.source_request_at(participant, index).unwrap(),
      )
      let cid = @environment.member_cid(item)
      if !expected.contains(cid) {
        return None
      }
      expected[cid] = true
    }
  }
  if expected.values().any(found => !found) {
    return None
  }
  Some({ environment, catalog, })
}

///|
/// An original-call projection capability, admitted only by the trusted Host
/// after complete registration custody and a fresh absence-disclosure decision.
pub struct ClientCheckSourceSelectorNamespace {
  priv name : String
  priv range : ClientCheckSourceSelectorRange
  priv context_ref : String
  priv program_revision : String
}

///|
pub fn client_program_check_source_selector_namespace(
  range : ClientCheckSourceSelectorRange,
  namespace_name : String,
  configuration_revision : String,
  context_ref : String,
  program_revision : String,
) -> ClientCheckSourceSelectorNamespace? {
  if namespace_name.is_empty() ||
    @utf8.encode(namespace_name).length() > 256 ||
    !check_selector_namespace_reference(configuration_revision, "sha256:") ||
    !check_selector_namespace_reference(context_ref, "ctx:") ||
    !check_selector_namespace_reference(program_revision, "rev:") {
    return None
  }
  Some({ name: namespace_name, range, context_ref, program_revision, })
}

///|
fn check_selector_namespace_reference(value : String, prefix : String) -> Bool {
  value.has_prefix(prefix) &&
  value.length() == prefix.length() + 64 &&
  value[prefix.length():]
  .to_owned()
  .iter()
  .all(character => {
    let code = character.to_int()
    (code >= 48 && code <= 57) || (code >= 97 && code <= 102)
  })
}
