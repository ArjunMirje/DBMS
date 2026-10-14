const liveData = document.getElementById('live-data');
const errorMessage = document.getElementById('error-message');
const interval = Number(liveData.dataset.interval) * 1000;
let pending = 0, revision = 0;

function showError(message = '') {
    errorMessage.textContent = message;
    errorMessage.hidden = !message;
}

async function refreshTables() {
    const version = revision;
    try {
        const response = await fetch(liveData.dataset.url + window.location.search, { cache: 'no-store' });
        if (!response.ok) throw new Error('Unable to refresh readings.');
        const html = await response.text();
        if (!pending && version === revision && !liveData.contains(document.activeElement)) liveData.innerHTML = html;
        showError();
    } catch (error) {
        showError(error.message);
    } finally {
        window.setTimeout(refreshTables, interval);
    }
}

liveData.addEventListener('submit', async event => {
    const form = event.target;
    if (!form.matches('[data-acknowledge]')) return;
    event.preventDefault();
    const button = form.querySelector('button');
    if (button.disabled) return;
    button.disabled = true;
    pending++;
    try {
        const response = await fetch(form.action, { method: 'POST', body: new FormData(form), headers: { Accept: 'application/json' } });
        const result = await response.json();
        if (!response.ok || !result.success) throw new Error(result.message || 'Unable to acknowledge alert.');
        form.replaceWith('Acknowledged');
        showError();
    } catch (error) {
        showError(error.message);
    } finally {
        button.disabled = false;
        pending--;
        revision++;
    }
});

window.setTimeout(refreshTables, interval);
