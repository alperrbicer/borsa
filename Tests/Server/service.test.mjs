import { afterEach, test, expect } from 'bun:test'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { Repository } from '../../server/storage.mjs'
import { handler } from '../../server/http.mjs'
import { hash, acceptQuote, placeOrder } from '../../server/domain.mjs'
import { Feeds, normalizeAlpaca, normalizeLicensed, parseRSS, readURL } from '../../server/providers.mjs'
import { notificationPayload, PushDelivery } from '../../server/notifications.mjs'
const NOW=Date.parse('2026-10-02T15:00:00Z'), token='a'.repeat(64)
const dirs=[],repos=[]
const directory=()=>{const d=mkdtempSync(join(tmpdir(),'borsa-tests-'));dirs.push(d);return d}
const repo=()=>{const r=new Repository(join(directory(),'test.sqlite'),NOW);repos.push(r);return r}
afterEach(()=>{for(const r of repos.splice(0))try{r.close()}catch{};for(const d of dirs.splice(0))rmSync(d,{recursive:true,force:true})})
const request=(path,method='GET',body,auth=token)=>new Request('https://localhost'+path,{method,headers:{...(auth?{Authorization:'Bearer '+auth}:{}),'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})})
const rss='<rss><channel><item><title>Test official announcement</title><description>Policy statement</description><link>https://example.test/1</link><pubDate>Fri, 02 Oct 2026 15:00:00 GMT</pubDate></item></channel></rss>'
const rawQuote={latestQuote:{bp:100,ap:100.02,bs:2,as:3,t:new Date(NOW).toISOString()},prevDailyBar:{c:99}}
test('SQLite preserves account and credentials on restart; invalid mutations roll back',()=>{
  const directoryPath=directory(),path=join(directoryPath,'account.sqlite'),a=new Repository(path,NOW)
  a.addToken(token);a.update(s=>{s.settings.mode='auto'})
  expect(()=>a.update(s=>{s.wallets[0].cashCents=-1})).toThrow()
  const before=a.read();expect(before.wallets[0].cashCents).toBe(10_000_000);a.close()
  const b=new Repository(path,NOW+1000);repos.push(b)
  expect(b.read()).toEqual(before);expect(b.authorize(token)).toBe(true)
  expect(b.db.query('SELECT digest FROM credentials').get().digest).not.toBe(token)
})
test('corrupt persisted account fails instead of resetting funds',()=>{
  const r=repo(),path=r.db.filename
  r.db.query('UPDATE account SET value=?').run('{"version":0}')
  expect(()=>new Repository(path,NOW)).toThrow('sürümü')
  expect(r.db.query('SELECT value FROM account').get().value).toBe('{"version":0}')
})
test('TLS handler requires bearer authentication and blocks browser origins',async()=>{
  const r=repo();r.addToken(token);const app=handler(r,{now:()=>NOW})
  expect((await app(request('/snapshot','GET',undefined,null))).status).toBe(401)
  const browser=new Request('https://localhost/snapshot',{headers:{Authorization:'Bearer '+token,Origin:'https://evil.example'}})
  expect((await app(browser)).status).toBe(403)
  expect((await app(request('/snapshot'))).status).toBe(200)
  expect((await app(request('/unknown'))).status).toBe(404)
})
test('one-time pairing expires, locks after failed attempts and never leaks plaintext storage',async()=>{
  const r=repo(),path=join(directory(),'pairing.json');let now=NOW
  const app=handler(r,{pairingPath:path,now:()=>now})
  writeFileSync(path,JSON.stringify({digest:hash('123456'),expiresAt:NOW+180000}))
  for(let i=0;i<5;i++)expect((await app(request('/pair','POST',{code:'000000'},null))).status).toBe(401)
  expect((await app(request('/pair','POST',{code:'123456'},null))).status).toBe(429)
  now+=61000;const response=await app(request('/pair','POST',{code:'123456'},null))
  expect(response.status).toBe(200);expect(r.authorize((await response.json()).token)).toBe(true)
  expect((await app(request('/pair','POST',{code:'123456'},null))).status).toBe(401)
  writeFileSync(path,JSON.stringify({digest:hash('123456'),expiresAt:now-1}))
  expect((await app(request('/pair','POST',{code:'123456'},null))).status).toBe(401)
})
test('oversized, invalid and null JSON bodies fail without mutating balances',async()=>{
  const r=repo();r.addToken(token);const app=handler(r,{now:()=>NOW}),before=r.read()
  expect((await app(request('/settings','PATCH',{huge:'x'.repeat(20000)}))).status).toBe(413)
  expect((await app(request('/settings','PATCH',null))).status).toBe(400)
  const bad=new Request('https://localhost/settings',{method:'PATCH',headers:{Authorization:'Bearer '+token},body:'{'})
  expect((await app(bad)).status).toBe(400);expect(r.read()).toEqual(before)
})
test('concurrent duplicate HTTP requests create one order and one reservation',async()=>{
  const r=repo();r.addToken(token)
  r.update(s=>acceptQuote(s,normalizeAlpaca('AAPL',rawQuote,'iex',{timestamp:new Date(NOW).toISOString(),is_open:true},NOW),NOW))
  const app=handler(r,{now:()=>NOW}),input={id:'concurrent-order-1234',symbol:'AAPL',side:'buy',quantity:2,limitUnits:1_020_000}
  const responses=await Promise.all(Array.from({length:8},()=>app(request('/orders','POST',input))))
  expect(responses.every(x=>x.status===200)).toBe(true);expect(r.read().orders).toHaveLength(1)
})
test('Alpaca sizes are shares, not round lots, and delayed feed cannot open execution',()=>{
  const clock={timestamp:new Date(NOW).toISOString(),is_open:true}
  const q=normalizeAlpaca('AAPL',rawQuote,'iex',clock,NOW)
  expect(q.askSize).toBe(3);expect(q.bidSize).toBe(2);expect(q.priceUnits).toBe(1_000_100)
  expect(normalizeAlpaca('AAPL',rawQuote,'iex',{...clock,is_open:false},NOW).sessionOpen).toBe(false)
  expect(normalizeAlpaca('AAPL',rawQuote,'iex',clock,NOW+45001).sessionOpen).toBe(false)
  expect(normalizeAlpaca('AAPL',rawQuote,'delayed_sip',clock,NOW).delaySeconds).toBe(900)
})
test('official RSS and Turkish Atom dates retain actual source times and secure URLs',()=>{
  expect(parseRSS(rss,{source:'Test',market:'US'},NOW)[0].publishedAt).toBe(NOW)
  const atom='<feed><entry><title>Test duyurusu</title><link href="http://www.tcmb.gov.tr/test"/><published>02 Eki 2026 18:00:00</published><summary><![CDATA[Test <b>duyuru</b>]]></summary></entry></feed>'
  const parsed=parseRSS(atom,{source:'TCMB',market:'BIST'},NOW)[0]
  expect(parsed.publishedAt).toBe(NOW);expect(parsed.url).toBe('https://www.tcmb.gov.tr/test');expect(parsed.summary).toBe('Test duyuru')
  expect(parseRSS('<item><title>no date</title></item>',{source:'Test'},NOW)).toHaveLength(0)
})
test('licensed bridge explicitly requires source, time, delay and session',()=>{
  expect(()=>normalizeLicensed({version:1,source:'Licensed test',quotes:[{symbol:'THYAO'}]},NOW)).toThrow()
  const input={version:1,source:'Licensed test',quotes:[{symbol:'THYAO',timestamp:NOW,sessionOpen:true,quality:'realtime',delaySeconds:0}]}
  expect(normalizeLicensed(input,NOW)[0].providerId).toBe('licensed')
})
test('provider body size and HTTP failure are bounded',async()=>{
  await expect(readURL('https://example.test',{},async()=>new Response('x',{status:429}))).rejects.toThrow('HTTP 429')
  await expect(readURL('https://example.test',{},async()=>new Response('x'.repeat(2_000_001)))).rejects.toThrow('boyut')
})
test('free startup fetches real feed shapes, not fabricated quotes',async()=>{
  const r=repo(),feeds=new Feeds({},async()=>new Response(rss))
  await feeds.cycle(r,NOW);const s=r.read()
  expect(Object.keys(s.quotes)).toHaveLength(0);expect(s.news.length).toBeGreaterThan(0)
  expect(s.health.find(x=>x.id==='alpaca').status).toBe('setup')
  expect(s.health.find(x=>x.id==='TCMB').status).toBe('connected')
})
test('data outage immediately closes execution even if cached quotes are young',async()=>{
  const r=repo();r.update(s=>acceptQuote(s,normalizeAlpaca('AAPL',rawQuote,'iex',{timestamp:new Date(NOW).toISOString(),is_open:true},NOW),NOW))
  const feeds=new Feeds({ALPACA_KEY_ID:'test',ALPACA_SECRET_KEY:'test'},async()=>new Response('unavailable',{status:503}))
  await feeds.cycle(r,NOW+1000)
  expect(r.read().quotes.AAPL.sessionOpen).toBe(false)
  expect(()=>r.update(s=>placeOrder(s,{id:'outage-order-123456',symbol:'AAPL',side:'buy',quantity:1,limitUnits:1_020_000},NOW+1000))).toThrow('kapalı')
})
test('authorized BIST bridge supports sourced Turkish company news and quotes together',async()=>{
  const r=repo();r.update(s=>{s.settings.mode='auto'})
  const envelope={version:1,source:'Licensed TEST fixture',quotes:[{symbol:'THYAO',currency:'TRY',priceUnits:1000000,bidUnits:1000000,askUnits:1000000,bidSize:50,askSize:50,previousCloseUnits:990000,timestamp:NOW,quality:'realtime',delaySeconds:0,sessionOpen:true}],news:[{id:'bist-test-news',title:'THYAO kâr beklentisini yükseltti',url:'https://example.test/turkish-news',publishedAt:NOW,symbols:['THYAO'],scope:'company',market:'BIST'}]}
  const feeds=new Feeds({LICENSED_FEED_URL:'https://licensed.example.test/feed',LICENSED_FEED_TOKEN:'fixture-only'},async url=>new URL(url).hostname==='licensed.example.test'?Response.json(envelope):new Response(rss))
  envelope.news.push(null, {id:'invalid-no-source-time'})
  await feeds.cycle(r,NOW)
  const s=r.read();expect(s.orders).toHaveLength(1);expect(s.orders[0].symbol).toBe('THYAO');expect(s.orders[0].side).toBe('buy')
  expect(s.decisions.find(x=>x.newsId==='bist-test-news').source).toBe('Licensed TEST fixture')
  expect(s.wallets[1].cashCents).toBe(1000000)
})
test('APNs carries a review link only, expires unanswered requests and deduplicates accepted deliveries',async()=>{
  const r=repo(),now=Date.now()
  r.update(s=>{s.decisions=[{id:'review-1',symbol:'AAPL',state:'review',expiresAt:now+60000},{id:'expired',symbol:'MSFT',state:'review',expiresAt:now-1}]})
  r.db.query('INSERT INTO devices VALUES (?,?)').run('d'.repeat(64),now)
  const push=new PushDelivery({APNS_KEY_PATH:'test',APNS_KEY_ID:'test',APNS_TEAM_ID:'test'}),sent=[]
  push.send=async(device,decision)=>{sent.push(decision.id);return true}
  await push.flush(r);await push.flush(r)
  expect(sent).toEqual(['review-1'])
  const payload=notificationPayload(r.read().decisions[0]);expect(payload.decisionId).toBe('review-1');expect(JSON.stringify(payload)).not.toContain('cash')
})
