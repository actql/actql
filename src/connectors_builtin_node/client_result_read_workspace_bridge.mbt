///|
#export_name("clientProgramReserveRequestResultRead")
pub fn client_program_reserve_request_result_read(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  max_row : Int,
  frame : Int,
  schema_units : Int,
  max_nodes : Int,
  desired_window : Int,
) -> Result[Int, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_result_read(
    parent, input, max_row, frame, schema_units, max_nodes, desired_window,
  )
}

///|
#export_name("clientProgramGrowRequestResultReadRow")
pub fn client_program_grow_request_result_read_row(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  units : Int,
) -> Result[(Int, Int), @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.grow_request_result_read_row(parent, input, units)
}
