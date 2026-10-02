import { describe, test, expect } from 'bun:test'
import { randomUUID } from 'node:crypto'
import { initialState, acceptQuote, placeOrder, processOrders, cancelOrder, changeSettings, validateState, snapshot, freshQuote, reservedCash, availableShares, updateBaselines } from '../../server/domain.mjs'

export const NOW=Date.parse('2026-10-02T15:00:00Z')
export function quote(symbol='AAPL',at=NOW,values={}) {
  return {symbol,currency:symbol==='THYAO'?'TRY':'USD',priceUnits:1_000_000,bidUnits:1_000_000,askUnits:1_000_000,bidSize:100,askSize:100,timestamp:at,source:'Test fixture only',quality:'realtime',delaySeconds:0,sessionOpen:true,previousCloseUnits:990_000,...values}
}
export function account() {const s=initialState(NOW);acceptQuote(s,quote(),NOW);return s}
export const order=(values={})=>({id:randomUUID(),symbol:'AAPL',side:'buy',quantity:5,limitUnits:1_020_000,...values})
const tick=(s,at=NOW+1000,values={})=>{acceptQuote(s,quote('AAPL',at,values),at);processOrders(s,at);validateState(s)}

describe('paper account and execution',()=>{
  test('starts with separate empty TRY/USD accounts and never invents prices',()=>{
    const view=snapshot(initialState(NOW),NOW)
    expect(view.wallets.map(x=>x.cashCents)).toEqual([10_000_000,1_000_000])
    expect(view.positions).toHaveLength(0)
    expect(view.instruments.every(x=>x.quote===null&&x.history.length===0)).toBe(true)
    expect(()=>placeOrder(initialState(NOW),order(),NOW)).toThrow('Fiyat kaynağı')
  })
  test.each(['delayed','eod'])('%s data cannot execute',quality=>{
    const s=account();acceptQuote(s,quote('AAPL',NOW,{quality,delaySeconds:900}),NOW)
    expect(()=>placeOrder(s,order(),NOW)).toThrow('Gecikmeli')
  })
  test('closed, stale, future and crossed quotes fail closed',()=>{
    for(const values of [{sessionOpen:false},{bidUnits:1_020_000,askUnits:1_000_000}]){
      const s=account();acceptQuote(s,quote('AAPL',NOW,values),NOW);expect(()=>placeOrder(s,order(),NOW)).toThrow()
    }
    const s=account();expect(()=>placeOrder(s,order(),NOW+45_001)).toThrow('güncel')
    expect(()=>acceptQuote(s,quote('AAPL',NOW+2001),NOW)).toThrow('zamanı')
  })
  test('submission and repeated old quotes never fill; subsequent quotes do',()=>{
    const s=account(),request=order();placeOrder(s,request,NOW)
    processOrders(s,NOW);processOrders(s,NOW+1000)
    expect(s.orders[0].filledQty).toBe(0)
    tick(s);expect(s.orders[0].status).toBe('filled');expect(s.positions[0].quantity).toBe(5)
    expect(s.wallets[0].cashCents).toBe(10_000_000)
  })
  test('request retry is idempotent and mismatched reuse is rejected',()=>{
    const s=account(),request=order();placeOrder(s,request,NOW);placeOrder(s,request,NOW+1)
    expect(s.orders).toHaveLength(1)
    expect(()=>placeOrder(s,{...request,quantity:6},NOW)).toThrow('farklı')
    tick(s);placeOrder(s,request,NOW+2000);expect(s.positions[0].quantity).toBe(5)
  })
  test('partial fills use available size, adverse slippage and cumulative fees exactly',()=>{
    const s=account();s.settings.slippageBps=10
    const request=order();placeOrder(s,request,NOW);tick(s,NOW+1000,{askSize:2})
    expect(s.wallets[1].cashCents).toBe(979_959)
    expect(s.orders[0].filledQty).toBe(2);expect(s.orders[0].feesCents).toBe(21)
    processOrders(s,NOW+1500);expect(s.orders[0].filledQty).toBe(2)
    tick(s,NOW+2000,{askSize:3})
    expect(s.wallets[1].cashCents).toBe(949_899)
    expect(s.orders[0].feesCents).toBe(51);expect(s.positions[0].costCents).toBe(50_101)
    expect(s.orders[0].fills).toHaveLength(2)
    s.settings.slippageBps=0
    acceptQuote(s,quote('AAPL',NOW+3000,{priceUnits:1_100_000,bidUnits:1_100_000,askUnits:1_100_000}),NOW+3000)
    placeOrder(s,order({side:'sell',limitUnits:1_090_000}),NOW+3000)
    tick(s,NOW+4000,{priceUnits:1_100_000,bidUnits:1_100_000,askUnits:1_100_000})
    expect(s.positions).toHaveLength(0);expect(s.wallets[1].realizedCents).toBe(4_844)
    expect(s.wallets[1].feesCents).toBe(106)
    expect(snapshot(s,NOW+4000).wallets[1].netProfitCents).toBe(4_844)
  })
  test('same quote liquidity is shared across concurrent orders',()=>{
    const s=account();placeOrder(s,order({quantity:2}),NOW);placeOrder(s,order({quantity:2}),NOW)
    tick(s,NOW+1000,{askSize:3});expect(s.positions[0].quantity).toBe(3)
    processOrders(s,NOW+2000);expect(s.positions[0].quantity).toBe(3)
  })
  test('limit excludes adverse fills and empty size',()=>{
    const s=account();placeOrder(s,order({limitUnits:1_000_000}),NOW)
    tick(s);expect(s.positions).toHaveLength(0)
    s.settings.slippageBps=0;tick(s,NOW+2000,{askSize:0});expect(s.positions).toHaveLength(0)
    tick(s,NOW+3000);expect(s.positions[0].quantity).toBe(5)
  })
  test('cancellation and timeout release reserved cash without crediting cash',()=>{
    const s=account(),o=placeOrder(s,order(),NOW)
    expect(reservedCash(s,'USD')).toBe(51_051)
    cancelOrder(s,o.id);cancelOrder(s,o.id);expect(reservedCash(s,'USD')).toBe(0)
    const pending=placeOrder(s,order(),NOW);processOrders(s,NOW+900_000)
    expect(pending.status).toBe('expired');expect(s.wallets[1].cashCents).toBe(1_000_000)
  })
  test('sell quantities are reserved; shorts are impossible',()=>{
    const s=account();expect(()=>placeOrder(s,order({side:'sell'}),NOW)).toThrow('adet')
    placeOrder(s,order(),NOW);tick(s)
    placeOrder(s,order({side:'sell',quantity:3}),NOW+1000);expect(availableShares(s,'AAPL')).toBe(2)
    expect(()=>placeOrder(s,order({side:'sell',quantity:3}),NOW+1000)).toThrow('adet')
  })
  test('pending orders count toward position and sector caps',()=>{
    const s=account();placeOrder(s,order(),NOW)
    expect(()=>placeOrder(s,order(),NOW)).toThrow('pozisyon')
    s.settings.maxPositionPercent=30;s.settings.maxSectorPercent=30
    acceptQuote(s,quote('MSFT'),NOW);acceptQuote(s,quote('NVDA'),NOW)
    placeOrder(s,order({symbol:'MSFT',quantity:20}),NOW)
    expect(()=>placeOrder(s,order({symbol:'NVDA',quantity:5}),NOW)).toThrow('Sektör')
  })
  test('daily loss stops buys but permits reducing a position',()=>{
    const s=account();s.settings.maxPositionPercent=50;s.settings.maxSectorPercent=50
    placeOrder(s,order({quantity:40}),NOW);tick(s)
    tick(s,NOW+2000,{priceUnits:800_000,bidUnits:800_000,askUnits:800_000})
    expect(()=>placeOrder(s,order({quantity:1,limitUnits:810_000}),NOW+2000)).toThrow('kayıp')
    expect(()=>placeOrder(s,order({side:'sell',quantity:1,limitUnits:790_000}),NOW+2000)).not.toThrow()
  })
  test('new day baseline resets once; mode changes do not reset it',()=>{
    const s=account();updateBaselines(s,NOW);const baseline=s.baselines.USD.start
    s.wallets[1].cashCents-=100;changeSettings(s,{mode:'auto'});updateBaselines(s,NOW+1000)
    expect(s.baselines.USD.start).toBe(baseline)
    updateBaselines(s,NOW+86400000);expect(s.baselines.USD.start).toBe(baseline-100)
  })
  test('missing held price suppresses performance and new buys',()=>{
    const s=account();placeOrder(s,order(),NOW);tick(s)
    expect(snapshot(s,NOW+60000).wallets[1].netProfitCents).toBeNull()
    acceptQuote(s,quote('MSFT',NOW+60000),NOW+60000)
    expect(()=>placeOrder(s,order({symbol:'MSFT'}),NOW+60000)).toThrow('güncel fiyatı')
  })
  test('massaging settings cannot change costs of an outstanding order',()=>{
    const s=account();placeOrder(s,order(),NOW)
    expect(()=>changeSettings(s,{commissionBps:20})).toThrow('bekleyen')
    expect(()=>changeSettings(s,{maxPositionPercent:51})).toThrow()
    expect(()=>changeSettings(s,{maxSectorPercent:5})).toThrow()
  })
  test('daily order cap and automatic cooldown are enforced',()=>{
    const s=account();s.settings.maxDailyOrders=1;placeOrder(s,order({quantity:1}),NOW)
    expect(()=>placeOrder(s,order({quantity:1}),NOW)).toThrow('Günlük emir')
    s.settings.maxDailyOrders=10
    expect(()=>placeOrder(s,order({quantity:1}),NOW,{decisionId:'review'})).toThrow('bekleme')
  })
  test('older quotes cannot overwrite current prices',()=>{
    const s=account();acceptQuote(s,quote('AAPL',NOW-1000,{priceUnits:999999}),NOW)
    expect(freshQuote(s,'AAPL',NOW).priceUnits).toBe(1_000_000)
  })
  test('pending orders stop when the source or data package changes',()=>{
    const s=account();placeOrder(s,order(),NOW)
    tick(s,NOW+1000,{source:'Different test feed'})
    expect(s.orders[0].status).toBe('cancelled');expect(s.orders[0].reason).toContain('kaynağı değişti')
    expect(s.positions).toHaveLength(0);expect(reservedCash(s,'USD')).toBe(0)
  })
  test('mixed partial buys and sells conserve cash and cost basis over repeated cycles',()=>{
    const s=account();s.settings.maxDailyOrders=100
    let now=NOW
    for(let cycle=0;cycle<30;cycle++){
      const quantity=cycle%3+1
      placeOrder(s,order({quantity,limitUnits:1_040_000}),now)
      for(let part=0;part<quantity;part++){now+=1000;tick(s,now,{askSize:1,priceUnits:1_000_001+cycle,bidUnits:1_000_001+cycle,askUnits:1_000_001+cycle})}
      placeOrder(s,order({side:'sell',quantity,limitUnits:960_000}),now)
      for(let part=0;part<quantity;part++){now+=1000;tick(s,now,{bidSize:1,priceUnits:1_010_011+cycle,bidUnits:1_010_011+cycle,askUnits:1_010_011+cycle})}
      expect(s.positions).toHaveLength(0)
      expect(s.wallets[1].cashCents).toBe(s.wallets[1].initialCashCents+s.wallets[1].realizedCents)
    }
    expect(s.orders.every(o=>o.status==='filled')).toBe(true)
    expect(s.orders).toHaveLength(60)
  })
})
