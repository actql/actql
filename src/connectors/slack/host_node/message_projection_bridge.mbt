///|
#export_name("slackCoalesceMessageOriginals")
pub fn slack_coalesce_message_originals(
  history : @catalog.SlackMessageHistory,
  replies : Array[@catalog.SlackMessageReplies],
  max_rows : Int,
  max_occurrences : Int,
  max_work : Int,
  max_comparison_nodes : Int,
  max_comparison_depth : Int,
  max_comparison_text_bytes : Int,
) -> Result[@catalog.SlackMessageProjection, @catalog.SlackMessagePageIssue] {
  @catalog.coalesce_slack_message_originals(history, replies, {
    max_rows,
    max_occurrences,
    max_work,
    comparison: {
      max_nodes: max_comparison_nodes,
      max_depth: max_comparison_depth,
      max_text_bytes: max_comparison_text_bytes,
    },
  })
}

///|
#export_name("slackMessageProjectionRowCount")
pub fn slack_message_projection_row_count(
  original : @catalog.SlackMessageProjection,
) -> Int {
  @catalog.slack_message_projection_row_count(original)
}

///|
#export_name("slackMessageProjectionRowsWire")
pub fn slack_message_projection_rows_wire(
  original : @catalog.SlackMessageProjection,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SlackMessagePageIssue] {
  @catalog.slack_message_projection_rows_wire(
    original, names, max_bytes, max_nodes, max_depth,
  )
}
