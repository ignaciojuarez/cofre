// Drive CofreTXM.js against a scripted debugserver: it detaches after the code region only when Air asks.
const assert = require('node:assert/strict');
const {hexLE} = require('../../extensions/PacketTunnel/CofreTXM.js');
const F00D = 'a0013ed4', BRK69 = '200d20d4';
function stopAt(pc, x0, x16) {
    return `T05thread:1;00:${hexLE(x0)};01:${hexLE(0)};10:${hexLE(x16)};20:${hexLE(pc)};`;
}
function run(policy) {
    // Air's order: send extension (2), set detach policy (3), then brk #0x69 for a 64 MB region.
    const stops = [stopAt(0x1000, 0, 2), stopAt(0x2000, policy, 3), stopAt(0x3000, 0x4000000, 0), 'W00'];
    const code = {'1000': F00D, '2000': F00D, '3000': BRK69};
    const sent = [], logs = [];
    global.get_pid = () => 42;
    global.log = (m) => logs.push(m);
    global.prepare_memory_region = () => true;
    global.send_command = (c) => {
        sent.push(c);
        if (c.startsWith('vAttach')) return 'T11thread:1;';
        if (c === 'c') return stops.shift();
        if (c.startsWith('m')) return code[c.slice(1).split(',')[0]];
        if (c.startsWith('_M')) return '15c110000';
        return 'OK';
    };
    delete require.cache[require.resolve('../../extensions/PacketTunnel/CofreTXM.js')];
    require('../../extensions/PacketTunnel/CofreTXM.js');
    return {sent, logs};
}
let r = run(1);
assert.equal(r.sent.at(-1), 'D');
assert(r.sent.includes(`P20=${hexLE(0x3004)};thread:1;`), 'resumes past the brk before detaching');
assert(r.logs.includes('COFRE_DETACHED'));
r = run(0);
assert(!r.sent.includes('D'), 'always-attached mode stays attached');
assert(r.logs.includes('COFRE_EXITED'));
console.log('TXM detach tests passed');
