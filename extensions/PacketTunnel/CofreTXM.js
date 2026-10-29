// Cofre's debugger protocol implementation. No StikDebug source is incorporated.
// Air requests: f00d/x16=0 detach, 1 region, 2 extension, 3 detach policy,
// 4 patch. brk #0x69 is Air's script probe until Air sends its extension (2), answered with 0x690000E0
// like the universal script; after that it allocates x0 bytes. Keep attached until process exit.
function le(hex) {
    if (!/^[0-9a-f]{16}$/i.test(hex)) throw Error('Invalid register');
    return BigInt('0x' + hex.match(/../g).reverse().join(''));
}
function hexLE(value) {
    return BigInt(value).toString(16).padStart(16, '0').match(/../g).reverse().join('');
}
const MAX_ADDRESS = 0xffffffffffffffffn;
const PROBE_REPLY = 0x690000e0n;
function checkedRange(address, size, cap) {
    if (typeof address !== 'bigint' || typeof size !== 'bigint' || address < 0n || address > MAX_ADDRESS ||
        size <= 0n || size > cap || address + size > MAX_ADDRESS + 1n)
        throw Error('Invalid memory range');
    return {address, size};
}
function parseStop(stop, instruction) {
    if (!/^T05/.test(stop)) return null;
    let fields = {};
    stop.substring(3).split(';').forEach(function(f) {
        let i = f.indexOf(':'); if (i > 0) fields[f.substring(0,i)] = f.substring(i+1);
    });
    if (!/^[0-9a-f]+$/i.test(fields.thread || '')) throw Error('Missing thread');
    let regs = ['00','01','10','20'].map(function(r) { return le(fields[r] || ''); });
    if (!/^[0-9a-f]{8}$/i.test(instruction)) throw Error('Invalid instruction');
    let word = parseInt(instruction.match(/../g).reverse().join(''), 16);
    if (((word & 0xffe0001f) >>> 0) !== 0xd4200000) return null;
    let immediate = (word >>> 5) & 65535;
    if (immediate !== 0xf00d && immediate !== 0x69) return null;
    return {tid:fields.thread, x0:regs[0], x1:regs[1], op:immediate === 0x69 ? 1n : regs[2],
        pc:regs[3], legacy:immediate === 0x69};
}
function checked(command) {
    let reply = send_command(command);
    if (!reply || /^E[0-9a-f]+$/i.test(reply)) throw Error('debugserver rejected ' + command.split(':')[0]);
    return reply;
}
function writeRegister(r, value, tid) {
    if (checked('P' + r + '=' + hexLE(value) + ';thread:' + tid + ';') !== 'OK') throw Error('Register write failed');
}
function runCofre() {
    let stop = checked('vAttach;' + get_pid().toString(16));
    if (!/^T/.test(stop)) throw Error('Attach failed');
    log('COFRE_ATTACHED');
    stop = checked('c');
    let extended = false;
    while (!/^[WX]/.test(stop)) {
        let pc = /(?:^|;)20:([0-9a-f]{16});/i.exec(stop);
        let request = pc ? parseStop(stop, checked('m' + checkedRange(le(pc[1]), 4n, 4n).address.toString(16) + ',4')) : null;
        if (!request) {
            // Deliver unrelated signals rather than swallowing crashes or looping on them.
            let signal = /^T([0-9a-f]{2})/i.exec(stop);
            if (!signal) throw Error('Unexpected stop reply');
            stop = checked('C' + signal[1]);
            continue;
        }
        let address = request.legacy ? 0n : request.x0;
        let size = request.legacy ? request.x0 : request.x1;
        if (request.legacy && !extended) {
            // Anything but this value makes Air abort with "Support for legacy script has been removed".
            writeRegister('0', PROBE_REPLY, request.tid);
        } else if (request.op === 1n) {
            checkedRange(address, size, 1073741824n);
            if (address === 0n) {
                let allocated = checked('_M' + size.toString(16) + ',rx');
                if (!/^[0-9a-f]+$/i.test(allocated)) throw Error('Allocation failed');
                address = BigInt('0x' + allocated);
            }
            checkedRange(address, size, 1073741824n);
            // Bounded memory: one page write at a time, no region-sized JS buffers.
            for (let offset = 0n; offset < size; offset += 16384n) {
                let count = size - offset > 1n ? 1n : size - offset;
                let range = checkedRange(address + offset, count, 1n);
                if (checked('M' + range.address.toString(16) + ',1:69') !== 'OK') throw Error('Region write failed');
            }
            writeRegister('0', address, request.tid);
            log('COFRE_REGION_READY');
        } else if (request.op === 4n) {
            checkedRange(address, size, 1048576n);
            for (let offset = 0n; offset < size; offset += 4096n) {
                let count = size - offset > 4096n ? 4096n : size - offset;
                let bounded = checkedRange(address + offset, count, 4096n);
                let range = bounded.address.toString(16) + ',' + bounded.size.toString(16);
                let bytes = checked('m' + range);
                if (bytes.length !== Number(count) * 2 || !/^[0-9a-f]+$/i.test(bytes)) throw Error('Invalid memory reply');
                if (checked('M' + range + ':' + bytes) !== 'OK') throw Error('Patch write failed');
            }
        } else if (request.op === 2n) {
            extended = true;
        } else if (![0n, 3n].includes(request.op)) {
            throw Error('Unsupported JIT request');
        }
        // Air's known extension operations are implemented above; never eval target memory.
        // Detach requests/policy are deliberately ignored: S3 is not yet proven on TXM.
        writeRegister('20', request.pc + 4n, request.tid);
        stop = checked('c');
    }
    log('COFRE_EXITED');
}
if (typeof get_pid === 'function') runCofre();
if (typeof module !== 'undefined') module.exports = {le, hexLE, parseStop, checkedRange, PROBE_REPLY};
