const assert = require('node:assert/strict');
const {le,hexLE,parseStop,checkedRange} = require('../../extensions/PacketTunnel/CofreTXM.js');
const stop = 'T05thread:abc;00:0010000000000000;01:0040000000000000;10:0100000000000000;20:0010000001000000;';
assert.equal(le(hexLE(0xfedcba9876543210n)), 0xfedcba9876543210n);
assert.equal(parseStop(stop,'a0013ed4').op,1n); // brk f00d
assert.equal(parseStop(stop,'200d20d4').legacy,true);
assert.equal(parseStop(stop,'1f2003d5'),null);
assert.equal(parseStop(stop.replace('T05','T0b'),'a0013ed4'),null);
assert.throws(()=>parseStop(stop.replace('thread:abc;',''),'a0013ed4'));
assert.throws(()=>le('bad'));
assert.throws(()=>checkedRange(0xffffffffffffffffn, 2n, 4096n)); // wrap
assert.throws(()=>checkedRange(0xfffffffffffffff0n, 32n, 4096n)); // overflow
assert.throws(()=>checkedRange(0n, 0n, 4096n)); // zero size
assert.deepEqual(checkedRange(0x100n, 4n, 4096n), {address: 0x100n, size: 4n});
console.log('TXM parsing tests passed');
