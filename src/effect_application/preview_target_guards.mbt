///|
/// A connector observation for one exact Preview row. The Site remains
/// responsible for obtaining this value under current authority; constructing
/// this record does not turn an untrusted observation into evidence.
pub(all) struct EffectTargetVersionObservation {
  row_preview_cid : String
  version_cid : String
} derive(Eq, Debug)

///|
pub(all) enum EffectPreviewTargetGuardIssue {
  InvalidLimits
  CapacityExceeded
  InvalidObservation(Int)
  DuplicateObservation(Int)
  MissingObservation(Int, Int)
  StalePreview(Int, Int)
  ForeignObservation
} derive(Eq, Debug)

///|
/// Compare every admitted version/content guard before the first mutation.
/// The caller must supply current, authorized connector observations keyed by
/// row Preview CID. A missing value is stale, not a waiver. This check is one
/// apply-admission obligation, not a complete EffectApplyPermit: source,
/// capability, authority, policy, and whole-set footprint admission remain.
pub fn check_effect_preview_target_guards(
  preview : @publication.EffectPreviewIdentity,
  observations : Array[EffectTargetVersionObservation],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, EffectPreviewTargetGuardIssue] {
  if max_rows < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  if observations.length() > max_rows || observations.length() > max_work {
    return Err(CapacityExceeded)
  }
  let mut remaining = max_work - observations.length()
  let current : Map[String, String] = Map([])
  for index in 0..<observations.length() {
    let observed = observations[index]
    if !effect_cid_valid(observed.row_preview_cid) ||
      !effect_cid_valid(observed.version_cid) {
      return Err(InvalidObservation(index))
    }
    if current.contains(observed.row_preview_cid) {
      return Err(DuplicateObservation(index))
    }
    current[observed.row_preview_cid] = observed.version_cid
  }
  let mut total_rows = 0
  let mut guarded_rows = 0
  for member_index in 0..<@publication.effect_preview_member_count(preview) {
    let count = @publication.effect_preview_row_count(preview, member_index).unwrap()
    if count > max_rows - total_rows || count > remaining {
      return Err(CapacityExceeded)
    }
    total_rows += count
    remaining -= count
    for row_index in 0..<count {
      match
        @publication.effect_preview_row_guard_version_cid(
          preview, member_index, row_index,
        ) {
        Some(expected) => {
          guarded_rows += 1
          let row = @publication.effect_preview_row_identity(
            preview, member_index, row_index,
          ).unwrap()
          match current.get(row) {
            None => return Err(MissingObservation(member_index, row_index))
            Some(actual) =>
              if actual != expected {
                return Err(StalePreview(member_index, row_index))
              }
          }
        }
        None => ()
      }
    }
  }
  if observations.length() != guarded_rows {
    return Err(ForeignObservation)
  }
  Ok(())
}
