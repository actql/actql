// Kintone DATA protocol on the same generic reader's bound response borrow.
// No credential, physical transport, RowRun, charge or cleanup ACK is created here.
import {types} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {KINTONE_FORM_READ_OPERATION, KINTONE_RECORD_READ_OPERATION} from './kintone-record-read.mjs';
import type {KintoneResponse} from './kintone-record-read.mjs';

type Operation = typeof KINTONE_FORM_READ_OPERATION | typeof KINTONE_RECORD_READ_OPERATION;
type Kind = 'form' | 'page';
type NativeMethod = (...args: unknown[]) => unknown;
export type KintoneManagedInput = Readonly<{resource: string; columns: readonly string[];
  responseBorrow?: unknown; originalAuthorization?: Readonly<{scope: unknown}>}>;
type SuppliedAuthorization = Readonly<{originalAuthorization: unknown; authorization: unknown; verifyCurrent(): unknown}>;
type Options = Readonly<{moon: unknown; original: unknown;
  bounds: Readonly<{page: unknown; form: unknown; values: unknown}>;
  limits: Readonly<Record<'maxPages' | 'perPage' | 'maxRequestBytes' | 'maxContractPairs', number>>;
  guestSpaceId?: string; baseCapacity: unknown;
  authorizeForm(input: KintoneManagedInput, signal: AbortSignal): SuppliedAuthorization | PromiseLike<SuppliedAuthorization>;
  capacityForResponse(read: unknown, kind: Kind, bytes: number, previous: unknown): unknown}>;
type Request = Readonly<{method: string; path: string; body: string;
  headers: readonly (readonly string[])[]; responseHeaders: readonly string[]}>;
type Response = Pick<KintoneResponse, 'statusCode' | 'body'>;
type ReadChild<Value> = Readonly<{operation: Operation; prepare():
  Readonly<{original: object; request: Request; project(response: Response): Value}> &
  Partial<SuppliedAuthorization>}>;
type Context = Readonly<{signal: AbortSignal; readChild<Value>(options: ReadChild<Value>): Promise<Value>;
  consumeObservation(): Promise<void>; consumeValues(columns: readonly string[], rows: readonly (readonly unknown[])[]): Promise<void>}>;
type Sequence = Readonly<{responseCapacity(bytes: number): unknown; read(context: Context): Promise<void>; retire(): boolean}>;

const fail: (code: string) => never=code=>{throw Object.assign(new Error(code),{code});};
function method(value: unknown,name: string): NativeMethod {
  if(value===null||typeof value!=='object'||types.isProxy(value))fail('InvalidKintoneManagedSequence');
  const field=Object.getOwnPropertyDescriptor(value,name);
  if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function')fail('KintoneManagedMethodUnavailable');
  return field.value as NativeMethod;
}

// The installing Source supplies exact native typed limits and complete quote
// callbacks. This constructor is not selected by any profile spelling.
export function createKintoneManagedSequence({moon,original,bounds,limits,guestSpaceId,
  authorizeForm,capacityForResponse,baseCapacity}: Options) {
  if(typeof authorizeForm!=='function'||typeof capacityForResponse!=='function'||baseCapacity==null||
      !Number.isSafeInteger(limits?.maxPages)||limits.maxPages<1||
      !Number.isSafeInteger(limits?.perPage)||limits.perPage<1||
      !Number.isSafeInteger(limits?.maxRequestBytes)||limits.maxRequestBytes<1||
      !Number.isSafeInteger(limits?.maxContractPairs)||limits.maxContractPairs<1||
      guestSpaceId!==undefined&&!/^[1-9][0-9]*$/u.test(guestSpaceId))fail('InvalidKintoneManagedSequence');
  const names=['clientProgramKintoneAdoptManagedBorrow','clientProgramKintoneManagedColumns',
    'clientProgramKintoneManagedFormRequest','clientProgramKintoneManagedPageRequest',
    'clientProgramKintoneManagedRecheckForm','clientProgramKintoneManagedProjectPage',
    'clientProgramKintoneManagedComplete','clientProgramKintoneManagedRetire'] as const;
  const methods=Object.freeze(Object.fromEntries(names.map(name=>[name,method(moon,name)])));
  const call=(name: (typeof names)[number],args: unknown[])=>Reflect.apply(methods[name],moon,args);
  const prefix=guestSpaceId===undefined?'/k/v1/':`/k/guest/${guestSpaceId}/v1/`;
  const maxPages=limits.maxPages,perPage=limits.perPage,maxRequestBytes=limits.maxRequestBytes,
    maxContractPairs=limits.maxContractPairs;
  const page=bounds.page,values=bounds.values,form=bounds.form;
  return function prepare(input: KintoneManagedInput){
    if(input?.responseBorrow===undefined||input.originalAuthorization===undefined)fail('KintoneManagedBorrowUnavailable');
    let read=checked(call(names[0],[original,input.responseBorrow,page,values,maxContractPairs,perPage]));
    let columns=call(names[1],[read]),capacity: unknown=baseCapacity,kind: Kind | undefined,retired=false,started=false;
    let sequence: Sequence;
    const current=()=>{if(retired)fail('KintoneManagedSequenceClosed');};
    const request=(body: string,path: string)=>Object.freeze({method:'POST',path:prefix+path,body,
      headers:Object.freeze([Object.freeze(['x-http-method-override','GET'])]),responseHeaders:Object.freeze([])});
    sequence=Object.freeze({
      responseCapacity(bytes: number){
        if(this!==sequence)fail('ForeignKintoneManagedSequence');current();
        if(kind!=='form'&&kind!=='page')fail('KintoneManagedResponseUnavailable');
        // The generic owner has retained and charged the original body before
        // this typed same-base/cumulative quote is asked for. No body is decoded here.
        capacity=Reflect.apply(capacityForResponse,undefined,[read,kind,bytes,capacity]);
        if(capacity==null)fail('KintoneManagedCapacityUnavailable');
        return capacity;
      },
      async read(context: Context){
        if(this!==sequence||started)fail('ForeignKintoneManagedSequence');current();started=true;
        const observeForm=async()=>{
          context.signal.throwIfAborted();current();
          const supplied=await Reflect.apply(authorizeForm,undefined,[input,context.signal]);
          current();context.signal.throwIfAborted();kind='form';
          await context.readChild({operation:KINTONE_FORM_READ_OPERATION,prepare(){
            current();return Object.freeze({original:Object.freeze({}),
              originalAuthorization:supplied.originalAuthorization,authorization:supplied.authorization,
              verifyCurrent:supplied.verifyCurrent,
              request:request(checked(call(names[2],[read,maxRequestBytes])) as string,'app/form/fields.json'),
              project(response: Response){current();if(response.statusCode!==200)fail('KintoneReadHttpRejected');
                checked(call(names[4],[read,response.body,form]));},
            });
          }});
          await context.consumeObservation();current();
        };
        await observeForm();
        for(let index=0;index<maxPages;index++){
          current();context.signal.throwIfAborted();kind='page';
          const rows=await context.readChild({operation:KINTONE_RECORD_READ_OPERATION,prepare(){
            return Object.freeze({original:Object.freeze({}),
              request:request(checked(call(names[3],[read,maxRequestBytes])) as string,'records.json'),
              project(response: Response){current();if(response.statusCode!==200)fail('KintoneReadHttpRejected');
                return checked(call(names[5],[read,response.body])) as readonly (readonly unknown[])[];},
            });
          }});
          await context.consumeValues(columns as readonly string[],rows);current();
          await observeForm();
          if(call(names[6],[read])===true)return;
        }
        fail('KintoneReadPageLimit');
      },
      retire(){
        if(this!==sequence)fail('ForeignKintoneManagedSequence');
        if(retired)return true;
        call(names[7],[read]);retired=true;read=columns=capacity=kind=undefined;
        return true;
      },
    });
    return sequence;
  };
}
