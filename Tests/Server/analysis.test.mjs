import { test, expect } from 'bun:test'
import { initialState, acceptQuote, changeSettings, processOrders } from '../../server/domain.mjs'
import { addNews, evaluateNews, previewDecision, reviewDecision } from '../../server/analysis.mjs'
const NOW=Date.parse('2026-10-02T15:00:00Z')
const news=(values={})=>({id:'test-news',title:'Apple raises guidance',summary:'Apple raises its outlook.',url:'https://example.test/news',source:'Test fixture only',sourceTier:'licensed',scope:'company',symbols:['AAPL'],market:'US',publishedAt:NOW,...values})
function setup(mode='review') {
  const s=initialState(NOW);s.settings.mode=mode
  acceptQuote(s,{symbol:'AAPL',currency:'USD',priceUnits:1_000_000,bidUnits:1_000_000,askUnits:1_000_000,bidSize:100,askSize:100,previousCloseUnits:990_000,timestamp:NOW,quality:'realtime',delaySeconds:0,sessionOpen:true,source:'Test fixture'},NOW)
  return s
}
test('aligned company news generates source-backed review with no unsolicited trade',()=>{
  const s=setup();addNews(s,[news()],NOW);evaluateNews(s,NOW)
  expect(s.decisions[0].confidence).toBe('high');expect(s.orders).toHaveLength(0)
  expect(s.decisions[0].sourceURL).toBe('https://example.test/news')
  expect(s.decisions[0].companyImpact).toContain('olumlu')
  expect(s.decisions[0].sectorImpact).toContain('Teknoloji')
})
test('auto submits once, waits for a future quote, and keeps the decision linked',()=>{
  const s=setup('auto');addNews(s,[news()],NOW);evaluateNews(s,NOW);evaluateNews(s,NOW+10)
  expect(s.orders).toHaveLength(1);expect(s.decisions[0].state).toBe('queued')
  processOrders(s,NOW);expect(s.positions).toHaveLength(0)
  acceptQuote(s,{...s.quotes.AAPL,timestamp:NOW+1000},NOW+1000);processOrders(s,NOW+1000)
  expect(s.decisions[0].state).toBe('executed');expect(s.positions[0].quantity).toBe(2)
})
test('ambiguous or unrelated company tags never trigger automatic trades',()=>{
  for (const values of [{title:'Apple might raise guidance',summary:''},{title:'Microsoft raises guidance',summary:''},{scope:'macro'},{sourceTier:'unknown'},{title:'Apple raises guidance but cuts outlook'}]) {
    const s=setup('auto');addNews(s,[news(values)],NOW);evaluateNews(s,NOW)
    expect(s.orders).toHaveLength(0);expect(s.decisions[0].state).toBe('review')
  }
})
test('unanswered, expired and paused decisions cannot execute',()=>{
  const s=setup();addNews(s,[news()],NOW);evaluateNews(s,NOW)
  expect(()=>reviewDecision(s,s.decisions[0].id,'buy',NOW+900001)).toThrow('süresi')
  evaluateNews(s,NOW+900001);expect(s.decisions[0].state).toBe('expired');expect(s.orders).toHaveLength(0)
  const paused=setup('paused');addNews(paused,[news()],NOW);evaluateNews(paused,NOW);expect(paused.decisions[0].state).toBe('held')
})
test('preview is non-mutating and changed prices require a new approval',()=>{
  const s=setup();addNews(s,[news()],NOW);evaluateNews(s,NOW)
  const id=s.decisions[0].id,preview=previewDecision(s,id,'buy',NOW)
  expect(preview.quantity).toBe(2);expect(s.orders).toHaveLength(0)
  acceptQuote(s,{...s.quotes.AAPL,askUnits:1_001_000,timestamp:NOW+1000},NOW+1000)
  expect(()=>reviewDecision(s,id,'buy',NOW+1000,preview)).toThrow('değişti')
  const newer=previewDecision(s,id,'buy',NOW+1000);reviewDecision(s,id,'buy',NOW+1001,newer)
  reviewDecision(s,id,'buy',NOW+1002,newer);expect(s.orders).toHaveLength(1)
})
test('negative news cannot short an empty account',()=>{
  const s=setup('auto');addNews(s,[news({title:'Apple cuts guidance',summary:''})],NOW);evaluateNews(s,NOW)
  expect(s.decisions[0].state).toBe('held');expect(s.orders).toHaveLength(0)
})
test('negative aligned news sells owned shares with costs, not synthetic shorts',()=>{
  const s=setup('auto');s.positions=[{symbol:'AAPL',currency:'USD',quantity:2,costCents:20000}];s.wallets[1].cashCents=980000
  acceptQuote(s,{...s.quotes.AAPL,priceUnits:950000,bidUnits:950000,askUnits:950000,previousCloseUnits:1000000},NOW)
  addNews(s,[news({title:'Apple cuts guidance',summary:''})],NOW);evaluateNews(s,NOW)
  expect(s.orders[0].side).toBe('sell');expect(s.orders[0].quantity).toBe(2)
  acceptQuote(s,{...s.quotes.AAPL,timestamp:NOW+1000},NOW+1000);processOrders(s,NOW+1000)
  expect(s.positions).toHaveLength(0);expect(s.wallets[1].realizedCents).toBeLessThan(0)
})
test('negated, third-party and cross-company headlines require review',()=>{
  for(const title of ['Apple does not expect record profit','Analysts say Apple raises guidance','Apple stock falls as Microsoft raises guidance']){
    const s=setup('auto');addNews(s,[news({title,summary:''})],NOW);evaluateNews(s,NOW);expect(s.orders).toHaveLength(0)
  }
})
test('Turkish denials and future-dated stories do not become automatic signals',()=>{
  for(const title of ['AAPL kâr beklentisini yükseltmedi','AAPL kâr beklentisini yükseltti iddiası yalanlandı']){
    const s=setup('auto');addNews(s,[news({title,summary:''})],NOW);evaluateNews(s,NOW);expect(s.orders).toHaveLength(0)
  }
  const s=setup('auto');addNews(s,[news({publishedAt:NOW+5000})],NOW);evaluateNews(s,NOW);expect(s.news).toHaveLength(0)
})
test('stopping automation cancels its pending orders and closes their decisions',()=>{
  const s=setup('auto');addNews(s,[news()],NOW);evaluateNews(s,NOW);changeSettings(s,{mode:'paused'})
  expect(s.orders[0].status).toBe('cancelled');expect(s.decisions[0].state).toBe('closed')
})
test('stale or future news cannot be used; evidence is immutable',()=>{
  const s=setup('auto');addNews(s,[news({publishedAt:NOW-31*60000})],NOW);evaluateNews(s,NOW)
  expect(s.decisions[0].state).toBe('held');expect(s.orders).toHaveLength(0)
  addNews(s,[news({title:'New contradictory headline'})],NOW+1000)
  expect(s.news[0].title).toBe('Apple raises guidance')
  addNews(s,[news({id:'future',url:'https://example.test/future',publishedAt:NOW+60001})],NOW);expect(s.news).toHaveLength(1)
})
