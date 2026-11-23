// The installed Source supplies IO, currentness, charging and retirement. The
// existing Catalog owns page meaning and original channel/history/reply links.
import {checked} from '../../../host-common/runtime-result.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';
import {SLACK_USER_LIST_OPERATION,SLACK_WORKSPACE_IDENTITY_OPERATION} from './user-list-read.mjs';
import {SLACK_CHANNEL_LIST_OPERATION} from './channel-list-read.mjs';
// @ts-expect-error TS7016 until the existing message history Owner moves to TypeScript.
import {SLACK_MESSAGE_HISTORY_OPERATION,SLACK_MESSAGE_REPLIES_OPERATION} from './message-history-read.mjs';
import type {ListPageProjection, SlackListLimits, SlackListPageMetadata, SlackListResponse,
  WorkspaceIdentityProvider} from './user-list-read.mjs';

type Resource = 'users' | 'channels' | 'messages';
type Projection<Args extends readonly unknown[], Value> = (...args: Args) => Value;
type Project = <Args extends readonly unknown[], Value>(method: Projection<Args, Value>,
  receiver: unknown, args: Args) => Value;
type Limits = SlackListLimits;
type SourceOptions = Readonly<{moon: unknown; workspaceId: string; resource: Resource;
  names: readonly string[] | undefined; limits: Limits}>;
type Response = Pick<SlackListResponse, 'body' | 'accepted' | 'statusCode'>;
type RequestQuery = readonly (readonly [string, string])[];
type DescribedRequest = Readonly<{method: 'GET' | 'POST'; path: string; query: readonly (readonly string[])[];
  body?: string; headers: readonly (readonly string[])[]; responseHeaders: readonly string[]}>;
type ChildRead<Value> = Readonly<{operation: string; prepare(): Readonly<{original: unknown;
  request: DescribedRequest; project(response: Response): Value}>}>;
type ReadContext = Readonly<{project: Project; readChild<Value>(read: ChildRead<Value>): Promise<Value>;
  consumeObservation(): Promise<void>; consumePage(rows: readonly unknown[]): Promise<void>}>;
type RowsWire = (page: unknown, names: readonly string[], bytes: number, nodes: number, depth: number) => unknown;
type HistorySelection = (page: unknown, index: number, bytes: number, nodes: number, depth: number,
  rows: number, cursorBytes: number, valueNodes: number, valueTextBytes: number, pages: number) => unknown;
type PageAdmission = (control: unknown, original: unknown, body: Response['body']) => unknown;
type NativeRequestFields = Readonly<{channel: string; ordinal: number; cursor: string | null;
  latest: string | null; oldest?: string | null}>;
type RepliesRequestFields = NativeRequestFields & Readonly<{ts: string; oldest: string | null}>;
type ChannelPage = Readonly<{original: unknown; ids: readonly string[]}>;
type SourceProvider = WorkspaceIdentityProvider & {
  slackProjectUserList: ListPageProjection;
  slackUserListIds(page: unknown): readonly string[];
  slackUserListRowsWire: RowsWire;
  slackUserListMetadataJson(page: unknown): string;
  slackUserListColumnNames(): string[];
  slackProjectChannelList: ListPageProjection;
  slackProjectHistoryConversationList: ListPageProjection;
  slackChannelListIds(page: unknown): readonly string[];
  slackChannelListRowsWire: RowsWire;
  slackChannelListMetadataJson(page: unknown): string;
  slackChannelListColumnNames(): string[];
  slackPrepareMessageHistoryFromChannel: HistorySelection;
  slackMessageHistoryMatchesChannel(history: unknown, page: unknown, index: number): boolean;
  slackAdmitMessageHistoryPage: PageAdmission;
  slackMessageHistoryRequestMatches(history: unknown, request: unknown): boolean;
  slackMessagePageRowCount(page: unknown): number;
  slackMessageColumnNames(): string[];
  slackBeginMessageHistory(history: unknown): unknown;
  slackMessageHistoryRequestJson(request: unknown): string;
  slackMessageHistoryPageHasNext(page: unknown): boolean;
  slackNextMessageHistoryRequest(history: unknown, page: unknown): unknown;
  slackFinishMessageHistory(history: unknown, page: unknown): unknown;
  slackCloseMessageHistory(history: unknown): unknown;
  slackPrepareMessageReplies(page: unknown, index: number, bytes: number, nodes: number, depth: number,
    rows: number, cursorBytes: number, valueNodes: number, valueTextBytes: number, comparisonNodes: number,
    comparisonDepth: number, comparisonTextBytes: number, pages: number, totalRows: number,
    totalBytes: number, maxWork: number): unknown;
  slackMessageRepliesMatchesOriginal(replies: unknown, page: unknown, index: number): boolean;
  slackBeginMessageReplies(replies: unknown): unknown;
  slackMessageRepliesRequestMatches(replies: unknown, request: unknown): boolean;
  slackMessageRepliesRequestJson(request: unknown): string;
  slackAdmitMessageRepliesPage: PageAdmission;
  slackMessageRepliesPageHasNext(page: unknown): boolean;
  slackNextMessageRepliesRequest(replies: unknown, page: unknown): unknown;
  slackFinishMessageReplies(replies: unknown, page: unknown): unknown;
  slackMessageRepliesPageRowCount(page: unknown): number;
  slackCloseMessageReplies(replies: unknown): unknown;
  slackCoalesceMessageOriginals(history: unknown, replies: readonly unknown[], historyRows: number,
    replyRows: number, comparisonNodes: number, outputNodes: number, depth: number, textBytes: number): unknown;
  slackMessageProjectionRowCount(projection: unknown): number;
  slackMessageProjectionRowsWire: RowsWire;
};

const fail: (code: string) => never = code=>{throw Object.assign(new Error(code),{code});};
const providerNames=['slackProjectUserList','slackUserListIds','slackUserListRowsWire',
  'slackUserListMetadataJson','slackUserListColumnNames','slackProjectChannelList',
  'slackProjectHistoryConversationList','slackChannelListIds','slackChannelListRowsWire',
  'slackChannelListMetadataJson','slackChannelListColumnNames','slackProjectWorkspaceIdentity',
  'slackWorkspaceIdentityMatches','slackPrepareMessageHistoryFromChannel','slackMessageHistoryMatchesChannel',
  'slackAdmitMessageHistoryPage','slackMessageHistoryRequestMatches','slackMessagePageRowCount',
  'slackMessageColumnNames','slackBeginMessageHistory','slackMessageHistoryRequestJson',
  'slackMessageHistoryPageHasNext','slackNextMessageHistoryRequest','slackFinishMessageHistory',
  'slackCloseMessageHistory','slackPrepareMessageReplies','slackMessageRepliesMatchesOriginal',
  'slackBeginMessageReplies','slackMessageRepliesRequestMatches','slackMessageRepliesRequestJson',
  'slackAdmitMessageRepliesPage','slackMessageRepliesPageHasNext','slackNextMessageRepliesRequest',
  'slackFinishMessageReplies','slackMessageRepliesPageRowCount','slackCloseMessageReplies',
  'slackCoalesceMessageOriginals','slackMessageProjectionRowCount','slackMessageProjectionRowsWire'] as const;

export function prepareSlackSourceReadSequence({moon,workspaceId,resource,names,limits}: SourceOptions, applySynchronousProjection: Project){
  if(typeof applySynchronousProjection!=='function'||!['users','channels','messages'].includes(resource)||
      !Array.isArray(names))fail('InvalidInstalledSlackRead');
  let provider: SourceProvider | undefined = Object.freeze(Object.fromEntries(providerNames.map(name=>{
    const field=Object.getOwnPropertyDescriptor(moon??{},name);
    if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function')fail('InvalidInstalledSlackProvider');
    return[name,(...args: unknown[])=>applySynchronousProjection(field.value,moon,args)];
  }))) as SourceProvider;
  const bound=Object.freeze({...limits});
  let started=false,pending=false,retired=false,chargePending=false,requestCount=0,observedRows=0,outputRows=0;
  let histories: unknown[] | undefined = [], replies: unknown[] | undefined = [],
    channelPages: ChannelPage[] | undefined = [], projections: unknown[] | undefined = [];
  const accountRows=(count: number)=>{
    if(!Number.isSafeInteger(count)||count<0||count>bound.maxTotalRows-observedRows)fail('InstalledSlackMessagesOccurrenceLimit');
    observedRows+=count;
  };
  const request=async <Value,>(context: ReadContext, operation: string, method: 'GET' | 'POST',
    path: string, query: RequestQuery, project: (body: Response['body']) => Value,
    body?: string, originalRequest?: unknown)=>{
    // Consume the actual earlier response before allocating the next original
    // request. The last response remains available for the coalesced row page.
    if(chargePending){await context.consumeObservation();chargePending=false;}
    if(resource==='messages'&&requestCount>=bound.maxPages)fail('InstalledSlackMessagesRequestLimit');
    requestCount++;
    const value=await context.readChild({operation,prepare(){
      if(Buffer.byteLength(requestTarget(path,query))>bound.maxTargetBytes)fail('SlackSourceTargetLimit');
      const request=Object.freeze({method,path,query:Object.freeze(query.map(pair=>Object.freeze(pair.slice()))),
        ...(body===undefined?{}:{body}),headers:Object.freeze([Object.freeze(['accept','application/json'])]),
        responseHeaders:Object.freeze([])});
      // The same fixed physical request is its original occurrence for the
      // list/identity grammar. Dependent reads retain the Catalog-issued
      // original instead; neither descriptor is an operation grant.
      return{original:originalRequest??request,request,project(response){
        if(!response.accepted||response.statusCode!==200)fail('SlackSourceReadRejected');
        return project(response.body);
      }};
    }});
    chargePending=true;return value;
  };
  const identity=async (context: ReadContext)=>{
    await request(context,SLACK_WORKSPACE_IDENTITY_OPERATION,'POST','/api/auth.test',[],body=>{
      const original=checked(provider!.slackProjectWorkspaceIdentity(body,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,bound.maxIdentityBytes));
      if(!provider!.slackWorkspaceIdentityMatches(original,workspaceId))fail('ForeignSlackWorkspace');
    },'{}');
    await context.consumeObservation();chargePending=false;
  };
  const append=async(context: ReadContext, rows: readonly unknown[])=>{
    if(rows.length>bound.maxTotalRows-outputRows)fail('InstalledSlackMessagesRowLimit');
    await context.consumePage(rows);chargePending=false;outputRows+=rows.length;
  };
  const list=async(context: ReadContext, kind: Resource)=>{
    const users=kind==='users',messages=kind==='messages';
    const ids=new Set<string>(),cursors=new Set<string>();let cursor: string | undefined,total=0;
    await identity(context);
    for(let index=0;index<bound.maxPages;index++){
      const remaining=bound.maxTotalRows-total;
      if(remaining<=0)fail(users?'SlackUserListRowLimit':'SlackChannelListRowLimit');
      const query: [string, string][] = users?[]:[['types',messages?'public_channel,private_channel,mpim,im':'public_channel,private_channel'],
        ['exclude_archived','false']];
      query.push(['limit',String(Math.min(bound.pageSize,remaining))]);
      if(cursor!==undefined)query.push(['cursor',cursor]);
      const page=await request(context,users?SLACK_USER_LIST_OPERATION:SLACK_CHANNEL_LIST_OPERATION,
        'GET',users?'/api/users.list':'/api/conversations.list',query,body=>{
          const original=checked((users?provider!.slackProjectUserList:messages
            ?provider!.slackProjectHistoryConversationList:provider!.slackProjectChannelList)(body,
            bound.maxResponseBytes,bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize),
            bound.maxCursorBytes,bound.maxValueNodes,bound.maxValueTextBytes));
          const metadata=JSON.parse((users?provider!.slackUserListMetadataJson:provider!.slackChannelListMetadataJson)(original)) as SlackListPageMetadata;
          if(metadata.rowCount>bound.maxTotalRows-total)fail(users?'SlackUserListRowLimit':'SlackChannelListRowLimit');
          const originalIds=(users?provider!.slackUserListIds:provider!.slackChannelListIds)(original);
          for(const id of originalIds){
            if(ids.has(id))fail(users?'SlackUserListDuplicateUser':'SlackChannelListDuplicateChannel');
            ids.add(id);
          }
          if(metadata.nextCursor!==null){
            if(cursors.has(metadata.nextCursor))fail(users?'SlackUserListRepeatedCursor':'SlackChannelListRepeatedCursor');
            cursors.add(metadata.nextCursor);
            if(index+1===bound.maxPages)fail(users?'SlackUserListPageLimit':'SlackChannelListPageLimit');
          }
          if(messages){accountRows(metadata.rowCount);channelPages!.push({original,ids:originalIds});return{metadata};}
          const rows=JSON.parse(checked((users?provider!.slackUserListRowsWire:provider!.slackChannelListRowsWire)(
            original,names!,bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)) as string) as readonly unknown[];
          return{metadata,rows};
        });
      total+=page.metadata.rowCount;
      if(!messages)await append(context,page.rows!);
      if(page.metadata.nextCursor===null)return;
      cursor=page.metadata.nextCursor;
    }
    fail('SlackSourcePageLimit');
  };
  const readReplies=async(context: ReadContext, page: unknown, index: number, channel: string)=>{
    let control=context.project(()=>{
      const selected=checked(provider!.slackPrepareMessageReplies(page,index,bound.maxResponseBytes,
        bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize),bound.maxCursorBytes,
        bound.maxValueNodes,bound.maxValueTextBytes,bound.maxNodes,bound.maxDepth,
        bound.maxValueTextBytes,bound.maxPages,bound.maxTotalRows,bound.maxTotalResponseBytes,bound.maxNodes));
      replies!.push(selected);
      if(!provider!.slackMessageRepliesMatchesOriginal(selected,page,index))fail('ForeignSlackMessageRepliesSelection');
      return selected;
    },undefined,[]);
    let original=context.project(()=>checked(provider!.slackBeginMessageReplies(control)),undefined,[]),target: string | undefined;
    for(let ordinal=0;ordinal<bound.maxPages;ordinal++){
      const fields=context.project(()=>{
        if(!provider!.slackMessageRepliesRequestMatches(control,original))fail('ForeignSlackMessageRepliesRequest');
        return JSON.parse(provider!.slackMessageRepliesRequestJson(original)) as RepliesRequestFields;
      },undefined,[]);
      if(target===undefined)target=fields.ts;
      if(fields.channel!==channel||fields.ts!==target||fields.ordinal!==ordinal)fail('ForeignSlackMessageRepliesRequest');
      const query: [string, string][] = [['channel',fields.channel],['ts',fields.ts],['limit',String(bound.pageSize)]];
      if(fields.cursor!==null)query.push(['cursor',fields.cursor]);
      if(fields.oldest!==null)query.push(['oldest',fields.oldest],['inclusive','false']);
      const admitted=await request(context,SLACK_MESSAGE_REPLIES_OPERATION,'GET','/api/conversations.replies',query,body=>{
        const admitted=checked(provider!.slackAdmitMessageRepliesPage(control,original,body));
        accountRows(provider!.slackMessageRepliesPageRowCount(admitted));return admitted;
      },undefined,original);
      if(context.project(()=>!provider!.slackMessageRepliesPageHasNext(admitted),undefined,[])){
        context.project(()=>checked(provider!.slackFinishMessageReplies(control,admitted)),undefined,[]);
        return control;
      }
      original=context.project(()=>checked(provider!.slackNextMessageRepliesRequest(control,admitted)),undefined,[]);
    }
    fail('SlackMessageRepliesPageLimit');
  };
  const readHistory=async(context: ReadContext, channelPage: ChannelPage, index: number)=>{
    const channel=channelPage.ids[index],
      pages: Readonly<{original: unknown; count: number}>[] = [], selectedReplies: unknown[] = [];
    const history=context.project(()=>{
      const selected=checked(provider!.slackPrepareMessageHistoryFromChannel(channelPage.original,index,
        bound.maxResponseBytes,bound.maxNodes,bound.maxDepth,Math.min(bound.maxRows,bound.pageSize,999),
        bound.maxCursorBytes,bound.maxValueNodes,bound.maxValueTextBytes,bound.maxPages));
      histories!.push(selected);
      if(!provider!.slackMessageHistoryMatchesChannel(selected,channelPage.original,index))fail('ForeignSlackOriginalChannel');
      return selected;
    },undefined,[]);
    await identity(context);
    let original=context.project(()=>checked(provider!.slackBeginMessageHistory(history)),undefined,[]);
    for(let ordinal=0;ordinal<bound.maxPages;ordinal++){
      const fields=context.project(()=>{
        if(!provider!.slackMessageHistoryRequestMatches(history,original))fail('ForeignSlackMessageHistoryRequest');
        return JSON.parse(provider!.slackMessageHistoryRequestJson(original)) as NativeRequestFields;
      },undefined,[]);
      if(fields.channel!==channel||fields.ordinal!==ordinal||fields.oldest!==undefined&&fields.oldest!==null){
        fail('ForeignSlackMessageHistoryRequest');
      }
      const query: [string, string][] = [['channel',channel],['limit',String(Math.min(bound.pageSize,999))]];
      if(fields.cursor!==null)query.push(['cursor',fields.cursor]);
      if(fields.latest!==null)query.push(['latest',fields.latest],['inclusive','false']);
      const page=await request(context,SLACK_MESSAGE_HISTORY_OPERATION,'GET','/api/conversations.history',query,body=>{
        const originalPage=checked(provider!.slackAdmitMessageHistoryPage(history,original,body));
        const count=provider!.slackMessagePageRowCount(originalPage);accountRows(count);
        return{original:originalPage,count};
      },undefined,original);
      pages.push(page);
      if(context.project(()=>!provider!.slackMessageHistoryPageHasNext(page.original),undefined,[])){
        context.project(()=>checked(provider!.slackFinishMessageHistory(history,page.original)),undefined,[]);break;
      }
      original=context.project(()=>checked(provider!.slackNextMessageHistoryRequest(history,page.original)),undefined,[]);
      if(ordinal+1===bound.maxPages)fail('SlackMessageHistoryPageLimit');
    }
    for(const page of pages)for(let row=0;row<page.count;row++){
      selectedReplies.push(await readReplies(context,page.original,row,channel));
    }
    const rows=context.project(()=>{
      const projection=checked(provider!.slackCoalesceMessageOriginals(history,selectedReplies,
        bound.maxTotalRows,bound.maxTotalRows,bound.maxNodes,bound.maxNodes,bound.maxDepth,bound.maxValueTextBytes));
      projections!.push(projection);
      const count=provider!.slackMessageProjectionRowCount(projection);
      if(count>bound.maxTotalRows-outputRows)fail('SlackMessageProjectionRowLimit');
      return JSON.parse(checked(provider!.slackMessageProjectionRowsWire(projection,names!,
        bound.maxRowsWireBytes,bound.maxRowsWireNodes,bound.maxRowsWireDepth)) as string) as readonly unknown[];
    },undefined,[]);
    await append(context,rows);
  };
  return Object.freeze({async read(context: ReadContext){
    if(started||retired)fail('InstalledSlackReaderAlreadyStarted');started=true;pending=true;
    try{
      context.project(()=>{
        const columns=(resource==='users'?provider!.slackUserListColumnNames:resource==='channels'
          ?provider!.slackChannelListColumnNames:provider!.slackMessageColumnNames)();
        if(new Set(names).size!==names!.length||names!.some(name=>!columns.includes(name)))fail('InvalidInstalledSlackRead');
        // Capture the complete declared row; SELECT remains the checked Program.
        names=Object.freeze(columns.slice());
      },undefined,[]);
      await list(context,resource);
      if(resource==='messages'){
        for(const page of channelPages!)for(let index=0;index<page.ids.length;index++)await readHistory(context,page,index);
        if(histories!.length===0)await append(context,[]);
      }
    }finally{pending=false;}
  },retire(){
    if(pending)return false;if(retired)return true;
    for(const control of replies!)provider!.slackCloseMessageReplies(control);
    for(const control of histories!)provider!.slackCloseMessageHistory(control);
    histories=replies=channelPages=projections=provider=names=undefined;
    retired=true;return true;
  }});
}
