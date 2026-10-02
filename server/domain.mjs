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
  if (!q || q.timestamp > now + 2000 || now - q.timestamp > MAX_AGE || now - q.receivedAt > MAX_AGE) return null
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
