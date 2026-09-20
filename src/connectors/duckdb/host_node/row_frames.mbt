///|
#export_name("retainedFramesPrepare")
pub fn retained_frames_prepare(
  max_bytes : Int,
  max_rows : Int,
  max_row_bytes : Int,
  max_depth : Int,
  max_frame_bytes : Int,
) -> @publication.DurableResultRowFrames raise NodeHostFailure {
  match
    @publication.prepare_durable_result_row_frames(
      max_bytes, max_rows, max_row_bytes, max_depth, max_frame_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Frame(issue)
  }
}

///|
#export_name("retainedFramesFeed")
pub fn retained_frames_feed(
  frames : @publication.DurableResultRowFrames,
  chunk : Bytes,
) -> Array[String] raise NodeHostFailure {
  match @publication.feed_durable_result_row_frames(frames, chunk) {
    Ok(value) => value
    Err(issue) => raise Frame(issue)
  }
}

///|
#export_name("retainedFramesFinish")
pub fn retained_frames_finish(
  frames : @publication.DurableResultRowFrames,
) -> Array[Int] raise NodeHostFailure {
  match @publication.finish_durable_result_row_frames(frames) {
    Ok(value) => [value.bytes, value.rows]
    Err(issue) => raise Frame(issue)
  }
}

///|
#export_name("retainedFramesCancel")
pub fn retained_frames_cancel(
  frames : @publication.DurableResultRowFrames,
) -> Unit {
  @publication.cancel_durable_result_row_frames(frames)
}
