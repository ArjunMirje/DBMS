const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

async function main() {
    const scheduled = [], requests = [];
    let focused = false, available = true, submit;
    const liveData = {
        dataset: { url: '/live', interval: '10' },
        innerHTML: 'original tables',
        contains: () => focused,
        addEventListener: (type, callback) => { assert.equal(type, 'submit'); submit = callback; },
    };
    const errorMessage = { textContent: '', hidden: true };
    const context = {
        document: { getElementById: id => id === 'live-data' ? liveData : errorMessage, activeElement: {} },
        window: { location: { search: '?view=all&sensor_id=1' }, setTimeout: (callback, delay) => scheduled.push({ callback, delay }) },
        FormData: class { constructor(form) { this.form = form; } },
        fetch: async (url, options) => {
            requests.push({ url, options });
            return { ok: available, text: async () => 'updated tables', json: async () => ({ success: available, message: 'Database unavailable.' }) };
        },
    };
    vm.createContext(context);
    vm.runInContext(fs.readFileSync('static/live.js', 'utf8'), context);
    assert.equal(scheduled[0].delay, 10000);
    await context.refreshTables();
    assert.equal(liveData.innerHTML, 'updated tables');
    assert.equal(requests[0].url, '/live?view=all&sensor_id=1');
    assert.equal(requests[0].options.cache, 'no-store');
    assert.equal(requests[0].options.method, undefined);
    assert.equal(errorMessage.hidden, true);
    focused = true;
    liveData.innerHTML = 'focused alert button';
    await context.refreshTables();
    assert.equal(liveData.innerHTML, 'focused alert button');
    available = false;
    await context.refreshTables();
    assert.equal(liveData.innerHTML, 'focused alert button');
    assert.match(errorMessage.textContent, /Unable to refresh/);
    assert.equal(errorMessage.hidden, false);
    assert.ok(scheduled.every(timer => timer.delay === 10000));

    let prevented = false, replacement;
    const button = { disabled: false };
    const form = {
        action: '/alerts/acknowledge',
        matches: () => true,
        querySelector: () => button,
        replaceWith: text => { replacement = text; },
    };
    const event = { target: form, preventDefault: () => { prevented = true; } };
    available = true;
    await submit(event);
    const ack = requests.at(-1);
    assert.equal(prevented, true);
    assert.equal(ack.url, '/alerts/acknowledge');
    assert.equal(ack.options.method, 'POST');
    assert.equal(ack.options.headers.Accept, 'application/json');
    assert.equal(ack.options.body.form, form);
    assert.equal(replacement, 'Acknowledged');
    assert.equal(button.disabled, false);
    assert.equal(errorMessage.hidden, true);
    replacement = undefined;
    available = false;
    await submit(event);
    assert.equal(replacement, undefined);
    assert.equal(button.disabled, false);
    assert.equal(errorMessage.textContent, 'Database unavailable.');
    let resolveText;
    context.fetch = async (url, options) => options.method === 'POST'
        ? { ok: true, json: async () => ({ success: true }) }
        : { ok: true, text: () => new Promise(resolve => { resolveText = resolve; }) };
    focused = false;
    liveData.innerHTML = 'acknowledged row';
    const delayedRefresh = context.refreshTables();
    await new Promise(resolve => setImmediate(resolve));
    await submit(event);
    resolveText('stale unacknowledged row');
    await delayedRefresh;
    assert.equal(liveData.innerHTML, 'acknowledged row');
    console.log('Passed: reading views, silent refresh, retained filters, acknowledgement without navigation, and error recovery.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
