///|
test "Native driver roots follow real cleanup retry and common reservation retirement" {
  for variant in ["current_filter", "current_edge_filter"] {
    println("ACTQL_DRIVER_CASE:" + variant)
    run_current_host_graph_relation_path(
      variant~,
      execution_quantum=1,
      cleanup_attempts=Some(Ref(0)),
    )
    println("ACTQL_DRIVER_CASE_DONE:" + variant)
  }
}
