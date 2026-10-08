import type {Client} from '@actql/sdk';
import type {HostCapacityPolicy} from './host-policy.js';
import type {HostObservationConnection} from './observation.js';
export type {HostCapacityPolicy} from './host-policy.js';

/** Multiple independently published Sources: 2–128 profiles and at most
 * 128 total read bindings. Execution keeps its existing acquisition bounds. */
export type SourceProfilePaths = readonly [string, string, ...string[]];
/** Independently published Effect installations. The shared Environment bounds
 * their inventory; every complete Effect Set must select one installation. */
export type EffectProfilePaths = readonly [string, string, ...string[]];

export type HostInstallation = Readonly<{
  directory?: string;
  sourceProfilePath?: string;
  sourceProfilePaths?: SourceProfilePaths;
  effectProfilePath?: string;
  effectProfilePaths?: EffectProfilePaths;
  hostCapacityPolicy?: HostCapacityPolicy;
  resolveSourceSecret?: (...args: any[]) => any;
  resolveEffectSecret?: (...args: any[]) => any;
  authorization?: Readonly<Record<string, unknown>>;
  modelInstallation?: Readonly<Record<string, unknown>>;
  registerModelProviders?: (...args: any[]) => any;
  resultDataPolicy?: Readonly<Record<string, unknown>>;
  retainedRelationOutput?: boolean;
  observation?: HostObservationConnection;
}>;
export declare function connect(options: Readonly<{
  mode: 'local'; owner: 'local'; runtime?: 'embedded'; durability?: 'volatile' | 'durable';
  consentRefs?: readonly string[]; installation?: HostInstallation;
}>): Promise<Client>;
export declare function publishSource(options?: Pick<HostInstallation,
  'directory' | 'sourceProfilePath' | 'resolveSourceSecret'> & {signal?: AbortSignal}): Promise<unknown>;
export declare function publishEffect(options?: Pick<HostInstallation,
  'directory' | 'effectProfilePath' | 'resolveEffectSecret' | 'hostCapacityPolicy'> & {signal?: AbortSignal}): Promise<unknown>;
