const {test}=require('node:test');const assert=require('node:assert/strict');
const {totals,consumption,allocate}=require('../src/domain');
test('IVA y propina redondean una vez sobre subtotal descontado',()=>{
 assert.deepEqual(totals([{priceCents:1050,qty:3}],1500,true,100),{subtotalCents:3150,discountCents:100,vatCents:458,tipCents:305,totalCents:3813});
});
test('recetas acumulan insumos compartidos y empaque por artículo',()=>{
 const products=new Map([['p',{active:true,priceCents:100,recipe:[{inventoryId:'arroz',qty:.2},{inventoryId:'pollo',qty:.3}]}],['q',{active:true,priceCents:100,recipe:[],inventoryId:'arroz'}]]);
 const result=consumption(products,[{productId:'p',qty:2},{productId:'q',qty:1}],'llevar','empaque');
 assert.deepEqual(result,{arroz:1.4,pollo:.6,empaque:3});
});
test('rechaza cantidades manipuladas, producto sin precio y descuentos excesivos',()=>{
 assert.throws(()=>totals([{priceCents:100,qty:-1}],0,false));
 assert.throws(()=>totals([{priceCents:100,qty:1}],0,false,101));
 assert.throws(()=>consumption(new Map([['p',{active:true,priceCents:0,recipe:[]}]]),[{productId:'p',qty:1}],'mesa'));
});
test('dividir entre personas conserva cada centavo',()=>{assert.deepEqual(allocate(1000,3),[334,333,333]);assert.equal(allocate(1001,7).reduce((a,b)=>a+b,0),1001);});
