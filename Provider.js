const pageUrl = 'https://antping.com/batch-tcp';
const targetTextareaSelector = '.nd-textarea';
const startButtonSelector = '.nd-btn-start';
const resultRowSelector = '.ant-table-row';
const pendingPingSelector = '.nd-ping-null';
const resultPingSelector = '.nd-ping';

function getPageUrl() {
    return pageUrl;
}

function isPageReady() {
    return document.querySelector(targetTextareaSelector) !== null && document.querySelector(startButtonSelector) !== null;
}

function fillTargetTextarea(input) {
    const textarea = document.querySelector(targetTextareaSelector);
    if (!textarea) return;

    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(textarea, input);
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
}

function clickStartButton() {
    document.querySelector(startButtonSelector)?.click();
}

function getResultCount() {
    let count = 0;

    for (const row of document.querySelectorAll(resultRowSelector)) {
        const cells = row.querySelectorAll('td');
        if (cells.length < 5) continue;

        if (
            cells[1].querySelector(pendingPingSelector) ||
            cells[2].querySelector(pendingPingSelector) ||
            cells[3].querySelector(pendingPingSelector) ||
            cells[4].querySelector(pendingPingSelector)
        ) { continue }

        count++;
    }

    return count;
}

function getResultData() {
    const results = [];

    for (const row of document.querySelectorAll(resultRowSelector)) {
        const cells = row.querySelectorAll('td');
        if (cells.length < 5) continue;

        const target = cells[0].textContent.trim();
        if (!target) continue;

        const latencies = [];

        for (let index = 1; index <= 4; index++) {
            const latency = Number.parseInt(cells[index].querySelector(resultPingSelector)?.textContent);
            latencies.push(Number.isNaN(latency) ? -1 : latency);
        }

        results.push({ target, latencies });
    }

    return JSON.stringify(results);
}
