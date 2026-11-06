// Keeps the first 32k of a response in $audit_response for the audit log (audit-http.conf), the client gets all of it.
const cap = 32768;

function collect(r, data, flags) {
    const kept = r.variables.audit_response || '';
    if (kept.length < cap) {
        r.variables.audit_response = kept + data.slice(0, cap - kept.length);
    }
    r.sendBuffer(data, flags);
}

export default { collect };
