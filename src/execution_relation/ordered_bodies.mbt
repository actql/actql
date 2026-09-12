///|
/// Three closure members for one owned ordered node, not a complete
/// row_kernel_evidence object: its binding record still needs node identity.
/// Caller writer limits span all bodies; temporary sort entries are bounded.
fn emit_ordered_context_bodies(
  links : OrderedLinks,
  max_entries : Int,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  if max_entries < 0 || links.slots.length() > max_entries {
    raise @encode.OutputLimit
  }
  let indices = Array::makei(links.slots.length(), i => i)
  indices.sort_by((a, b) => {
    @canonical.compare_utf16(
      links.slots[a].context_cid,
      links.slots[b].context_cid,
    )
  })
  // Every prefix has a distinct length. A duplicate CID cannot name two of
  // these bodies: do not silently discard evidence on an identity collision.
  for i = 1; i < indices.length(); i = i + 1 {
    if links.slots[indices[i - 1]].context_cid ==
      links.slots[indices[i]].context_cid {
      raise @encode.InvalidStructure
    }
  }
  @encode.begin_array(out)
  for index in indices {
    emit_ordered_context(
      links.shapes,
      index,
      out,
      self_cid=Some(links.slots[index].context_cid),
    )
  }
  @encode.end_array(out)
}

///|
fn emit_ordered_shape_bodies(
  links : OrderedLinks,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let shapes = links.shapes
  @encode.begin_array(out)
  if @canonical.compare_utf16(shapes.input_cid, shapes.output_cid) <= 0 {
    emit_closed_row_shape(shapes.input, out, self_cid=Some(shapes.input_cid))
    if shapes.input_cid != shapes.output_cid {
      emit_closed_row_shape(
        shapes.output,
        out,
        self_cid=Some(shapes.output_cid),
      )
    }
  } else {
    emit_closed_row_shape(shapes.output, out, self_cid=Some(shapes.output_cid))
    emit_closed_row_shape(shapes.input, out, self_cid=Some(shapes.input_cid))
  }
  @encode.end_array(out)
}

///|
fn emit_ordered_limit_bodies(
  links : OrderedLinks,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(out)
  emit_ordered_limits_body(links.limits.limits, Some(links.limits.cid), out)
  @encode.end_array(out)
}
