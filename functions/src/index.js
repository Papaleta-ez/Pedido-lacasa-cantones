'use strict';
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {randomBytes, scryptSync, timingSafeEqual} = require('node:crypto');
const {integer, amount, totals, consumption, allocate} = require('./domain');
initializeApp();
const db = getFirestore();
const now = () => FieldValue.serverTimestamp();
const ref = (c, id) => db.collection(c).doc(id);
const fail = (s) => { throw new HttpsError('failed-precondition', s); };
function id(value) { if (typeof value !== 'string' || !/^[\w-]{1,128}$/.test(value)) fail('Identificador inválido'); return value; }
function text(value, max = 300) { if (typeof value !== 'string' || value.length > max) fail('Texto inválido'); return value.trim(); }
function callable(fn) { return onCall({region: 'us-central1', maxInstances: 10}, async r => {
 if (!r.auth) throw new HttpsError('unauthenticated', 'Iniciá sesión');
 try { return await fn(r, r.data || {}); } catch (e) { if (e instanceof HttpsError) throw e; throw new HttpsError('failed-precondition', e.message); }
}); }
async function role(r, allowed, tx) {
 if (r.auth.token.owner === true) return;
 const doc = tx ? await tx.get(ref('devices', r.auth.uid)) : await ref('devices', r.auth.uid).get();
 if (!doc.exists || !doc.data().active || !allowed.includes(doc.data().role)) throw new HttpsError('permission-denied', 'Dispositivo no autorizado para esta operación');
}
function owner(r) { if (r.auth.token.owner !== true) throw new HttpsError('permission-denied', 'Solo el dueño'); }
async function pin(r, value) {
 if (!/^\d{4}$/.test(value || '')) fail('PIN de cuatro dígitos requerido');
 // Lockouts are committed independently so failed protected operations cannot undo them.
 const accepted = await db.runTransaction(async tx => {
  const secret = await tx.get(ref('private', 'pin'));
  const attempts = await tx.get(ref('pinAttempts', r.auth.uid));
  const a = attempts.data() || {};
  if (a.until && a.until.toMillis() > Date.now()) fail('PIN bloqueado temporalmente. Esperá 15 minutos');
  const s = secret.data(); if (!s) fail('El dueño debe configurar el PIN');
  const hash = scryptSync(value, s.salt, 32);
  const ok = timingSafeEqual(hash, Buffer.from(s.hash, 'hex'));
  const count = ok ? 0 : (a.count || 0) + 1;
  tx.set(ref('pinAttempts', r.auth.uid), {count, until: count >= 5 ? Timestamp.fromMillis(Date.now() + 900000) : null});
  return ok;
 });
 if (!accepted) throw new HttpsError('permission-denied', 'PIN incorrecto');
}
function audit(tx, r, action, data) { tx.set(db.collection('audit').doc(), {uid: r.auth.uid, action, ...data, at: now()}); }
exports.registerDevice = callable(async (r, d) => {
 if (!['mesero', 'cocina'].includes(d.mode)) fail('Modo inválido');
 await db.runTransaction(async tx => {
  const device = ref('devices', r.auth.uid); const snap = await tx.get(device);
  if (!snap.exists) tx.set(device, {name: text(d.name || 'Dispositivo'), requestedRole: d.mode, role: '', active: false, createdAt: now()});
 }); return {uid: r.auth.uid};
});
exports.authorizeDevice = callable(async (r, d) => {
 owner(r); id(d.uid); if (!['mesero','cocina'].includes(d.role)) fail('Rol inválido');
 await ref('devices', d.uid).update({role: d.role, active: d.active === true}); return {ok: true};
});
exports.setPin = callable(async (r, d) => {
 owner(r); if (!/^\d{4}$/.test(d.pin || '')) fail('PIN debe tener cuatro dígitos');
 const salt = randomBytes(16).toString('hex');
 await ref('private', 'pin').set({salt, hash: scryptSync(d.pin, salt, 32).toString('hex')}); return {ok:true};
});
exports.saveCatalog = callable(async (r, d) => {
 owner(r); const type = d.type;
 if (!['products','inventory','zones','tables','settings'].includes(type)) fail('Tipo inválido');
 const key = id(d.id); const v = d.value || {}; let value;
 if (type === 'inventory') {
  value = {name:text(v.name), unit:text(v.unit || 'unidad',30), stock:amount(v.stock,'stock'), low:amount(v.low,'mínimo')};
 } else if (type === 'products') {
  const recipe = v.recipe || []; if (!Array.isArray(recipe) || recipe.length > 30) fail('Receta inválida');
  value = {name:text(v.name), description:text(v.description || '',800), category:text(v.category), priceCents:integer(v.priceCents,'precio'), active:v.active === true, esComida:v.esComida === true,
   inventoryId:v.inventoryId ? id(v.inventoryId) : '', recipe:recipe.map(x => ({inventoryId:id(x.inventoryId), qty:amount(x.qty,'receta',0.000001)}))};
  if (!value.recipe.length && !value.inventoryId) fail('Asigná stock o receta');
 } else if (type === 'zones') {
  value = {name:text(v.name), width:amount(v.width,'ancho',1), height:amount(v.height,'largo',1)};
 } else if (type === 'tables') {
  value = {name:text(v.name), zoneId:id(v.zoneId), x:amount(v.x,'x'), y:amount(v.y,'y'), side:amount(v.side,'lado',0.5)};
 } else {
  if (key !== 'business') fail('Configuración inválida');
  value = {name:text(v.name), ruc:text(v.ruc), address:text(v.address), phone:text(v.phone), currency:text(v.currency || 'C$',10), vatBps:integer(v.vatBps,'IVA',0,10000), packagingId:v.packagingId ? id(v.packagingId) : ''};
 }
 if (!value.name) fail('Nombre requerido');
 let reductionAuthorized=false;
 if(type==='inventory') {const stock=(await ref(type,key).get()).data()?.stock;if(stock!==undefined && value.stock<stock){await pin(r,v.pin);reductionAuthorized=true;}}
 await db.runTransaction(async tx => {
  const current = await tx.get(ref(type,key));
  if(type==='settings' && !current.exists)fail('Inicializá el negocio y menú primero desde Gestión');
  if (type === 'inventory') {
   if (current.exists && (v.version || 0) !== (current.data().version || 0)) fail('El stock cambió mientras editabas. Volvé a abrir el insumo');
   if(current.exists && value.stock<current.data().stock && !reductionAuthorized)fail('Reducir stock requiere PIN');
   value.version = (current.data()?.version || 0) + 1;
  }
  if (type === 'tables') {
   const zone = await tx.get(ref('zones',value.zoneId)); if (!zone.exists) fail('Zona inexistente');
   const z = zone.data(); if (value.x+value.side > z.width || value.y+value.side > z.height) fail('Mesa fuera de zona');
   const tables = await tx.get(db.collection('tables').where('zoneId','==',value.zoneId));
   if (tables.docs.some(t => t.id!==key && value.x<t.data().x+t.data().side && value.x+value.side>t.data().x && value.y<t.data().y+t.data().side && value.y+value.side>t.data().y)) fail('Las mesas se superponen');
   if (current.data()?.orderId && current.data().zoneId !== value.zoneId) fail('No mover de zona una mesa ocupada');
  }
  if (type === 'zones') {
   const tables = await tx.get(db.collection('tables').where('zoneId','==',key));
   if (tables.docs.some(t=>t.data().x+t.data().side>value.width || t.data().y+t.data().side>value.height)) fail('Hay mesas fuera de las nuevas medidas');
  }
  if (type === 'products') {
   const ids = new Set(value.recipe.length ? value.recipe.map(x=>x.inventoryId) : [value.inventoryId]);
   for (const k of ids) if (!(await tx.get(ref('inventory',k))).exists) fail(`Insumo inexistente: ${k}`);
  }
  tx.set(ref(type,key), {...value,updatedAt:now()}, {merge:true}); audit(tx,r,'catalog',{type,id:key});
 }); return {ok:true};
});
exports.submitOrder = callable(async (r, d) => {
 id(d.requestId); if (!['mesa','llevar','delivery'].includes(d.kind)) fail('Tipo inválido');
 if (!Array.isArray(d.lines) || !d.lines.length || d.lines.length > 100) fail('Comanda inválida');
 const lines = d.lines.map(l => ({productId:id(l.productId),qty:integer(l.qty,'cantidad',1,99),note:text(l.note || '',500)}));
 const orderId = `${r.auth.uid}_${d.requestId}`;
 return db.runTransaction(async tx => {
  await role(r,['mesero'],tx);
  const existing = await tx.get(ref('orders',orderId)); if (existing.exists) return {id:orderId,number:existing.data().number};
  if ((await tx.get(ref('abandoned',orderId))).exists) fail('Solicitud descartada. Creá una nueva comanda');
  const settings = (await tx.get(ref('settings','business'))).data(); if (!settings) fail('Configurá el negocio');
  const shift = (await tx.get(ref('shifts','current'))).data(); if (!shift) fail('Inicializá la caja');
  const products = new Map();
  for (const k of new Set(lines.map(l=>l.productId))) { const s = await tx.get(ref('products',k)); products.set(k,s.data()); }
  const consumed = consumption(products,lines,d.kind,settings.packagingId);
  const stock = new Map();
  for (const k of Object.keys(consumed)) {
   const s = await tx.get(ref('inventory',k)); if (!s.exists || s.data().stock + 1e-9 < consumed[k]) fail(`Stock insuficiente: ${s.data()?.name || k}`);
   stock.set(k,s.data().stock);
  }
  const tableIds = d.kind === 'mesa' ? [...new Set((d.tableIds || []).map(id))] : [];
  if (d.kind === 'mesa' && !tableIds.length) fail('Elegí una mesa');
  if (tableIds.length > 30) fail('Demasiadas mesas');
  const tables = [];
  for (const k of tableIds) { const s = await tx.get(ref('tables',k)); if (!s.exists || s.data().orderId) fail('Mesa ocupada'); tables.push(s.data().name); }
  const customer = text(d.customer || ''); if (d.kind !== 'mesa' && !customer) fail('Nombre del cliente requerido');
  const counter = ref('counters','orders'); const n = ((await tx.get(counter)).data()?.last || 0) + 1;
  const number = `CC-${String(n).padStart(6,'0')}`;
  const orderLines = lines.map((l,i) => ({...l,lineId:String(i),name:products.get(l.productId).name,priceCents:products.get(l.productId).priceCents,esComida:products.get(l.productId).esComida,remaining:l.qty}));
  tx.set(counter,{last:n});
  for (const [k,qty] of Object.entries(consumed)) tx.update(ref('inventory',k),{stock:Math.max(0,stock.get(k)-qty),version:FieldValue.increment(1),updatedAt:now()});
  const kitchenLines = orderLines.filter(l=>l.esComida);
  tx.set(ref('orders',orderId),{number,kind:d.kind,customer,tableIds,tableNames:tables,lines:orderLines,consumed,note:text(d.note || '',500),status:'open',kitchenStatus:kitchenLines.length?'pendiente':'listo',kitchenBatches:kitchenLines.length?{[orderId]:'pendiente'}:{},uid:r.auth.uid,shiftId:shift.id,createdAt:now()});
  if (kitchenLines.length) tx.set(ref('kitchen',orderId),{orderId,number,label:tables.join(' + ') || customer,lines:kitchenLines,note:text(d.note || '',500),status:'pendiente',createdAt:now()});
  for (const k of tableIds) tx.update(ref('tables',k),{orderId,status:kitchenLines.length?'active':'pending'});
  audit(tx,r,'submit',{orderId}); return {id:orderId,number};
 });
});
exports.kitchenStatus = callable(async (r,d) => {
 id(d.orderId); if (!['preparando','listo'].includes(d.status)) fail('Estado inválido');
 return db.runTransaction(async tx => {
  await role(r,['cocina'],tx);
  const k = await tx.get(ref('kitchen',d.orderId)); if (!k.exists) fail('Comanda inexistente');
  const o = await tx.get(ref('orders',k.data().orderId || d.orderId));
  if (!o.exists || o.data().status==='cancelled') fail('Pedido cancelado');
  if (k.data().status === d.status) return {ok:true};
  if (!['pendiente','preparando'].includes(k.data().status) || (k.data().status==='pendiente' && d.status!=='preparando')) fail('Cambio de estado inválido');
  const batches={...o.data().kitchenBatches,[d.orderId]:d.status};const values=Object.values(batches);const aggregate=values.every(s=>s==='listo')?'listo':values.some(s=>s==='pendiente')?'pendiente':'preparando';
  tx.update(k.ref,{status:d.status,updatedAt:now()}); tx.update(o.ref,{kitchenStatus:aggregate,kitchenBatches:batches});
  if(o.data().status==='open') for (const key of o.data().tableIds) tx.update(ref('tables',key),{status:aggregate==='listo'?'pending':'active'});
  return {ok:true};
 });
});
exports.joinTables = callable(async (r,d) => {
 id(d.orderId); const ids = [...new Set((d.tableIds || []).map(id))]; if (!ids.length || ids.length>30) fail('Mesas inválidas');
 return db.runTransaction(async tx => {
  await role(r,['mesero'],tx); const s=await tx.get(ref('orders',d.orderId)); if (!s.exists || s.data().status!=='open' || s.data().kind!=='mesa') fail('Pedido inválido');
  const names=[...s.data().tableNames], keys=[...s.data().tableIds];
  for (const key of ids) {const t=await tx.get(ref('tables',key)); if (!t.exists || t.data().orderId) fail('Mesa ocupada'); keys.push(key); names.push(t.data().name);}
  tx.update(s.ref,{tableIds:keys,tableNames:names}); for (const key of ids) tx.update(ref('tables',key),{orderId:d.orderId,status:s.data().kitchenStatus==='listo'?'pending':'active'});
  for(const batch of Object.keys(s.data().kitchenBatches || {}))tx.update(ref('kitchen',batch),{label:names.join(' + ')}); return {ok:true};
 });
});
exports.payOrder = callable(async (r,d) => {
 id(d.orderId); id(d.requestId); integer(d.discountCents || 0,'descuento');
 await role(r,['mesero']); if (d.discountCents) await pin(r,d.pin);
 if (!['efectivo','tarjeta','transferencia'].includes(d.method)) fail('Método inválido');
 const invoiceId = `${r.auth.uid}_${d.requestId}`;
 return db.runTransaction(async tx => {
  await role(r,['mesero'],tx);
  const old=await tx.get(ref('invoices',invoiceId)); if (old.exists) return {id:invoiceId,...old.data()};
  if((await tx.get(ref('abandonedPayments',invoiceId))).exists)fail('Solicitud de pago descartada');
  const snap=await tx.get(ref('orders',d.orderId)); if (!snap.exists || snap.data().status!=='open') fail('Pedido ya cerrado');
  const order=snap.data();
  const business=(await tx.get(ref('settings','business'))).data();
  const shiftSnap=await tx.get(ref('shifts','current')); const shift=shiftSnap.data();
  if (!shift || order.shiftId!==shift.id) fail('Caja inválida');
  const selections=d.selections || order.lines.filter(l=>l.remaining>0).map(l=>({lineId:l.lineId,qty:l.remaining}));
  if (!Array.isArray(selections) || !selections.length || selections.length>100) fail('Selección inválida');
  const chosen=new Map(); for (const l of selections) {if (chosen.has(l.lineId)) fail('Línea duplicada');chosen.set(l.lineId,integer(l.qty,'cantidad',1,99));}
  const bill=[]; const remaining=order.lines.map(l=>{
   const qty=chosen.get(l.lineId)||0; if(qty>l.remaining) fail('Artículos ya cobrados');
   if(qty) {bill.push({...l,qty});chosen.delete(l.lineId);} return {...l,remaining:l.remaining-qty};
  }); if(chosen.size || !bill.length) fail('Artículo inexistente');
  const calculation=totals(bill,business.vatBps,d.tip===true,d.discountCents||0);
  const received=d.method==='efectivo'?integer(d.receivedCents,'recibido'):calculation.totalCents;
  if(received<calculation.totalCents) fail('Efectivo insuficiente');
  const counter=ref('counters','invoices'); const n=((await tx.get(counter)).data()?.last||0)+1;
  const invoice={number:`F-${String(n).padStart(8,'0')}`,orderId:d.orderId,orderNumber:order.number,customer:order.customer,tableNames:order.tableNames,lines:bill,...calculation,method:d.method,receivedCents:received,changeCents:received-calculation.totalCents,business,shiftId:shift.id,uid:r.auth.uid,createdAt:now(),shares:allocate(calculation.totalCents,d.people||1)};
  tx.set(counter,{last:n});tx.set(ref('invoices',invoiceId),invoice);
  tx.update(shiftSnap.ref,{salesCents:(shift.salesCents||0)+calculation.totalCents,cashCents:(shift.cashCents||0)+(d.method==='efectivo'?calculation.totalCents:0)});
  const paid=remaining.every(l=>l.remaining===0); tx.update(snap.ref,{lines:remaining,status:paid?'paid':'open'});
  if(paid) for(const key of order.tableIds) tx.update(ref('tables',key),{orderId:null,status:'free'});
  audit(tx,r,'payment',{invoiceId,orderId:d.orderId});return {id:invoiceId,...invoice,createdAt:null};
 });
});
exports.cancelOrder = callable(async(r,d)=>{
 await role(r,['mesero']);await pin(r,d.pin);id(d.orderId);
 return db.runTransaction(async tx=>{
  await role(r,['mesero'],tx);const snap=await tx.get(ref('orders',d.orderId));if(!snap.exists) fail('Pedido inexistente');const o=snap.data();
  if(o.status==='cancelled') return {ok:true};if(o.status!=='open' || o.lines.some(l=>l.remaining!==l.qty)) fail('No cancelar un pedido cobrado total o parcialmente');
  // Once food preparation starts, cancelling records waste rather than returning consumed ingredients.
  const restore=d.restore===true; if(restore && Object.values(o.kitchenBatches || {}).some(s=>s!=='pendiente')) fail('No devolver ingredientes después de iniciar preparación');
  const stocks={};if(restore) for(const key of Object.keys(o.consumed)) stocks[key]=(await tx.get(ref('inventory',key))).data().stock;
  if(restore) for(const [key,qty] of Object.entries(o.consumed)) tx.update(ref('inventory',key),{stock:stocks[key]+qty,version:FieldValue.increment(1)});
  tx.update(snap.ref,{status:'cancelled',cancelledAt:now(),reason:text(d.reason||'Cancelación'),stockRestored:restore});for(const batch of Object.keys(o.kitchenBatches || {}))tx.delete(ref('kitchen',batch));
  for(const key of o.tableIds) tx.update(ref('tables',key),{orderId:null,status:'free'});audit(tx,r,'cancel',{orderId:d.orderId,restore});return {ok:true};
 });
});
exports.recordWaste = callable(async(r,d)=>{
 owner(r);await pin(r,d.pin);id(d.requestId);id(d.inventoryId);const qty=amount(d.qty,'merma',0.000001);
 return db.runTransaction(async tx=>{
  const request=ref('waste',`${r.auth.uid}_${d.requestId}`);if((await tx.get(request)).exists)return {ok:true};
  if((await tx.get(ref('abandonedOwner',request.id))).exists)fail('Solicitud descartada');
  const s=await tx.get(ref('inventory',d.inventoryId));if(!s.exists || s.data().stock<qty)fail('Stock insuficiente');
  tx.update(s.ref,{stock:s.data().stock-qty,version:FieldValue.increment(1)});tx.set(request,{inventoryId:d.inventoryId,qty,reason:text(d.reason),uid:r.auth.uid,createdAt:now()});audit(tx,r,'waste',{inventoryId:d.inventoryId,qty});return {ok:true};
 });
});
exports.closeShift = callable(async(r,d)=>{
 owner(r);id(d.requestId);if(!['X','Z'].includes(d.type))fail('Cierre inválido');integer(d.countedCents,'efectivo contado');
 return db.runTransaction(async tx=>{
  const closure=ref('closures',`${r.auth.uid}_${d.requestId}`);const old=await tx.get(closure);if(old.exists)return old.data();
  if((await tx.get(ref('abandonedOwner',closure.id))).exists)fail('Solicitud descartada');
  const s=await tx.get(ref('shifts','current'));if(!s.exists)fail('Caja inexistente');const shift=s.data();
  const open=await tx.get(db.collection('orders').where('status','==','open'));if(d.type==='Z' && !open.empty)fail('Cobrá o cancelá los pedidos abiertos antes de cerrar Z');
  const expected=(shift.openingCents||0)+(shift.cashCents||0);
  const result={...shift,type:d.type,expectedCents:expected,countedCents:d.countedCents,differenceCents:d.countedCents-expected,createdAt:now(),uid:r.auth.uid};tx.set(closure,result);
  if(d.type==='Z')tx.set(s.ref,{id:db.collection('identifiers').doc().id,openingCents:integer(d.nextOpeningCents||0,'fondo'),cashCents:0,salesCents:0,openedAt:now()});
  audit(tx,r,'close',{type:d.type,shiftId:shift.id});return {...result,createdAt:null,openedAt:null};
 });
});
exports.seedBusiness = callable(async(r)=>{
 owner(r);const seed=require('./seed.json');
 await db.runTransaction(async tx=>{
  if((await tx.get(ref('settings','business'))).exists)fail('Negocio ya inicializado. No se sobreescribe');
  for(const [collection,docs] of Object.entries(seed))for(const [key,value] of Object.entries(docs))tx.set(ref(collection,key),value);
  tx.set(ref('shifts','current'),{id:db.collection('identifiers').doc().id,openingCents:0,cashCents:0,salesCents:0,openedAt:now()});
 });return {ok:true};
});
exports.checkSubmission = callable(async(r,d)=>{
 id(d.requestId);const key=`${r.auth.uid}_${d.requestId}`;
 return db.runTransaction(async tx=>{
  await role(r,['mesero'],tx);const s=await tx.get(ref('orders',key));const addition=await tx.get(ref('orderAdditions',key));
  if(s.exists || addition.exists)return {exists:true};
  tx.set(ref('abandoned',key),{uid:r.auth.uid,at:now()});return {exists:false};
 });
});
exports.addToOrder = callable(async(r,d)=>{
 id(d.requestId);id(d.existingOrderId);if(!Array.isArray(d.lines)||!d.lines.length||d.lines.length>100)fail('Comanda inválida');
 const lines=d.lines.map(l=>({productId:id(l.productId),qty:integer(l.qty,'cantidad',1,99),note:text(l.note||'',500)}));const key=`${r.auth.uid}_${d.requestId}`;
 return db.runTransaction(async tx=>{
  await role(r,['mesero'],tx);const request=await tx.get(ref('orderAdditions',key));if(request.exists)return request.data();
  if((await tx.get(ref('abandoned',key))).exists)fail('Solicitud descartada');
  const snap=await tx.get(ref('orders',d.existingOrderId));if(!snap.exists||snap.data().status!=='open')fail('Cuenta cerrada');const order=snap.data();
  if(order.lines.length+lines.length>400)fail('Demasiados artículos en esta cuenta');
  const settings=(await tx.get(ref('settings','business'))).data();const products=new Map();
  for(const k of new Set(lines.map(l=>l.productId)))products.set(k,(await tx.get(ref('products',k))).data());
  const consumed=consumption(products,lines,order.kind,settings.packagingId);const stocks={};
  for(const [k,qty]of Object.entries(consumed)){const s=await tx.get(ref('inventory',k));if(!s.exists||s.data().stock+1e-9<qty)fail(`Stock insuficiente: ${s.data()?.name||k}`);stocks[k]=s.data().stock;}
  const newLines=lines.map((l,i)=>({...l,lineId:String(order.lines.length+i),name:products.get(l.productId).name,priceCents:products.get(l.productId).priceCents,esComida:products.get(l.productId).esComida,remaining:l.qty}));const food=newLines.filter(l=>l.esComida);
  const usage={...order.consumed};for(const[k,qty]of Object.entries(consumed))usage[k]=(usage[k]||0)+qty;
  const batches={...order.kitchenBatches,...(food.length?{[key]:'pendiente'}:{})};
  tx.update(snap.ref,{lines:[...order.lines,...newLines],consumed:usage,kitchenBatches:batches,kitchenStatus:food.length?'pendiente':order.kitchenStatus});
  for(const[k,qty]of Object.entries(consumed))tx.update(ref('inventory',k),{stock:Math.max(0,stocks[k]-qty),version:FieldValue.increment(1),updatedAt:now()});
  if(food.length){tx.set(ref('kitchen',key),{orderId:d.existingOrderId,number:order.number,label:order.tableNames.join(' + ')||order.customer,lines:food,status:'pendiente',note:text(d.note||'',500),createdAt:now()});for(const t of order.tableIds)tx.update(ref('tables',t),{status:'active'});}
  const result={id:d.existingOrderId,number:order.number};tx.set(ref('orderAdditions',key),result);audit(tx,r,'addition',{orderId:d.existingOrderId});return result;
 });
});
exports.archiveKitchen = callable(async(r,d)=>{
 id(d.ticketId);return db.runTransaction(async tx=>{
  await role(r,['cocina'],tx);const s=await tx.get(ref('kitchen',d.ticketId));if(!s.exists||!['listo','archived'].includes(s.data().status))fail('Solo retirar comandas listas');
  tx.update(s.ref,{status:'archived',archivedAt:now()});return {ok:true};
 });
});
exports.checkOwnerOperation=callable(async(r,d)=>{
 owner(r);id(d.requestId);if(!['recordWaste','closeShift'].includes(d.name))fail('Operación inválida');const key=`${r.auth.uid}_${d.requestId}`;
 return db.runTransaction(async tx=>{const s=await tx.get(ref(d.name==='recordWaste'?'waste':'closures',key));if(s.exists)return {exists:true};tx.set(ref('abandonedOwner',key),{at:now()});return {exists:false};});
});
exports.checkPayment = callable(async(r,d)=>{
 id(d.requestId);const key=`${r.auth.uid}_${d.requestId}`;
 return db.runTransaction(async tx=>{
  await role(r,['mesero'],tx);const s=await tx.get(ref('invoices',key));
  if(s.exists)return {exists:true,id:key};
  tx.set(ref('abandonedPayments',key),{uid:r.auth.uid,at:now()});return {exists:false};
 });
});
