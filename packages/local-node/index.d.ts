import type {Client} from '@actql/sdk';
import type {HostCapacityPolicy} from './host-policy.js';
export type {HostCapacityPolicy} from './host-policy.js';

export type HostInstallation = Readonly<{
  directory?: string;
  sourceProfilePath?: string;
  sourceProfilePaths?: readonly [string, string];
  effectProfilePath?: string;
  hostCapacityPolicy?: HostCapacityPolicy;
  resolveSourceSecret?: (...args: any[]) => any;
  resolveEffectSecret?: (...args: any[]) => any;
  authorization?: Readonly<Record<string, unknown>>;
  modelInstallation?: Readonly<Record<string, unknown>>;
  registerModelProviders?: (...args: any[]) => any;
  resultDataPolicy?: Readonly<Record<string, unknown>>;
  retainedRelationOutput?: boolean;
}>;
export declare function connect(options: Readonly<{
  mode: 'local'; owner: 'local'; runtime?: 'embedded'; durability?: 'volatile' | 'durable';
  consentRefs?: readonly string[]; installation?: HostInstallation;
}>): Promise<Client>;
export declare function publishSource(options?: Pick<HostInstallation,
  'directory' | 'sourceProfilePath' | 'resolveSourceSecret'> & {signal?: AbortSignal}): Promise<unknown>;
export declare function publishEffect(options?: Pick<HostInstallation,
  'directory' | 'effectProfilePath' | 'resolveEffectSecret' | 'hostCapacityPolicy'> & {signal?: AbortSignal}): Promise<unknown>;
