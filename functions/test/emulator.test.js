const {test,before,after}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
if(!process.env.FIRESTORE_EMULATOR_HOST){test('integración requiere emulador Firestore',{skip:true},()=>{});}else{
 process.env.GCLOUD_PROJECT='demo-cantones';
 const api=require('../src/index');const {getFirestore}=require('firebase-admin/firestore');const db=getFirestore();
 const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');const {doc,setDoc,getDoc}=require('firebase/firestore');let env;
 const request=(uid,data,owner=false)=>({auth:{uid,token:{owner}},data});
 before(async()=>{
  env=await initializeTestEnvironment({projectId:'demo-cantones',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});await env.clearFirestore();
  await api.seedBusiness.run(request('owner',{},true));
  await db.doc('devices/waiter').set({role:'mesero',active:true});await db.doc('devices/cook').set({role:'cocina',active:true});
  await db.doc('products/p').set({name:'Plato',category:'Pollo',priceCents:1000,active:true,esComida:true,inventoryId:'p',recipe:[]});
  await db.doc('products/drink').set({name:'Té',category:'Bebidas',priceCents:200,active:true,esComida:false,inventoryId:'drink',recipe:[]});
  await db.doc('inventory/p').set({name:'Plato',stock:10,low:1});await db.doc('inventory/drink').set({name:'Té',stock:10,low:1});
 });after(async()=>env.cleanup());
 test('reglas rechazan escrituras directas incluso del dueño y aíslan cocina',async()=>{
  const waiter=env.authenticatedContext('waiter').firestore(),cook=env.authenticatedContext('cook').firestore(),owner=env.authenticatedContext('owner',{owner:true}).firestore();
  await assertFails(setDoc(doc(waiter,'inventory/p'),{stock:999}));await assertFails(setDoc(doc(owner,'invoices/fake'),{totalCents:0}));
  await assertFails(getDoc(doc(cook,'orders/private')));await assertSucceeds(getDoc(doc(waiter,'products/p')));await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'products/p')));
 });
 test('dos envíos simultáneos con mismo ID descuentan una sola vez y filtran bebidas',async()=>{
  const r=request('waiter',{requestId:'same',kind:'mesa',tableIds:['m1'],lines:[{productId:'p',qty:2},{productId:'drink',qty:1}]});
  const [a,b]=await Promise.all([api.submitOrder.run(r),api.submitOrder.run(r)]);assert.equal(a.id,b.id);assert.equal((await db.doc('inventory/p').get()).data().stock,8);
  assert.equal((await db.doc(`kitchen/${a.id}`).get()).data().lines.length,1);
 });
 test('cobros simultáneos no duplican factura ni stock, parcial mantiene mesa',async()=>{
  const r=request('waiter',{orderId:'waiter_same',requestId:'pay1',selections:[{lineId:'0',qty:1}],method:'efectivo',receivedCents:1000,people:3});
  const [a,b]=await Promise.all([api.payOrder.run(r),api.payOrder.run(r)]);assert.equal(a.id,b.id);assert.equal((await db.doc('inventory/p').get()).data().stock,8);assert.equal((await db.doc('tables/m1').get()).data().orderId,'waiter_same');
  assert.equal((await db.doc('shifts/current').get()).data().cashCents,1000);
  await api.payOrder.run(request('waiter',{orderId:'waiter_same',requestId:'pay2',method:'tarjeta'}));assert.equal((await db.doc('tables/m1').get()).data().orderId,null);
 });
 test('stock insuficiente revierte pedido, contador y ocupación',async()=>{
  await assert.rejects(api.submitOrder.run(request('waiter',{requestId:'tooMuch',kind:'mesa',tableIds:['m2'],lines:[{productId:'p',qty:99}]})));
  assert.equal((await db.doc('orders/waiter_tooMuch').get()).exists,false);assert.equal((await db.doc('tables/m2').get()).data().orderId,null);assert.equal((await db.doc('inventory/p').get()).data().stock,8);
 });
 test('descartar solicitud bloquea un envío tardío',async()=>{
  await api.checkSubmission.run(request('waiter',{requestId:'abandoned'}));
  await assert.rejects(api.submitOrder.run(request('waiter',{requestId:'abandoned',kind:'mesa',tableIds:['m2'],lines:[{productId:'p',qty:1}]})));
 });
 test('agregar platos es idempotente y crea otra comanda, cancelar preparado no repone stock',async()=>{
  await api.setPin.run(request('owner',{pin:'1234'},true));
  const first=await api.submitOrder.run(request('waiter',{requestId:'extra',kind:'mesa',tableIds:['m3'],lines:[{productId:'p',qty:1}]}));
  const r=request('waiter',{requestId:'addition',existingOrderId:first.id,lines:[{productId:'p',qty:1}]});
  await Promise.all([api.addToOrder.run(r),api.addToOrder.run(r)]);assert.equal((await db.doc('inventory/p').get()).data().stock,6);
  assert.equal((await db.doc(`orders/${first.id}`).get()).data().lines.length,2);
  assert.equal((await db.doc('kitchen/waiter_addition').get()).data().lines.length,1);
  await api.kitchenStatus.run(request('cook',{orderId:first.id,status:'preparando'}));
  await assert.rejects(api.cancelOrder.run(request('waiter',{orderId:first.id,pin:'1234',restore:true,reason:'Prueba'})));
  await api.cancelOrder.run(request('waiter',{orderId:first.id,pin:'1234',restore:false,reason:'Prueba'}));assert.equal((await db.doc('inventory/p').get()).data().stock,6);
  assert.equal((await db.doc('kitchen/waiter_addition').get()).exists,false);
 });
 test('cierre Z repetido no abre dos turnos y stock contado detecta cambios concurrentes',async()=>{
  const r=request('owner',{requestId:'closure',type:'Z',countedCents:1000,nextOpeningCents:100},true);
  const[a,b]=await Promise.all([api.closeShift.run(r),api.closeShift.run(r)]);assert.equal(a.id,b.id);assert.equal(a.differenceCents,0);assert.equal((await db.doc('shifts/current').get()).data().openingCents,100);
  const version=(await db.doc('inventory/p').get()).data().version;
  await assert.rejects(api.saveCatalog.run(request('owner',{type:'inventory',id:'p',value:{name:'Plato',unit:'porción',stock:100,low:1,version:version-1}},true)));
  assert.equal((await db.doc('inventory/p').get()).data().stock,6);
 });
 test('PIN incorrecto no cancela ni descuenta y cinco intentos bloquean',async()=>{
  for(let i=0;i<5;i++)await assert.rejects(api.recordWaste.run(request('owner',{requestId:`bad${i}`,inventoryId:'p',qty:1,pin:'0000',reason:'Prueba'},true)));
  await assert.rejects(api.recordWaste.run(request('owner',{requestId:'good',inventoryId:'p',qty:1,pin:'1234',reason:'Prueba'},true)));assert.equal((await db.doc('inventory/p').get()).data().stock,6);
 });
 test('revocar dispositivo bloquea funciones y lecturas',async()=>{
  await db.doc('devices/waiter').update({active:false});await assert.rejects(api.payOrder.run(request('waiter',{orderId:'waiter_same',requestId:'pay3',method:'tarjeta'})));
  await assertFails(getDoc(doc(env.authenticatedContext('waiter').firestore(),'products/p')));
 });
}
