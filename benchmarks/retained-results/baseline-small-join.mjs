// Capacity-only assembly for the registered narrow/100 join fixture.
import {createHash} from 'node:crypto';
import {baselineHostLimitsSha256} from './baseline-acquisition-capacity.mjs';

export function adaptBaselineSmallJoin(host, generation) {
  const hash = text => createHash('sha256').update(text).digest('hex');
  if (hash(host) !== baselineHostLimitsSha256 || hash(generation) !==
      '326711dc0f3c014e19538acdce34c7ca560e9bb6de40e31f322067187609b7ba') {
    throw Error('UnrecognizedBaselineSmallJoinSource');
  }
  // Validation and selected output each have 100 rows. Their shared receiving
  // allowance and receipts must cover both, plus metadata transport.
  host = host.replace('max_received_rows: 100,', 'max_received_rows: 204,');
  const dispatch = host.indexOf('fn dispatch_limits(');
  if (dispatch < 0) throw Error('MissingBaselineDispatchLimits');
  host = host.slice(0, dispatch).replaceAll('max_rows: 100,', 'max_rows: 204,') +
    host.slice(dispatch).replaceAll('max_rows: 100,', 'max_rows: 200,');
  const generate = generation.indexOf('fn generate(');
  if (generate < 0) throw Error('MissingBaselineGeneration');
  generation = generation.slice(0, generate) + generation.slice(generate)
    .replaceAll('max_rows: 100,', 'max_rows: 200,')
    .replace('prepare_fragment_request(pipeline, 100L, 1000L)', 'prepare_fragment_request(pipeline, 200L, 1000L)')
    .replace('max_input_rows: 100L,', 'max_input_rows: 200L,');
  return Object.freeze({host, generation,
    scope: 'narrow-100-join-capacity-only',
    compute: Object.freeze({rows: 600, cells: 1000, inputRows: 200})});
}
