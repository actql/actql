///|
/// Immutable references to existing runtime bundle identities. Membership is
/// neither installation evidence nor permission to install or activate a bundle.
struct RemoteBundleDistribution {
  runtime_bundle_cids : Array[String]
  distribution_cid : String
}

///|
fn distribution_body(
  runtime_bundle_cids : Array[String],
) -> Result[String, RemoteBundleIssue] {
  let writer = @encode.writer(65536, 1024, 2) catch {
    _ => return Err(InvalidBundle)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "runtime_bundle_cids")
    @encode.begin_array(writer)
    for cid in runtime_bundle_cids {
      @encode.string_value(writer, cid)
    }
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-runtime-bundle-distribution/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidBundle)
  }
}

///|
fn bundle_value_identity(body : String) -> Result[String, RemoteBundleIssue] {
  match @sha.text_hex(body) {
    Ok(digest) => Ok("sha256:" + digest)
    Err(_) => Err(InvalidBundle)
  }
}

///|
pub fn prepare_bundle_distribution(
  runtime_bundle_cids : Array[String],
) -> Result[RemoteBundleDistribution, RemoteBundleIssue] {
  // Each CID needs at least 74 JSON bytes. This allocation bound derives from
  // the control-wire budget, independently of a manifest's physical components.
  if runtime_bundle_cids.is_empty() || runtime_bundle_cids.length() > 65536 / 74 {
    return Err(InvalidBundle)
  }
  let owned = runtime_bundle_cids.copy()
  owned.sort()
  let mut previous = ""
  for cid in owned {
    if !valid_cid(cid) || cid == previous {
      return Err(InvalidBundle)
    }
    previous = cid
  }
  let body = match distribution_body(owned) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let distribution_cid = match bundle_value_identity(body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ runtime_bundle_cids: owned, distribution_cid, })
}

///|
pub fn bundle_distribution_identity(value : RemoteBundleDistribution) -> String {
  value.distribution_cid
}

///|
pub fn bundle_distribution_json(
  value : RemoteBundleDistribution,
) -> Result[String, RemoteBundleIssue] {
  if value.runtime_bundle_cids.is_empty() ||
    value.runtime_bundle_cids.length() > 65536 / 74 {
    return Err(InvalidBundle)
  }
  let mut previous = ""
  for cid in value.runtime_bundle_cids {
    if !valid_cid(cid) || (previous != "" && cid <= previous) {
      return Err(InvalidBundle)
    }
    previous = cid
  }
  let body = match distribution_body(value.runtime_bundle_cids) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match bundle_value_identity(body) {
    Ok(identity) if identity == value.distribution_cid => Ok(body)
    Ok(_) => Err(BundleIdentityMismatch)
    Err(issue) => Err(issue)
  }
}

///|
pub fn bundle_distribution_projection(
  value : RemoteBundleDistribution,
) -> Array[String] {
  let result = [value.distribution_cid]
  for cid in value.runtime_bundle_cids {
    result.push(cid)
  }
  result
}

///|
pub fn bundle_distribution_contains(
  value : RemoteBundleDistribution,
  runtime_bundle_cid : String,
) -> Bool {
  value.runtime_bundle_cids.contains(runtime_bundle_cid)
}

///|
fn bundle_control_object(
  body : String,
  fields : Array[String],
) -> @decode.ObjectView raise RemoteBundleDecodeStop {
  let node = match
    @source.parse_json_bytes(@utf8.encode(body), {
      max_input_bytes: 65536,
      max_nodes: 1024,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => raise RemoteBundleDecodeStop
  }
  let cursor = decoded(
    @decode.admit(node, {
      max_nodes: 1024,
      max_depth: 2,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }),
  )
  decoded(@decode.closed_object(cursor, fields))
}

///|
pub fn admit_bundle_distribution_json(
  body : String,
  claimed_distribution_cid : String,
) -> Result[RemoteBundleDistribution, RemoteBundleIssue] {
  try {
    let object = bundle_control_object(body, ["runtime_bundle_cids", "version"])
    if field(object, "version") !=
      "actql-remote-runtime-bundle-distribution/0.1" {
      raise RemoteBundleDecodeStop
    }
    let members_node = decoded(@decode.required(object, "runtime_bundle_cids"))
    let count = match @decode.array_length(members_node) {
      Some(value) if value > 0 && value <= 65536 / 74 => value
      _ => raise RemoteBundleDecodeStop
    }
    let members : Array[String] = []
    for index in 0..<count {
      members.push(
        decoded(@decode.text(@decode.element_at(members_node, index).unwrap())),
      )
    }
    let distribution = match prepare_bundle_distribution(members) {
      Ok(value) => value
      Err(_) => raise RemoteBundleDecodeStop
    }
    if bundle_distribution_json(distribution) != Ok(body) {
      raise RemoteBundleDecodeStop
    }
    if distribution.distribution_cid != claimed_distribution_cid {
      Err(BundleIdentityMismatch)
    } else {
      Ok(distribution)
    }
  } catch {
    RemoteBundleDecodeStop => Err(InvalidBundle)
  }
}
