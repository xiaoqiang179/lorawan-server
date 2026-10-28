// Run with: node test/admin_timeline_test.js
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const path = require('path');

async function test() {
    let definition;
    const app = {
        config() {}, decorator() {},
        directive(name, factory) { if (name === 'timeline') definition = factory; }
    };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../priv/admin/admin.js'), 'utf8'), {
        angular: { module: () => app }, Set, Date
    });
    const requests = [];
    const http = options => new Promise((resolve, reject) => requests.push({options, resolve, reject}));
    const timers = new Set();
    const timeout = (fn, delay) => { const timer = {fn, delay}; timers.add(timer); return timer; };
    timeout.cancel = timer => timers.delete(timer);
    let cancelled = false;
    const q = {defer: () => ({promise: new Promise(() => {}), resolve: () => { cancelled = true; }})};
    const items = new Map([['old', {id: 'old'}]]);
    let destroy;
    const scope = {$on: (event, fn) => { destroy = fn; }};
    const directive = definition[definition.length - 1](http, timeout, q, () => ({
        getIds: () => [...items.keys()], remove: id => items.delete(id),
        update: entries => entries.forEach(item => items.set(item.id, item))
    }));
    const flush = () => new Promise(resolve => setImmediate(resolve));
    const runTimer = () => { const timer = [...timers][0]; timers.delete(timer); timer.fn(); };
    directive.link(scope);
    assert.strictEqual(requests.length, 0);
    scope.events.onload({range: {start: Date.now() - 600000, end: Date.now()}});
    scope.events.rangechanged({byUser: true});
    scope.events.rangechanged({byUser: true});
    assert.strictEqual(requests.length, 1, 'range changes must not overlap requests');
    requests[0].resolve({data: {items: [{id: 'stale'}]}});
    await flush();
    assert(!items.has('stale'), 'outdated range responses must be ignored');
    assert.strictEqual([...timers][0].delay, 0);
    runTimer();
    requests[1].resolve({data: {items: [{id: 'new'}], truncated: true, total: 2000}});
    await flush();
    assert.deepStrictEqual([...items.keys()], ['new']);
    assert.strictEqual(scope.truncated, true);
    assert.strictEqual([...timers][0].delay, 5000, 'poll only after completion');
    runTimer();
    requests[2].reject(new Error('network error'));
    await flush();
    assert.strictEqual(scope.error, true);
    assert.strictEqual(timers.size, 1, 'failures must remain retryable');
    runTimer();
    destroy();
    requests[3].resolve({data: {items: [{id: 'after-destroy'}]}});
    await flush();
    assert(cancelled, 'destroy must cancel the pending HTTP request');
    assert.strictEqual(timers.size, 0);
    assert(!items.has('after-destroy'));
    console.log('Timeline request lifecycle checks passed');
}
test().catch(error => { console.error(error); process.exitCode = 1; });
