import { instrument, freshQuote, quoteBlock, equity, availableShares, reservedCash, placeOrder, fee, hash, requireValue } from './domain.mjs'
const POSITIVE = /raises? (?:its |full.year )?(?:guidance|outlook)|raised (?:its )?(?:guidance|outlook)|record (?:revenue|profit)|k[aâ]r beklentisini (?:yükseltti|yükseltiyor)/i
const NEGATIVE = /cuts? (?:its |full.year )?(?:guidance|outlook)|lowers? (?:its )?(?:guidance|outlook)|files? for bankruptcy|earnings miss|k[aâ]r beklentisini (?:düşürdü|düşürüyor)/i
const UNCERTAIN = /rumou?r|unconfirmed|may |might |could |denies|\bnot\b|\bno\b|analysts? |analist|söylenti|iddia|yalanla|bekleniyor|beklentisi(?:\s|$)|değil|yükseltmedi|düşürmedi/i
export function addNews(state, rows, now=Date.now()) {
  for (const row of rows) {
    if (!row || typeof row!=='object' || typeof row.id!=='string' || !row.id || typeof row.title!=='string' || !row.title || typeof row.source!=='string' || !row.source || typeof row.url!=='string' || !/^https:\/\//.test(row.url) || !Number.isFinite(row.publishedAt) || row.publishedAt<=0 || row.publishedAt>now+2000) continue
    const item={...row,receivedAt:now,title:row.title.slice(0,500),summary:String(row.summary??'').slice(0,1200),symbols:(Array.isArray(row.symbols)?row.symbols:[]).filter(x=>instrument(x)),delaySeconds:Math.max(0,Math.round((now-row.publishedAt)/1000))}
    const old=state.news.find(x=>x.id===row.id || x.url===row.url)
    // A decision retains the exact text it evaluated; revisions cannot rewrite its evidence.
    if (old) continue
    state.news.unshift(item)
  }
  state.news.sort((a,b)=>b.publishedAt-a.publishedAt)
  state.news=state.news.slice(0,500)
}
export function analyze(state, news, symbol, now=Date.now()) {
  const item=instrument(symbol), held=state.positions.find(x=>x.symbol===symbol), text=news.title+' '+news.summary
  const positive=POSITIVE.test(text), negative=NEGATIVE.test(text), uncertain=UNCERTAIN.test(text)
  const quote=freshQuote(state,symbol,now,true)
  const change=quote?.previousCloseUnits>0 ? (quote.priceUnits/quote.previousCloseUnits-1)*100 : null
  const named=text.toLocaleLowerCase('tr').includes(item.name.toLocaleLowerCase('tr')) || new RegExp(`\\b${symbol}\\b`,'i').test(text)
  const direct=news.scope==='company' && news.symbols.includes(symbol) && named
  const proposedSide=direct && positive!==negative && !uncertain ? positive?'buy':'sell' : null
  const aligned=proposedSide==='buy' ? change!==null&&change>=0.3&&change<=3 : proposedSide==='sell' ? change!==null&&change<=-0.3 : false
  const recent=now-news.publishedAt<30*60_000 && now-news.receivedAt<5*60_000
  const reliable=news.sourceTier==='official' || news.sourceTier==='licensed'
  const escaped=item.name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')
  const subject=new RegExp(`^(?:${escaped}|${symbol})(?: Inc[.,]?)?[:\\s]+(?:reports? |announces? )?(?:raises? (?:its )?(?:guidance|outlook)|cuts? (?:its )?(?:guidance|outlook)|record (?:profit|revenue)|files? for bankruptcy|k[aâ]r beklentisini (?:yükseltti|yükseltiyor|düşürdü|düşürüyor))`,'i').test(news.title)
  const confidence=proposedSide && subject && aligned && recent && reliable && quote ? 'high' : 'review'
  const companyImpact=uncertain?'Haberin dili veya iddiası belirsiz; yön doğrulanamadı.':direct ? positive!==negative ? positive?'Başlık/özette olumlu beklenti sinyali var.':'Başlık/özette olumsuz beklenti sinyali var.' : 'Şirket yönü metinden güvenle çıkarılamıyor.' : 'Makro gelişmenin şirkete doğrudan etkisi doğrulanmadı.'
  const sectorImpact=`${item.sector}: ${direct?'Tek şirket haberi sektörün tamamına genellenmez.':'Faiz, talep ve maliyet etkileri birlikte incelenmeli.'}`
  const portfolioImpact=held ? `${held.quantity} adet pozisyonun var. Karar mevcut risk sınırlarına tabi.` : 'Bu şirkette pozisyonun yok.'
  let reason=!recent?'Haber güncel işlem penceresinin dışında; yalnızca bilgi.':!proposedSide?'Yön veya doğrudan şirket etkisi belirsiz; kullanıcı incelemesi gerekiyor.':!aligned?'Fiyat tepkisi haberi doğrulamıyor; inceleme gerekiyor.':quoteBlock(state,symbol,now)??'Haber yönü ve güncel fiyat tepkisi uyumlu; risk kontrolü uygulanacak.'
  const stateName=!recent||state.settings.mode==='paused'?'held':proposedSide==='sell'&&!held?'held':'review'
  if (proposedSide==='sell'&&!held) reason='Olumsuz sinyal var; satılacak pozisyon yok, işlem yapılmadı.'
  return {id:hash(news.id+'|'+symbol),newsId:news.id,symbol,action:stateName==='held'?'BEKLE':proposedSide==='buy'?'AL':proposedSide==='sell'?'SAT':'İNCELE',
    proposedSide,state:stateName,reason,companyImpact,sectorImpact,portfolioImpact,sourceURL:news.url,source:news.source,
    createdAt:now,expiresAt:Math.min(now+15*60_000,news.publishedAt+30*60_000),confidence,analysisVersion:'rules-1',orderId:null}
}
function proposal(state, decision, now, selectedSide) {
  const side=selectedSide??decision.proposedSide, item=instrument(decision.symbol), quote=freshQuote(state,decision.symbol,now,true)
  requireValue(['buy','sell'].includes(side),'Alış veya satış yönünü seç.')
  requireValue(quote,'Karar için güncel ve işlem yapılabilir fiyat bekleniyor.')
  const limitUnits=side==='buy'?Math.ceil(quote.askUnits*1.002):Math.floor(quote.bidUnits*0.998)
  const wallet=state.wallets.find(x=>x.currency===item.currency), value=equity(state,item.currency,now)
  let quantity
  if (side==='sell') quantity=availableShares(state,decision.symbol)
  else {
    requireValue(value!==null,'Portföyün güncel değeri doğrulanamıyor.')
    const held=state.positions.find(x=>x.symbol===decision.symbol)
    const capacity=value*state.settings.maxPositionPercent/100-(held?held.quantity*quote.priceUnits/100:0)
    const budget=Math.max(0,Math.min(value*0.025,capacity,wallet.cashCents-reservedCash(state,item.currency)))
    quantity=Math.floor(budget/(limitUnits/100*(1+state.settings.commissionBps/10000)))
  }
  requireValue(quantity>0,'Risk sınırları içinde işlem yapılabilecek adet yok.')
  return {id:'decision-'+decision.id,symbol:decision.symbol,side,quantity,limitUnits}
}
export function previewDecision(state, id, choice, now=Date.now()) {
  const decision=state.decisions.find(x=>x.id===id)
  requireValue(decision?.state==='review' && decision.expiresAt>now,'İnceleme kapandı veya süresi doldu.')
  requireValue(state.settings.mode!=='paused','Otomasyon duraklatıldı.')
  const request=proposal(state,decision,now,choice)
  // Validate on an isolated state without reserving or submitting anything.
  placeOrder(structuredClone(state),request,now,{decisionId:id})
  const grossCents=request.side==='buy'?Math.ceil(request.limitUnits*request.quantity/100):Math.floor(request.limitUnits*request.quantity/100)
  return {...request,currency:instrument(request.symbol).currency,feeCents:fee(grossCents,state.settings.commissionBps),grossCents,expiresAt:Math.min(now+30_000,decision.expiresAt)}
}
export function reviewDecision(state, id, choice, now=Date.now(), confirmation=null) {
  const decision=state.decisions.find(x=>x.id===id)
  requireValue(decision,'İnceleme bulunamadı.')
  if (['queued','executed'].includes(decision.state)) return decision
  requireValue(decision.state==='review','Bu inceleme zaten kapatılmış.')
  requireValue(now<decision.expiresAt,'İncelemenin süresi doldu; yeni değerlendirme bekle.')
  if (choice==='reject') { decision.state='rejected'; decision.reason='Kullanıcı işlem yapmamayı seçti.'; return decision }
  requireValue(['buy','sell'].includes(choice),'Geçersiz inceleme yanıtı.')
  requireValue(state.settings.mode!=='paused','Otomasyon duraklatıldı. Önce inceleme veya otomatik modu aç.')
  const request=proposal(state,decision,now,choice)
  if (confirmation) requireValue(confirmation.expiresAt>now && confirmation.expiresAt<=now+30_000 && ['symbol','side','quantity','limitUnits'].every(k=>confirmation[k]===request[k]) && confirmation.feeCents===fee(request.side==='buy'?Math.ceil(request.limitUnits*request.quantity/100):Math.floor(request.limitUnits*request.quantity/100),state.settings.commissionBps),'Fiyat veya masraf değişti; yeni önizlemeyi onayla.')
  const order=placeOrder(state,request,now,{decisionId:decision.id})
  decision.proposedSide=choice; decision.action=choice==='buy'?'AL':'SAT'; decision.state='queued'; decision.orderId=order.id
  decision.reason='Güncel fiyat ve risk sınırlarıyla yeniden kontrol edildi. Sonraki kotasyon bekleniyor.'
  return decision
}
export function evaluateNews(state, now=Date.now()) {
  for (const d of state.decisions) if (d.state==='review' && d.expiresAt<=now) { d.state='expired'; d.reason='Yanıt gelmedi; işlem yapılmadı.' }
  for (const news of state.news.slice(0,60)) {
    const symbols=news.symbols.length?news.symbols:state.watchlist.filter(x=>instrument(x)?.market===(news.market??'US')).slice(0,3)
    for (const symbol of symbols) {
      if (state.decisions.some(x=>x.id===hash(news.id+'|'+symbol))) continue
      const d=analyze(state,news,symbol,now)
      state.decisions.unshift(d)
      if (state.settings.mode==='auto' && d.state==='review' && d.confidence==='high') {
        try { reviewDecision(state,d.id,d.proposedSide,now) }
        catch (error) { d.reason=error.message; d.confidence='review' }
      }
    }
  }
  // Never discard active reviews. Stop ingestion before exhausting the bounded journal.
  if (state.decisions.length>2000) state.decisions=state.decisions.filter(x=>x.state==='review').concat(state.decisions.filter(x=>x.state!=='review').slice(0,2000-state.decisions.filter(x=>x.state==='review').length))
}
