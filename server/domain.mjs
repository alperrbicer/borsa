import { createHash } from 'node:crypto'
export const CATALOG = [
  ['THYAO','Türk Hava Yolları','Ulaştırma','BIST','TRY'], ['ASELS','Aselsan','Savunma','BIST','TRY'],
  ['TUPRS','Tüpraş','Enerji','BIST','TRY'], ['GARAN','Garanti BBVA','Bankacılık','BIST','TRY'],
  ['SISE','Şişecam','Sanayi','BIST','TRY'], ['KCHOL','Koç Holding','Holding','BIST','TRY'],
  ['BIMAS','BİM','Perakende','BIST','TRY'], ['AKBNK','Akbank','Bankacılık','BIST','TRY'],
  ['AAPL','Apple','Teknoloji','US','USD'], ['MSFT','Microsoft','Teknoloji','US','USD'],
  ['NVDA','NVIDIA','Teknoloji','US','USD'], ['AMZN','Amazon','Perakende','US','USD'],
  ['GOOGL','Alphabet','İletişim','US','USD'], ['JPM','JPMorgan Chase','Bankacılık','US','USD'],
  ['SPY','SPDR S&P 500 ETF','Endeks','US','USD'], ['QQQ','Invesco QQQ ETF','Endeks','US','USD'],
].map(([symbol,name,sector,market,currency]) => ({symbol,name,sector,market,currency}))
export const instrument = symbol => CATALOG.find(x => x.symbol === symbol)
export const MAX_AGE = 45_000, VERSION = 1, MAX_MONEY = 1_000_000_000_000
export const hash = value => createHash('sha256').update(value).digest('hex')
export class DomainError extends Error { constructor(message, status = 422) { super(message); this.status = status } }
export const requireValue = (condition, message) => { if (!condition) throw new DomainError(message) }
export const integer = (value, low, high) => Number.isSafeInteger(value) && value >= low && value <= high
export const fee = (cents, bps) => cents > 0 ? Math.max(bps > 0 ? 1 : 0, Math.ceil(cents * bps / 10_000)) : 0
const gross = (units, side) => side === 'buy' ? Math.ceil(units / 100) : Math.floor(units / 100)
export const nowDay = (now, market) => new Intl.DateTimeFormat('en-CA', {timeZone:market === 'US' ? 'America/New_York' : 'Europe/Istanbul', year:'numeric',month:'2-digit',day:'2-digit'}).format(now)
export function initialState(now = Date.now()) {
  return { version:VERSION, createdAt:now, revision:0, quotes:{}, history:{}, news:[], decisions:[], orders:[], positions:[],
    wallets:[{currency:'TRY', initialCashCents:10_000_000, cashCents:10_000_000, realizedCents:0, feesCents:0},
      {currency:'USD', initialCashCents:1_000_000, cashCents:1_000_000, realizedCents:0, feesCents:0}],
    settings:{mode:'review', maxPositionPercent:10, maxSectorPercent:30, maxDailyLossPercent:2, commissionBps:10, slippageBps:5, maxDailyOrders:10, cooldownMinutes:30},
    baselines:{}, health:[], lastCycleAt:null, watchlist:['THYAO','ASELS','AAPL','MSFT'], appliedActions:[] }
}
export function freshQuote(state, symbol, now, executable = false) {
  const q = state.quotes[symbol]
  if (!q || q.timestamp > now + 2000 || q.receivedAt > now + 2000 || now - q.timestamp > MAX_AGE || now - q.receivedAt > MAX_AGE) return null
  if (executable && (!q.sessionOpen || q.quality !== 'realtime' || q.delaySeconds !== 0 || !integer(q.bidUnits,1,1_000_000_000) || !integer(q.askUnits,q.bidUnits,1_000_000_000))) return null
  return q
}
export function quoteBlock(state, symbol, now) {
  const q = state.quotes[symbol]
  if (!q) return 'Fiyat kaynağı bağlı değil.'
  if (q.quality !== 'realtime' || q.delaySeconds !== 0) return 'Gecikmeli veya gün sonu veriyle gün içi işlem yapılmaz.'
  if (!freshQuote(state,symbol,now)) return 'Fiyat güncel değil; yeni veri bekleniyor.'
  if (!q.sessionOpen) return 'Piyasa kapalı veya seans durumu doğrulanamadı.'
  if (!freshQuote(state,symbol,now,true)) return 'Geçerli alış/satış kotasyonu bekleniyor.'
  return null
}
function reserve(order, settings) {
  if (order.status !== 'pending' || order.side !== 'buy') return 0
  const remainingGross = gross(order.limitUnits * order.remaining, 'buy')
  return remainingGross + Math.max(0, fee(gross(order.grossUnits,'buy') + remainingGross, settings.commissionBps) - order.feesCents)
}
export function reservedCash(state, currency, excluding) {
  return state.orders.filter(x => x.id !== excluding && instrument(x.symbol)?.currency === currency).reduce((sum,x) => sum + reserve(x,state.settings),0)
}
export function availableShares(state, symbol, excluding) {
  return (state.positions.find(x => x.symbol === symbol)?.quantity ?? 0) - state.orders.filter(x => x.id !== excluding && x.symbol === symbol && x.side === 'sell' && x.status === 'pending').reduce((sum,x) => sum + x.remaining,0)
}
export function equity(state, currency, now) {
  let result = state.wallets.find(x => x.currency === currency).cashCents
  for (const position of state.positions.filter(x => x.currency === currency)) {
    const quote = freshQuote(state,position.symbol,now)
    if (!quote) return null
    result += Math.floor(quote.priceUnits * position.quantity / 100)
  }
  return result
}
export function updateBaselines(state, now) {
  for (const wallet of state.wallets) {
    const value = equity(state,wallet.currency,now)
    if (value === null) continue
    const day = nowDay(now,wallet.currency === 'USD' ? 'US' : 'BIST'), previous = state.baselines[wallet.currency]
    state.baselines[wallet.currency] = {day, start:previous?.day === day ? previous.start : value,
      peak:Math.max(previous?.peak ?? wallet.initialCashCents,value)}
  }
}

function riskReason(state, request, now, excluding) {
  if (request.side === 'sell') return null
  const item = instrument(request.symbol), value = equity(state,item.currency,now)
  if (value === null) return 'Portföyde güncel fiyatı olmayan varlık var.'
  const baseline = state.baselines[item.currency]
  if (baseline?.day === nowDay(now,item.market) && (baseline.start-value)/baseline.start*100 >= state.settings.maxDailyLossPercent) return 'Günlük kayıp sınırı aşıldı; yeni alışlar durdu.'
  const pending = state.orders.filter(x => x.status === 'pending' && x.side === 'buy' && x.id !== excluding)
  const positionValue = state.positions.filter(x => x.symbol === request.symbol).reduce((s,x) => s + Math.floor(state.quotes[x.symbol].priceUnits*x.quantity/100),0)
  const samePending = pending.filter(x => x.symbol === request.symbol).reduce((s,x) => s + Math.ceil(x.limitUnits*x.remaining/100),0)
  const requested = Math.ceil(request.limitUnits*request.quantity/100)
  if (positionValue + samePending + requested > value*state.settings.maxPositionPercent/100) return 'Hisse başına pozisyon sınırı aşılıyor.'
  const sectorValue = state.positions.filter(x => instrument(x.symbol).sector === item.sector && x.currency === item.currency).reduce((s,x) => s + Math.floor(state.quotes[x.symbol].priceUnits*x.quantity/100),0)
  const sectorPending = pending.filter(x => instrument(x.symbol).currency === item.currency && instrument(x.symbol).sector === item.sector).reduce((s,x) => s + Math.ceil(x.limitUnits*x.remaining/100),0)
  if (sectorValue + sectorPending + requested > value*state.settings.maxSectorPercent/100) return 'Sektör yoğunlaşma sınırı aşılıyor.'
  return null
}
export function placeOrder(state, request, now = Date.now(), {decisionId = null} = {}) {
  const old = state.orders.find(x => x.id === request.id)
  if (old) {
    requireValue(['symbol','side','quantity','limitUnits'].every(k => old[k] === request[k]), 'Bu istek kimliği farklı bir emir için kullanılmış.')
    return old
  }
  requireValue(typeof request.id === 'string' && /^[a-zA-Z0-9-]{16,80}$/.test(request.id), 'Geçersiz emir kimliği.')
  const item = instrument(request.symbol)
  requireValue(item && ['buy','sell'].includes(request.side), 'Geçersiz hisse veya işlem yönü.')
  requireValue(integer(request.quantity,1,100_000) && integer(request.limitUnits,1,1_000_000_000), 'Geçersiz adet veya limit fiyat.')
  requireValue(state.orders.length < 10_000, 'Hesap emir sınırına ulaştı.')
  const block = quoteBlock(state,request.symbol,now)
  requireValue(!block, block)
  updateBaselines(state,now)
  const day = nowDay(now,item.market)
  requireValue(state.orders.filter(x => instrument(x.symbol).market === item.market && nowDay(x.createdAt,item.market) === day).length < state.settings.maxDailyOrders, 'Günlük emir sınırına ulaşıldı.')
  if (decisionId) requireValue(!state.orders.some(x => x.symbol === request.symbol && now-x.createdAt < state.settings.cooldownMinutes*60_000), 'Bu hissede işlem bekleme süresi dolmadı.')
  const risk = riskReason(state,request,now)
  requireValue(!risk,risk)
  const order = {id:request.id,symbol:request.symbol,side:request.side,quantity:request.quantity,remaining:request.quantity,
    limitUnits:request.limitUnits,status:'pending',createdAt:now,expiresAt:now+15*60_000,filledQty:0,grossUnits:0,feesCents:0,
    executionUnits:null,filledAt:null,decisionId,reason:decisionId ? 'Haber değerlendirmesi' : 'Kullanıcı emri',source:'',requestedSource:state.quotes[request.symbol].source,lastQuoteAt:null,lastFillQuantity:0}
  const wallet = state.wallets.find(x => x.currency === item.currency)
  if (request.side === 'buy') requireValue(reserve(order,state.settings) <= wallet.cashCents-reservedCash(state,item.currency), 'Kullanılabilir bakiye komisyon dahil yetersiz.')
  else requireValue(request.quantity <= availableShares(state,request.symbol), 'Satılabilir adet yetersiz.')
  state.orders.unshift(order)
  return order
}
export function cancelOrder(state, id) {
  const order = state.orders.find(x => x.id === id)
  requireValue(order, 'Emir bulunamadı.')
  if (order.status === 'cancelled') return
  requireValue(order.status === 'pending','Yalnızca bekleyen emir iptal edilebilir.')
  order.status = 'cancelled'; order.reason = 'Kullanıcı iptal etti.'
  syncDecision(state,order)
}
function syncDecision(state,order) {
  const decision=state.decisions.find(x=>x.id===order.decisionId)
  if (!decision) return
  decision.state=order.status==='filled'?'executed':order.status==='pending'?'queued':'closed'
  decision.reason=order.status==='filled'?'Sanal emir güncel kotasyonlarla gerçekleşti.':order.status==='pending'?`${order.filledQty}/${order.quantity} adet gerçekleşti; kalan emir bekliyor.`:`${order.reason} Gerçekleşen: ${order.filledQty}/${order.quantity} adet.`
}
export function processOrders(state, now = Date.now()) {
  updateBaselines(state,now)
  for (const order of [...state.orders].reverse()) {
    if (order.status !== 'pending') continue
    if (now >= order.expiresAt) { order.status='expired'; order.reason='Emrin 15 dakikalık süresi doldu.'; syncDecision(state,order); continue }
    if (state.settings.mode === 'paused' && order.decisionId) continue
    const q = freshQuote(state,order.symbol,now,true)
    if (!q || q.timestamp <= order.createdAt || q.timestamp <= (order.lastQuoteAt ?? 0)) continue
    if (order.requestedSource && order.requestedSource!==q.source) { order.status='cancelled'; order.reason='Fiyat kaynağı değişti; yeni kaynakla tekrar değerlendirme gerekli.'; syncDecision(state,order); continue }
    const risk = riskReason(state,{...order,quantity:order.remaining},now,order.id)
    if (risk) { order.status='cancelled'; order.reason=risk; syncDecision(state,order); continue }
    const slip = state.settings.slippageBps
    const price = order.side === 'buy' ? Math.ceil(q.askUnits*(10_000+slip)/10_000) : Math.floor(q.bidUnits*(10_000-slip)/10_000)
    if (order.side === 'buy' ? price > order.limitUnits : price < order.limitUnits) continue
    const size = order.side === 'buy' ? q.askSize : q.bidSize
    if (!integer(size,1,100_000_000)) continue
    const consumed = state.orders.filter(x => x.symbol === order.symbol && x.side === order.side && x.lastQuoteAt === q.timestamp).reduce((s,x) => s+x.lastFillQuantity,0)
    const quantity = Math.min(order.remaining,Math.max(0,size-consumed))
    if (!quantity) continue
    const item=instrument(order.symbol), wallet=state.wallets.find(x=>x.currency===item.currency)
    const previousGross=gross(order.grossUnits,order.side), nextGrossUnits=order.grossUnits+price*quantity
    const nextGross=gross(nextGrossUnits,order.side), cost=nextGross-previousGross
    const nextFee=fee(nextGross,state.settings.commissionBps), commission=nextFee-order.feesCents
    let position=state.positions.find(x=>x.symbol===order.symbol)
    if (order.side === 'buy') {
      if (cost+commission > wallet.cashCents-reservedCash(state,item.currency,order.id)) continue
      wallet.cashCents-=cost+commission
      if (!position) { position={symbol:order.symbol,currency:item.currency,quantity:0,costCents:0}; state.positions.push(position) }
      position.quantity+=quantity; position.costCents+=cost+commission
    } else {
      if (!position || position.quantity < quantity) continue
      const removedCost=quantity===position.quantity ? position.costCents : Math.floor(position.costCents*quantity/position.quantity)
      wallet.cashCents+=cost-commission; wallet.realizedCents+=cost-commission-removedCost
      position.quantity-=quantity; position.costCents-=removedCost
      state.positions=state.positions.filter(x=>x.quantity>0)
    }
    wallet.feesCents+=commission
    order.grossUnits=nextGrossUnits; order.feesCents=nextFee; order.remaining-=quantity; order.filledQty+=quantity
    order.executionUnits=Math.round(order.grossUnits/order.filledQty); order.filledAt=now; order.lastQuoteAt=q.timestamp; order.lastFillQuantity=quantity
    order.source=q.source; order.status=order.remaining===0?'filled':'pending'
    order.fills??=[]
    order.fills.push({quantity,priceUnits:price,feeCents:commission,quoteAt:q.timestamp,filledAt:now,source:q.source})
    syncDecision(state,order)
  }
}
export function acceptQuote(state, q, now = Date.now()) {
  const item = instrument(q.symbol)
  requireValue(item && q.currency === item.currency && integer(q.priceUnits,1,1_000_000_000), 'Sağlayıcı geçersiz fiyat döndürdü.')
  requireValue(Number.isFinite(q.timestamp) && q.timestamp > 0 && q.timestamp <= now+2000 && typeof q.source === 'string' && q.source.length>0, 'Sağlayıcı zamanı veya kaynağı geçersiz.')
  requireValue(['realtime','delayed','eod'].includes(q.quality) && integer(q.delaySeconds,0,172800) && typeof q.sessionOpen==='boolean','Sağlayıcı gecikmesi veya seans bilgisi geçersiz.')
  if (state.quotes[q.symbol]?.timestamp > q.timestamp) return
  state.quotes[q.symbol]={...q,receivedAt:now}
  const history=state.history[q.symbol]??[]
  if (!history.some(x=>x.at===q.timestamp)) history.push({at:q.timestamp,priceUnits:q.priceUnits})
  state.history[q.symbol]=history.sort((a,b)=>a.at-b.at).slice(-480)
}
export function changeSettings(state, values) {
  requireValue(values && typeof values==='object' && !Array.isArray(values),'Geçersiz ayarlar.')
  const bounds={maxPositionPercent:[1,50],maxSectorPercent:[5,100],maxDailyLossPercent:[1,20],commissionBps:[0,200],slippageBps:[0,200],maxDailyOrders:[1,100],cooldownMinutes:[1,1440]}
  const next={...state.settings}
  for (const [key,value] of Object.entries(values)) {
    if (key==='mode') { requireValue(['paused','review','auto'].includes(value),'Geçersiz otomasyon modu.'); next.mode=value }
    else { requireValue(bounds[key] && integer(value,...bounds[key]),'Geçersiz risk ayarı.'); next[key]=value }
  }
  requireValue(next.maxSectorPercent>=next.maxPositionPercent,'Sektör sınırı hisse sınırından küçük olamaz.')
  if (next.commissionBps !== state.settings.commissionBps || next.slippageBps !== state.settings.slippageBps) requireValue(!state.orders.some(x=>x.status==='pending'),'Masraf ayarını değiştirmeden bekleyen emirleri iptal et.')
  state.settings=next
  if (next.mode==='paused') for (const order of state.orders.filter(x=>x.status==='pending' && x.decisionId)) { order.status='cancelled'; order.reason='Otomasyon durduruldu.'; syncDecision(state,order) }
}
export function validateState(state) {
  requireValue(state?.version===VERSION && Array.isArray(state.wallets) && state.wallets.length===2,'Hesap sürümü veya yapısı geçersiz.')
  requireValue(['positions','orders','news','decisions','health','watchlist'].every(key=>Array.isArray(state[key])) && state.quotes && state.history && state.baselines,'Hesap kayıtları eksik.')
  requireValue(integer(state.createdAt,1,Number.MAX_SAFE_INTEGER) && integer(state.revision,0,Number.MAX_SAFE_INTEGER),'Hesap zamanı veya sürümü geçersiz.')
  changeSettings({settings:state.settings,orders:[]},state.settings)
  requireValue(new Set(state.wallets.map(x=>x.currency)).size===2,'Tekrarlanan para birimi.')
  for (const w of state.wallets) {
    requireValue(['USD','TRY'].includes(w.currency) && integer(w.initialCashCents,1,MAX_MONEY) && integer(w.cashCents,0,MAX_MONEY) && integer(w.feesCents,0,MAX_MONEY) && integer(w.realizedCents,-MAX_MONEY,MAX_MONEY) && reservedCash(state,w.currency)<=w.cashCents,'Hesap bakiyesi tutarsız.')
    requireValue(w.cashCents+state.positions.filter(p=>p.currency===w.currency).reduce((total,p)=>total+p.costCents,0)===w.initialCashCents+w.realizedCents,'Nakit ve maliyet defteri dengede değil.')
    requireValue(w.feesCents===state.orders.filter(o=>instrument(o.symbol)?.currency===w.currency).reduce((total,o)=>total+o.feesCents,0),'Komisyon defteri tutarsız.')
  }
  requireValue(new Set(state.positions.map(x=>x.symbol)).size===state.positions.length,'Tekrarlanan varlık.')
  requireValue(new Set(state.orders.map(x=>x.id)).size===state.orders.length,'Tekrarlanan emir.')
  for (const p of state.positions) requireValue(instrument(p.symbol)?.currency===p.currency && integer(p.quantity,1,1_000_000) && integer(p.costCents,0,MAX_MONEY) && availableShares(state,p.symbol)>=0,'Hisse kaydı tutarsız.')
  for (const o of state.orders) requireValue(instrument(o.symbol) && ['buy','sell'].includes(o.side) && integer(o.quantity,1,100_000) && integer(o.limitUnits,1,1_000_000_000) && integer(o.remaining,0,o.quantity) && integer(o.filledQty,0,o.quantity) && o.filledQty+o.remaining===o.quantity && integer(o.feesCents,0,MAX_MONEY) && integer(o.grossUnits,0,Number.MAX_SAFE_INTEGER) && ['pending','filled','cancelled','expired'].includes(o.status) && (o.status!=='filled'||o.remaining===0),'Emir kaydı tutarsız.')
  requireValue(state.orders.length<=10_000 && state.news.length<=500 && state.decisions.length<=2000,'Kayıt sınırı aşıldı.')
}
export function snapshot(state, now = Date.now()) {
  const copy=structuredClone(state)
  for (const d of copy.decisions) if (d.state==='review' && d.expiresAt<=now) d.state='expired'
  const wallets=copy.wallets.map(w=>{
    const value=equity(copy,w.currency,now), baseline=copy.baselines[w.currency]
    return {...w,reservedCents:reservedCash(copy,w.currency),availableCents:w.cashCents-reservedCash(copy,w.currency),
      holdingValueCents:value===null?null:value-w.cashCents,netProfitCents:value===null?null:value-w.initialCashCents,
      dailyLossPercent:value!==null&&baseline?.start>0?Math.max(0,(baseline.start-value)/baseline.start*100):null,
      drawdownPercent:value!==null&&baseline?.peak>0?Math.max(0,(baseline.peak-value)/baseline.peak*100):null}
  })
  return {...copy,quotes:undefined,history:undefined,baselines:undefined,appliedActions:undefined,serverTime:now,wallets,
    orders:copy.orders.slice(0,500).map(({fills,...order})=>order),totalOrders:copy.orders.length,
    instruments:CATALOG.map(i=>({...i,quote:copy.quotes[i.symbol]??null,history:copy.history[i.symbol]??[],blockedReason:quoteBlock(copy,i.symbol,now)})),
    positions:copy.positions.map(p=>{const q=freshQuote(copy,p.symbol,now);const value=q?Math.floor(q.priceUnits*p.quantity/100):null;return {...p,marketValueCents:value,profitCents:value===null?null:value-p.costCents}})}
}
