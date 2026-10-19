///|
/// Bounds for the trusted application's ordinary file and JSON inputs. These
/// are managed operation limits, not an allocation certificate or an RSS cap.
priv struct HolderEffectHostOrdinaryLimits {
  read_ceiling : Int
  catalog_read_ceiling : Int64
  catalog_json_limits : @decode.Limits
  diagnostic_ceiling : Int
}

///|
fn holder_effect_host_ordinary_limits(
  file_limit : Int64,
  record_limit : Int64,
) -> HolderEffectHostOrdinaryLimits? {
  guard file_limit > 0L && record_limit > 0L && record_limit <= 2147483647L else {
    return None
  }
  let read_ceiling = if file_limit > 1000000L {
    1000000
  } else {
    file_limit.to_int()
  }
  Some({
    read_ceiling,
    catalog_read_ceiling: record_limit,
    catalog_json_limits: {
      max_nodes: 1000000,
      max_depth: 64,
      max_string_bytes: record_limit.to_int(),
      max_total_string_bytes: record_limit.to_int(),
    },
    diagnostic_ceiling: 4096,
  })
}

///|
/// Ordinary Host entry is sufficient to acquire bounded platform resources.
/// No mapped Read or startup-history token is manufactured here. A selected
/// explicit Read installation continues through the separate physical path.
fn prepare_holder_effect_host_ordinary_scope(
  site : @site.ExecutionSite,
  file_limit : Int64,
  record_limit : Int64,
) -> HolderEffectHostSetupScope? {
  guard holder_effect_host_ordinary_limits(file_limit, record_limit)
    is Some(limits) else {
    return None
  }
  Some({
    site,
    profile: None,
    ordinary: Some(limits),
    preparation_binding: None,
    current_binding: None,
    read_domain: None,
    read_parent: None,
    caller_operation: None,
    operation: None,
    holding: None,
    depth: 1,
    pending: None,
    cleanup: None,
    retiring: false,
  })
}

///|
fn holder_effect_host_scope_read_ceiling(
  scope : HolderEffectHostSetupScope,
) -> Int {
  match scope.ordinary {
    Some(limits) => limits.read_ceiling
    None => scope.profile.unwrap().read_ceiling
  }
}

///|
fn holder_effect_host_scope_diagnostic_ceiling(
  scope : HolderEffectHostSetupScope,
) -> Int {
  match scope.ordinary {
    Some(limits) => limits.diagnostic_ceiling
    None => scope.profile.unwrap().diagnostic_ceiling
  }
}

///|
fn holder_effect_host_scope_catalog_limits(
  scope : HolderEffectHostSetupScope,
) -> (Int64, @decode.Limits) {
  match scope.ordinary {
    Some(limits) => (limits.catalog_read_ceiling, limits.catalog_json_limits)
    None => {
      let profile = scope.profile.unwrap()
      (profile.catalog_read_ceiling, profile.catalog_json_limits)
    }
  }
}
