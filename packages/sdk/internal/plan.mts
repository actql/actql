// Read-only static compiler projection through the existing wire validator.
import type {Client} from '../index.d.ts';
import type {WireConnection} from '@actql/client-wire';

interface StaticProducer {
  readonly receipt: unknown;
  body?: unknown;
}
interface StaticPreparation {
  assertSourceSnapshotCurrent(receipt: unknown): void;
  captureSourceSnapshot(receipt: unknown, original: unknown,
    snapshot: (value: unknown, observe?: Parameters<typeof snapshotClientRequest>[1]) => unknown): unknown;
  bindSourceSnapshot(receipt: unknown, body: unknown): unknown;
}
import {contentCid} from '../checkpoints.mjs';
import {captureResponse, freezeInput} from './data.mjs';
import {fail} from './errors.mjs';
import {snapshotClientRequest, validClientBody, validWireEffectfulStaticPlanViewShape,
  validWirePlanViewShape} from '@actql/client-wire';

export function createPlan(connection: WireConnection,
  exchange: (operation: 'plan', body: Record<string, unknown>, signal?: AbortSignal,
    submitContext?: undefined, cancellationContext?: undefined, producer?: StaticProducer) => Promise<unknown>,
  responseValue: (response: unknown) => unknown | Promise<unknown>,
  withStaticPreparation: <T>(kind: 'aql' | 'program', input: unknown, options: unknown,
    read: (producer?: StaticProducer) => Promise<T>) => Promise<T>,
  sourcePreparation?: StaticPreparation): Pick<Client, 'plan'> {
  const selected = {wire: connection};
  return {
    plan: (input, originalOptions) => withStaticPreparation(
      typeof input === 'string' ? 'aql' : 'program', input, originalOptions, async producer => {
      const options = originalOptions === undefined ? {} : originalOptions;
      const kind = options.kind ?? (typeof input === 'string' ? 'aql' : 'program');
      const original = {kind,
        input: kind === 'aql' ? {text: input, format: options.format ?? 'aql-text',
          ...(options.parameterDeclarations === undefined ? {} :
            {parameterDeclarations: options.parameterDeclarations})} : input,
        parameters: options.parameters ?? null,
        maxWireBytes: options.maxWireBytes ?? 65536,
        maxNodes: options.maxNodes ?? 10000, maxDepth: options.maxDepth ?? 64};
      let captured: unknown;
      const snapshot = (value: unknown, observe?: Parameters<typeof snapshotClientRequest>[1]) => {
        if (value !== original || captured !== undefined) fail('InvalidHostSourceSnapshot');
        return captured = snapshotClientRequest(value, observe);
      };
      if (producer !== undefined) sourcePreparation!.assertSourceSnapshotCurrent(producer.receipt);
      const value = producer === undefined ? snapshot(original)
        : sourcePreparation!.captureSourceSnapshot(producer.receipt, original, snapshot);
      if (captured === undefined || value !== captured) fail('InvalidHostSourceSnapshot');
      if (producer !== undefined) sourcePreparation!.assertSourceSnapshotCurrent(producer.receipt);
      // This is the original unchecked JSON snapshot; the wire guard below
      // still admits the complete actual body before any exchange.
      const body = freezeInput(captured) as Record<string, unknown>;
      if (producer !== undefined) {
        sourcePreparation!.bindSourceSnapshot(producer.receipt, body);
        producer.body = body;
      }
      if (!validClientBody('plan', {connection: selected.wire, ...body})) {
        fail('InvalidClientPlanRequest');
      }
      const response = await exchange('plan', body, options.signal, undefined, undefined, producer);
      const view = captureResponse(await responseValue(response));
      const effectful = validWireEffectfulStaticPlanViewShape(view);
      if (!effectful && !validWirePlanViewShape(view)) fail('InvalidClientHostPlanView');
      const component = effectful ? view.computation.plan_view : view;
      const map = component.logical_map;
      const {self_cid: observed, ...preimage} = map;
      if (map.compiled_plan_cid !== component.compiled_plan_cid ||
          effectful && map.program_definition_cid !== view.program_definition_cid ||
          await contentCid(preimage) !== observed) fail('InvalidClientHostPlanView');
      return freezeInput(view);
    }),
  };
}
