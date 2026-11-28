///|
priv struct StoredSavedEffectFileRow {
  selected : StoredMockProjectWriteTarget
  row : @host.ClientEffectSavedFileRow
}

///|
fn prepare_saved_effect_file_targets(
  value : Instance,
  configuration : StoredRunConfiguration,
  environment : Int,
  application : @host.ClientEffectSavedApplication,
  at : String,
  now : Int64,
  work : (Int) -> Bool,
  fund : (Int, Int, Int) -> Bool,
) -> Result[Array[StoredSavedEffectFileRow], Int] {
  guard mock_project_request_configuration(value, environment)
    is Some((selected_configuration, check)) &&
    physical_equal(configuration, selected_configuration) else {
    return Err(-32)
  }
  let (members, rows) = application.ordered_count()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  guard fund(0, 32 + members * 16 + rows * 16, 8) else { return Err(-4) }
  let plans = Array(capacity=rows)
  let account = configuration.account
  let principal = configuration.tuple.principal
  for index in 0..<members {
    guard application.file_member(index)
      is Some((binding, reference, mapping, count)) else {
      return Err(-32)
    }
    if !work(check.write_targets.length()) {
      return Err(-10)
    }
    let mut found : StoredMockProjectWriteTarget? = None
    for target in check.write_targets {
      if target.binding_cid == binding &&
        target.write.mapping.mapping_ref == reference &&
        target.write.mapping.mapping_cid == mapping {
        if found is Some(_) {
          return Err(-32)
        }
        found = Some(target)
      }
    }
    guard found is Some(selected) else { return Err(-32) }
    let tuple : @authorization.AccessTuple = {
      principal,
      connection: selected.source.connection,
      resource: selected.write.mapping.resource,
      operation: "read",
    }
    guard @authorization.evaluate_account(account, tuple) is Allow(_) &&
      mock_project_write_visible(
        account,
        principal,
        selected.source,
        selected.write,
      ) &&
      application.authorize_file_target(
        account,
        { ..tuple, operation: "effect", },
        at,
        fund,
      ) else {
      return Err(-20)
    }
    for ordinal in 0..<count {
      match
        application.prepare_file_row(
          index, ordinal, binding, mapping, now, limits, fund,
        ) {
        Ok(row) => plans.push({ selected, row, })
        Err(_) => return Err(-31)
      }
    }
  }
  if plans.length() != rows {
    Err(-32)
  } else {
    Ok(plans)
  }
}
