///|
/// The REST API version every GitHub request of this connector states. A
/// fixture or acceptance run is valid only for this exact version.
pub let api_version : String = "2026-03-10"

///|
/// The connector's own `User-Agent`; GitHub refuses requests without one.
pub let user_agent : String = "actql-github-connector/0.1"

///|
/// The response headers the GitHub drivers read. The common exchange admits
/// only these names, under its caps.
pub let response_headers : Array[String] = [
  "link", "retry-after", "x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset",
  "x-ratelimit-resource",
]

///|
/// The non-secret request headers of every GitHub request. The credential
/// resource adds the Bearer token; nothing here carries a secret.
pub fn request_headers() -> Array[(String, String)] {
  [
    ("accept", "application/vnd.github+json"),
    ("x-github-api-version", api_version),
    ("user-agent", user_agent),
  ]
}

///|
/// A bounded header observation as the common exchange returns it.
pub(all) struct HeaderObservation {
  entries : Array[(String, String)]
} derive(Eq, Debug)

///|
pub fn header_value(headers : HeaderObservation, name : String) -> String? {
  for entry in headers.entries {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
fn decimal(text : String) -> Int64? {
  if text.length() == 0 || text.length() > 18 {
    return None
  }
  let mut value = 0L
  for index = 0; index < text.length(); index = index + 1 {
    let unit = text[index].to_int()
    if unit < 48 || unit > 57 {
      return None
    }
    value = value * 10L + (unit - 48).to_int64()
  }
  Some(value)
}

///|
/// What a rate-limit observation lets the next step do. `retry_after_seconds`
/// and `reset_epoch_seconds` are the provider's own basis; the connector never
/// waits on them itself.
pub(all) struct RateLimitBasis {
  retry_after_seconds : Int64?
  reset_epoch_seconds : Int64?
  remaining : Int64?
  resource : String?
} derive(Eq, Debug)

///|
pub fn rate_limit_basis(headers : HeaderObservation) -> RateLimitBasis {
  {
    retry_after_seconds: header_value(headers, "retry-after").bind(decimal),
    reset_epoch_seconds: header_value(headers, "x-ratelimit-reset").bind(
      decimal,
    ),
    remaining: header_value(headers, "x-ratelimit-remaining").bind(decimal),
    resource: header_value(headers, "x-ratelimit-resource"),
  }
}

///|
/// The meaning of a non-success status. GitHub reports primary and secondary
/// rate limits as 429 or 403; a 403 is a rate limit only when its headers say
/// so (`retry-after`, or no remaining quota). Every other 401/403 is an
/// authorization denial.
pub(all) enum ExchangeFailure {
  RateLimited(RateLimitBasis)
  PermissionDenied
  NotFound
  Gone
  Unprocessable
  ProviderUnavailable
  Unexpected(Int)
} derive(Eq, Debug)

///|
pub fn classify_failure(
  status : Int,
  headers : HeaderObservation,
) -> ExchangeFailure {
  let basis = rate_limit_basis(headers)
  if status == 429 {
    return RateLimited(basis)
  }
  if status == 403 &&
    (basis.retry_after_seconds is Some(_) || basis.remaining is Some(0L)) {
    return RateLimited(basis)
  }
  if status == 401 || status == 403 {
    return PermissionDenied
  }
  if status == 404 {
    return NotFound
  }
  if status == 410 {
    return Gone
  }
  if status == 422 {
    return Unprocessable
  }
  if status >= 500 && status <= 599 {
    return ProviderUnavailable
  }
  Unexpected(status)
}
