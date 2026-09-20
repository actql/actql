///|
pub(all) enum DeliveryGrantUsageIssue {
  DeliveryGrantUsageWrongContract
  DeliveryGrantUsageReferenceMismatch
  DeliveryGrantUsageExhausted
  DeliveryGrantUsageInvalidWire
  DeliveryGrantUsageEncoding
} derive(Eq, Debug)

///|
struct DeliveryGrantUsageClaim {
  wire : String
  newly_claimed : Bool
}

///|
fn delivery_grant_usage_attempts(
  value : @json.CanonicalValue,
) -> Array[String]? {
  guard @json.object_field(value, "delivery_attempt_cids")
    is Some(@json.Array(items)) else {
    return None
  }
  let attempts : Array[String] = []
  for item in @json.array_values(items) {
    guard item is @json.String(identity) && valid_contract_cid(identity) else {
      return None
    }
    attempts.push(identity)
  }
  Some(attempts)
}

///|
fn encode_delivery_grant_usage(
  grant_cid : String,
  max_uses : Int,
  attempts : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, DeliveryGrantUsageIssue] {
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryGrantUsageEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "delivery_attempt_cids")
    @encode.begin_array(writer)
    for identity in attempts {
      @encode.string_value(writer, identity)
    }
    @encode.end_array(writer)
    @encode.key(writer, "grant_cid")
    @encode.string_value(writer, grant_cid)
    @encode.key(writer, "max_uses")
    @encode.number_value(writer, max_uses.to_double())
    @encode.key(writer, "use_count")
    @encode.number_value(writer, attempts.length().to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-result-read-grant-usage/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(DeliveryGrantUsageEncoding)
  }
}

///|
/// Prepare the complete next durable use set for one read grant. A Store CAS
/// installs this body atomically; an exact attempt already in the set is a
/// retry and consumes no additional use.
pub fn prepare_delivery_grant_usage_claim(
  grant : PublicationContract,
  existing_wire : String?,
  attempt : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[DeliveryGrantUsageClaim, DeliveryGrantUsageIssue] {
  if grant.name != "result_read_grant" || attempt.name != "delivery_attempt" {
    return Err(DeliveryGrantUsageWrongContract)
  }
  if contract_string(attempt, "result_read_grant_cid") != Some(grant.identity) {
    return Err(DeliveryGrantUsageReferenceMismatch)
  }
  guard contract_count(grant, "max_uses") is Some(max_uses64) &&
    max_uses64 > 0L &&
    max_uses64 <= 2147483647L else {
    return Err(DeliveryGrantUsageReferenceMismatch)
  }
  let max_uses = max_uses64.to_int()
  let attempts = match existing_wire {
    None => []
    Some(wire) => {
      let value = match
        parse_contract_wire(wire, max_wire_bytes, max_nodes, max_depth) {
        Ok(value) => value
        Err(_) => return Err(DeliveryGrantUsageInvalidWire)
      }
      guard @json.object_fields(value) is Some(fields) &&
        fields.length() == 5 &&
        optional_string(@json.object_field(value, "version")) ==
        Some("actql-result-read-grant-usage/0.1") &&
        optional_string(@json.object_field(value, "grant_cid")) ==
        Some(grant.identity) &&
        delivery_optional_count(@json.object_field(value, "max_uses")) ==
        Some(max_uses64) &&
        delivery_grant_usage_attempts(value) is Some(attempts) &&
        delivery_optional_count(@json.object_field(value, "use_count")) ==
        Some(attempts.length().to_int64()) else {
        return Err(DeliveryGrantUsageInvalidWire)
      }
      let ordered = attempts.copy()
      ordered.sort_by(@canonical.compare_utf16)
      if ordered != attempts || attempts.length() > max_uses {
        return Err(DeliveryGrantUsageInvalidWire)
      }
      for index = 1; index < attempts.length(); index = index + 1 {
        if attempts[index - 1] == attempts[index] {
          return Err(DeliveryGrantUsageInvalidWire)
        }
      }
      attempts
    }
  }
  if attempts.contains(attempt.identity) {
    let wire = match existing_wire {
      Some(value) => value
      None => return Err(DeliveryGrantUsageInvalidWire)
    }
    return Ok({ wire, newly_claimed: false, })
  }
  if attempts.length() >= max_uses {
    return Err(DeliveryGrantUsageExhausted)
  }
  attempts.push(attempt.identity)
  attempts.sort_by(@canonical.compare_utf16)
  let wire = match
    encode_delivery_grant_usage(
      grant.identity,
      max_uses,
      attempts,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ wire, newly_claimed: true, })
}

///|
pub fn delivery_grant_usage_claim_wire(
  claim : DeliveryGrantUsageClaim,
) -> String {
  claim.wire
}

///|
pub fn delivery_grant_usage_claim_is_new(
  claim : DeliveryGrantUsageClaim,
) -> Bool {
  claim.newly_claimed
}
