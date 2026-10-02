'use strict';
function integer(value, name, min = 0, max = 1000000000) {
 if (!Number.isSafeInteger(value) || value < min || value > max) throw new Error(`${name}: entero entre ${min} y ${max}`);
 return value;
}
function amount(value, name, min = 0) {
 if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > 1e9) throw new Error(`${name}: número inválido`);
 return value;
}
function totals(lines, vatBps, tip, discount = 0) {
 integer(vatBps, 'IVA', 0, 10000); integer(discount, 'descuento');
 const subtotal = lines.reduce((s, l) => s + integer(l.priceCents, 'precio') * integer(l.qty, 'cantidad', 1, 99), 0);
 if (discount > subtotal) throw new Error('Descuento mayor al subtotal');
 const net = subtotal - discount;
 const vat = Math.round(net * vatBps / 10000);
 const gratuity = tip ? Math.round(net * 0.1) : 0;
 return {subtotalCents: subtotal, discountCents: discount, vatCents: vat, tipCents: gratuity, totalCents: net + vat + gratuity};
}
function consumption(products, lines, kind, packagingId) {
 const needed = new Map();
 const add = (id, qty) => { if (!id || !Number.isFinite(qty) || qty <= 0) throw new Error('Receta inválida'); needed.set(id, (needed.get(id) || 0) + qty); };
 for (const line of lines) {
  const p = products.get(line.productId); if (!p || !p.active || p.priceCents <= 0) throw new Error('Producto no disponible o sin precio');
  integer(line.qty, 'cantidad', 1, 99);
  if (p.recipe.length) for (const item of p.recipe) add(item.inventoryId, item.qty * line.qty);
  else add(p.inventoryId, line.qty);
 }
 if (kind !== 'mesa') {
  if (!packagingId) throw new Error('Configurá el insumo de empaque');
  add(packagingId, lines.reduce((sum, l) => sum + l.qty, 0));
 }
 return Object.fromEntries(needed);
}
function allocate(total, people) {
 integer(total, 'total'); integer(people, 'personas', 1, 50);
 return Array.from({length: people}, (_, i) => Math.floor(total / people) + (i < total % people ? 1 : 0));
}
module.exports = {integer, amount, totals, consumption, allocate};
