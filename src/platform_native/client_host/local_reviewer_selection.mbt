///|
// Explicit syntax selection only. The actual adopted Host must separately
// bind this original file, current Account and original Checkpoint before the
// existing signature Owner can use a registration. No permission is cached.
struct NativeLocalEffectReviewerSelection {
  enabled : Bool
  principal : String
  connection : String
  key_id : String
  reviewer_id : String
  public_key_pem : String
} derive(Eq)

///|
pub(all) enum NativeLocalEffectReviewerIssue {
  InvalidReviewerSelection
  ReviewerSelectionLimitExceeded
}

///|
priv suberror LocalReviewerSelectionStop {
  LocalReviewerSelectionStop(NativeLocalEffectReviewerIssue)
}

///|
fn[T] local_reviewer_decoded(
  result : Result[T, @decode.Issue],
) -> T raise LocalReviewerSelectionStop {
  match result {
    Ok(value) => value
    Err(_) => raise LocalReviewerSelectionStop(InvalidReviewerSelection)
  }
}

///|
fn local_reviewer_text(
  fields : @decode.ObjectView,
  key : String,
  max_bytes : Int,
) -> String raise LocalReviewerSelectionStop {
  let value = local_reviewer_decoded(
    @decode.text(local_reviewer_decoded(@decode.required(fields, key))),
  )
  if value.is_empty() || value.contains("\u{0}") {
    raise LocalReviewerSelectionStop(InvalidReviewerSelection)
  }
  if @utf8.encode(value).length() > max_bytes {
    raise LocalReviewerSelectionStop(ReviewerSelectionLimitExceeded)
  }
  value
}

///|
/// Decode one bounded, duplicate-free installation original with the existing
/// value-preserving reader. This is not a trusted Reviewer registration, key
/// verification, approval, evidence disclosure, resume claim or credential.
/// Configuration supplies no scope/context/policy CID or Site identity.
pub fn admit_native_local_effect_reviewer_selection(
  wire : String,
) -> Result[NativeLocalEffectReviewerSelection, NativeLocalEffectReviewerIssue] {
  if @utf8.encode(wire).length() > 8192 {
    return Err(ReviewerSelectionLimitExceeded)
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 8192,
      max_nodes: 32,
      max_depth: 4,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidReviewerSelection)
  }
  try {
    let cursor = local_reviewer_decoded(
      @decode.admit(source, {
        max_nodes: 32,
        max_depth: 4,
        max_string_bytes: 4096,
        max_total_string_bytes: 6144,
      }),
    )
    let root = local_reviewer_decoded(
      @decode.closed_object(cursor, ["version", "native"]),
    )
    if local_reviewer_text(root, "version", 32) != "actql-config/0.1" {
      return Err(InvalidReviewerSelection)
    }
    let native = local_reviewer_decoded(
      @decode.closed_object(
        local_reviewer_decoded(@decode.required(root, "native")),
        ["effect_reviewer"],
      ),
    )
    let fields = local_reviewer_decoded(
      @decode.closed_object(
        local_reviewer_decoded(@decode.required(native, "effect_reviewer")),
        [
          "enabled", "principal", "connection", "key_id", "reviewer_id", "public_key_pem",
        ],
      ),
    )
    Ok({
      enabled: local_reviewer_decoded(
        @decode.boolean(
          local_reviewer_decoded(@decode.required(fields, "enabled")),
        ),
      ),
      principal: local_reviewer_text(fields, "principal", 512),
      connection: local_reviewer_text(fields, "connection", 512),
      key_id: local_reviewer_text(fields, "key_id", 128),
      reviewer_id: local_reviewer_text(fields, "reviewer_id", 128),
      public_key_pem: local_reviewer_text(fields, "public_key_pem", 4096),
    })
  } catch {
    LocalReviewerSelectionStop(issue) => Err(issue)
  }
}
