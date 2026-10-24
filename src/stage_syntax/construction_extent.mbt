///|
/// Preconstruction structural facts from the already admitted indexed source.
/// This is a bound on the stage envelope only, not semantic checking or a grant.
/// The indexed tree, temporary ObjectViews/name arrays, strings and diagnostic
/// paths need separate simultaneous owners. The caller funds this inspection.
pub(all) struct ProgramConstructionExtent {
  stage_records : Int
  import_tuple_bound : Int64
  export_tuples : Int
  name_index_entries : Int64
  retained_array_capacity_bound : Int64
  retained_map_capacity_bound : Int64
  inspection_work : Int
} derive(Eq,Debug)

///|
priv struct ConstructionExtentWork { mut remaining : Int }

///|
/// Cursor lookup is deliberately not open_object: no additional name Map is
/// built merely to determine the constructor's own Map envelope.
fn construction_field(cursor : @wire.Cursor,name : String,work : ConstructionExtentWork) -> @wire.Cursor? {
  guard @wire.object_length(cursor) is Some(count) else {return None}
  if count>work.remaining {work.remaining = -1;return None}
  work.remaining-=count
  for index in 0..<count {
    guard @wire.field_at(cursor,index) is Some((key,value)) else {return None}
    if key==name {return Some(value)}
  }
  None
}

///|
pub fn program_construction_extent(root : @wire.Cursor,max_work : Int) -> ProgramConstructionExtent? {
  if max_work<1 {return None}
  let work : ConstructionExtentWork={remaining:max_work-1}
  guard construction_field(root,"stages",work) is Some(stages) else {return None}
  guard construction_field(root,"results",work) is Some(exports) else {return None}
  guard @wire.array_length(stages) is Some(stage_count) else {return None}
  guard @wire.object_length(exports) is Some(export_count) else {return None}
  if stage_count>work.remaining {return None}
  work.remaining-=stage_count
  let mut imports=0L
  let mut names=0L
  for index in 0..<stage_count {
    guard @wire.element_at(stages,index) is Some(stage) else {return None}
    guard construction_field(stage,"inputs",work) is Some(inputs) else {return None}
    guard @wire.object_length(inputs) is Some(input_count) else {return None}
    // An admitted input declaration can contain at most result and receipt
    // imports. Malformed declarations remain the actual decoder's concern.
    if input_count>work.remaining {return None}
    work.remaining-=input_count
    imports+=2L*input_count.to_int64()
    guard construction_field(stage,"results",work) is Some(results) else {return None}
    guard @wire.object_length(results) is Some(result_count) else {return None}
    if result_count>work.remaining {return None}
    work.remaining-=result_count
    names+=result_count.to_int64()
    for name in ["effects","table_inputs"] {
      match construction_field(stage,name,work) {
        Some(value)=>{
          guard @wire.object_length(value) is Some(count) else {return None}
          if count>work.remaining {return None}
          work.remaining-=count
          names+=count.to_int64()
        }
        None=>if work.remaining<0 {return None}
      }
    }
  }
  // Pinned grow-only arrays start at <=8 and double: capacity<=8+2n.
  // Four retained arrays per stage, plus Program stages/exports. Maps grow
  // below full occupancy: conservative capacity<=8+4n, with three per stage.
  let arrays=2L+4L*stage_count.to_int64()
  let array_items=stage_count.to_int64()+export_count.to_int64()+imports+names
  Some({stage_records:stage_count,import_tuple_bound:imports,export_tuples:export_count,name_index_entries:names,retained_array_capacity_bound:8L*arrays+2L*array_items,retained_map_capacity_bound:24L*stage_count.to_int64()+4L*names,inspection_work:max_work-work.remaining})
}
