import type {WireControlledRunState} from './index.js';

const unknown: WireControlledRunState = {
  version: 'actql-controlled-run-state/0.1', run_id: 'original',
  status: 'running', updated_at: '2026-10-11T00:00:00.000Z',
  control_revision: 17,
};
const observed: WireControlledRunState = {
  ...unknown, pause_pending: false, expiry_pending: true, cleanup_pending: false,
};
const cleanup: boolean | undefined = unknown.cleanup_pending;
// @ts-expect-error An unknown pending observation is not a required boolean.
const known: boolean = unknown.cleanup_pending;
// @ts-expect-error NULL is not the wire representation of unknown observation.
const invalid: WireControlledRunState = {...unknown, cleanup_pending: null};
void [observed, cleanup, known, invalid];
