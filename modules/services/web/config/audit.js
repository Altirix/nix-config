// The audit log's request and response (audit-http.conf), the client gets all of both. Each is cut at 16k
// (marked with "…") and its control bytes logged as "?", so JSON escaping can't grow a line past what one
// syslog message carries.
const cap = 16384;

function clip(text) {
    const kept = text.length > cap ? text.slice(0, cap) + '…' : text;
    return kept.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '?');
}

// Empty when the body went to a temporary file (over client_body_buffer_size).
function request(r) {
    return clip(r.requestText || '');
}

// Keeps a little more than the cap as the response passes, response() cuts it.
function collect(r, data, flags) {
    const raw = r.variables.audit_raw || '';
    if (raw.length <= cap) {
        r.variables.audit_raw = raw + data.slice(0, cap + 1 - raw.length);
    }
    r.sendBuffer(data, flags);
}

function response(r) {
    return clip(r.variables.audit_raw || '');
}

export default { request, collect, response };
