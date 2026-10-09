///|
/// Pure common placement planning. Trusted Host owners provide current Site,
/// capacity and Transfer facts; this projection grants no execution or I/O.
#export_name("coordinatorPlanSiteCandidate")
pub fn coordinator_plan_site_candidate(
  duration : Int64?,
  startup : Int64?,
  capacity_supported : Bool,
  accepts_transfer : Bool,
  transfer_provider_available : Bool,
  transfer_duration : Int64?,
  transfer_required : Array[Bool],
  shared_transfer : Array[Bool],
  source_revoked : Array[Bool],
  estimate_available : Array[Bool],
  transfer_bytes : Array[Int64],
  retained_bytes : Array[Int64],
  execution_bytes : Array[Int64],
) -> (Int, Int64) {
  @site.site_candidate_plan_projection(
    @site.plan_site_candidate(
      duration, startup, capacity_supported, accepts_transfer, transfer_provider_available,
      transfer_duration, transfer_required, shared_transfer, source_revoked, estimate_available,
      transfer_bytes, retained_bytes, execution_bytes,
    ),
  )
}

///|
#export_name("coordinatorSelectSiteCandidate")
pub fn coordinator_select_site_candidate(
  durations : Array[Int64],
  keys : Array[String],
) -> Int {
  @site.select_site_candidate_index(durations, keys)
}
