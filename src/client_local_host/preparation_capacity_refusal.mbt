///|
priv enum PreparationRefusalPhase { TextEligibility; SnapshotAndIntent; SourceParsing; ProgramConstruction; CheckLowerAndPlan } derive(Eq,Debug)

///|
/// Immutable explanation DATA. It conveys no owner, reservation or authority.
pub(all) struct ClientPreparationCapacityRefusal {
  phase : String
  dimension : String
  required_retention : Int64
  required_execution : Int64
  available_retention : Int64
  available_execution : Int64
} derive(Eq,Debug)

///|
fn[I,P] reserve_closed_values_phase(
  capacity : @resources.PreparationCapacity[I,P],input : I,phase : PreparationRefusalPhase,
  retained : Int64,execution : Int64,
) -> Result[Unit,ClientClosedValuesPreparationIssue] {
  match @resources.reserve_working_preparation_phase(capacity,input,retained,execution) {
    Ok(_) => Ok(())
    Err(issue) => {
      let dimension=match issue {
        Resource(RetentionLimit)=>"retention"
        Resource(ExecutionLimit)=>"execution"
        _=>return Err(Capacity(issue))
      }
      let (available_retention,available_execution)=match @resources.preparation_capacity_available(capacity,input) {
        Ok(value)=>value
        Err(_)=>return Err(Capacity(issue))
      }
      let phase=match phase {
        TextEligibility=>"text_eligibility"
        SnapshotAndIntent=>"snapshot_and_intent"
        SourceParsing=>"source_parsing"
        ProgramConstruction=>"program_construction"
        CheckLowerAndPlan=>"check_lower_and_plan"
      }
      Err(CapacityExceeded({phase,dimension,required_retention:retained,required_execution:execution,available_retention,available_execution}))
    }
  }
}

///|
/// Fixed bridge projection; the returned tuple contains scalar diagnostic data
/// only. A supplied/copied explanation cannot select or mutate a resource owner.
pub fn closed_values_preparation_capacity_refusal(
  issue : ClientClosedValuesPreparationIssue,
) -> (String,String,Int64,Int64,Int64,Int64)? {
  match issue {
    CapacityExceeded(value)=>Some((value.phase,value.dimension,value.required_retention,value.required_execution,value.available_retention,value.available_execution))
    _=>None
  }
}
