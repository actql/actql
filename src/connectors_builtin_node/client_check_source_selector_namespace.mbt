///|
/// Unfiltered SourceRequestContracts admitted for the exact installed range.
/// Host publication custody and current disclosure remain separate obligations.
pub struct ClientCheckSourceSelectorRange {
  priv environment : @program_check.CheckEnvironment
  priv catalog : @check_environment.SourceRequestContracts
}

///|
#export_name("clientProgramCheckSourceSelectorRange")
pub fn client_program_check_source_selector_range(
  environment : @program_check.CheckEnvironment,
  registrations : Array[@program_check.CheckEnvironment],
) -> ClientCheckSourceSelectorRange? {
  if registrations.length() > 128 {
    return None
  }
  let mut remaining = 1000000
  let prepare = (owner : @program_check.CheckEnvironment) => {
    let prepared = @program_check.prepare_source_catalog(owner, {
      max_work: remaining,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 64,
    }).to_option()
    prepared.map(value => {
      remaining -= @program_check.source_catalog_usage(value).work
      @program_check.source_catalog_contracts(value)
    })
  }
  guard prepare(environment) is Some(catalog) else { return None }
  let count = @check_environment.source_request_usage(catalog).2
  if count > 1024 || count > remaining {
    return None
  }
  remaining -= count
  let expected : Map[String, Bool] = Map([])
  for index in 0..<count {
    let item = @check_environment.source_request_member(
      @check_environment.source_request_at(catalog, index).unwrap(),
    )
    expected[@check_environment.member_cid(item)] = false
  }
  for registration in registrations {
    guard prepare(registration) is Some(participant) else { return None }
    let count = @check_environment.source_request_usage(participant).2
    if count > remaining {
      return None
    }
    remaining -= count
    for index in 0..<count {
      let item = @check_environment.source_request_member(
        @check_environment.source_request_at(participant, index).unwrap(),
      )
      let cid = @check_environment.member_cid(item)
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
#export_name("clientProgramCheckSourceSelectorNamespace")
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
