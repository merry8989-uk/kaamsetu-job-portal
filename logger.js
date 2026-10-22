/* KaamSetu client logger.
   Captures application, error, performance, activity and security events.
   Passwords and tokens are never logged, and sensitive metadata keys are redacted. */
(function () {
  var SUPABASE_URL = "https://lnclkwvbismmhhygpblw.supabase.co";
  var SUPABASE_ANON_KEY = "sb_publishable_dMccx0xBmAfPLHO8h1FlNA_i_BJjD0J";
  var APP = "kaamsetu", ENV = "prod";
  var deviceId = "";
  try { deviceId = localStorage.getItem("kaamsetu_device_id") || ""; } catch (e) {}
  var requestId = (window.crypto && crypto.randomUUID)
    ? crypto.randomUUID()
    : "req-" + Date.now() + "-" + Math.random().toString(36).slice(2);
  var SENSITIVE = /pass|pwd|token|secret|authoriz|apikey|api_key|cookie|session/i;

  function sanitize(v, depth) {
    depth = depth || 0;
    if (v == null) return null;
    if (depth > 3) return "[deep]";
    if (typeof v !== "object") return typeof v === "string" ? v.slice(0, 500) : v;
    if (Array.isArray(v)) return v.slice(0, 20).map(function (x) { return sanitize(x, depth + 1); });
    var out = {};
    for (var k in v) {
      if (!Object.prototype.hasOwnProperty.call(v, k)) continue;
      if (SENSITIVE.test(k)) { out[k] = "[redacted]"; continue; }
      try { out[k] = sanitize(v[k], depth + 1); } catch (e) {}
    }
    return out;
  }

  function send(severity, category, message, metadata) {
    try {
      var body = [{
        severity: severity,
        category: category,
        message: String(message).slice(0, 1000),
        app_id: APP,
        environment: ENV,
        request_id: requestId,
        device_id: deviceId,
        path: location.pathname,
        metadata: sanitize(metadata)
      }];
      fetch(SUPABASE_URL + "/rest/v1/logs", {
        method: "POST",
        keepalive: true,
        headers: {
          "Content-Type": "application/json",
          apikey: SUPABASE_ANON_KEY,
          Authorization: "Bearer " + SUPABASE_ANON_KEY,
          Prefer: "return=minimal"
        },
        body: JSON.stringify(body)
      }).catch(function () {});
    } catch (e) {}
  }

  window.KSLog = {
    trace: function (c, m, d) { send("TRACE", c, m, d); },
    debug: function (c, m, d) { send("DEBUG", c, m, d); },
    info: function (c, m, d) { send("INFO", c, m, d); },
    warn: function (c, m, d) { send("WARN", c, m, d); },
    error: function (c, m, d) { send("ERROR", c, m, d); },
    fatal: function (c, m, d) { send("FATAL", c, m, d); },
    security: function (m, d) { send("WARN", "security", m, d); },
    requestId: requestId
  };

  window.addEventListener("error", function (e) {
    send("ERROR", "error", e.message || "Script error", {
      source: (e.filename || "") + ":" + (e.lineno || 0),
      stack: e.error && e.error.stack ? String(e.error.stack).slice(0, 800) : null
    });
  });
  window.addEventListener("unhandledrejection", function (e) {
    var r = e.reason || {};
    send("ERROR", "error", "Unhandled promise rejection", { reason: String(r.message || r).slice(0, 500) });
  });

  send("INFO", "activity", "page_view", { referrer: document.referrer || null });
  window.addEventListener("load", function () {
    try {
      var nav = performance.getEntriesByType && performance.getEntriesByType("navigation")[0];
      var ms = nav ? Math.round(nav.loadEventEnd || nav.duration || performance.now()) : Math.round(performance.now());
      send("INFO", "performance", "page_load", { ms: ms, path: location.pathname });
    } catch (e) {}
  });
})();
