import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const REST = `${SB_URL}/rest/v1`;
const H = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function clean(s: unknown): string {
  if (s == null) return "";
  return String(s)
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function tag(block: string, name: string): string {
  const m = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, "i"));
  if (!m) return "";
  let v = m[1];
  const c = v.match(/<!\[CDATA\[([\s\S]*?)\]\]>/);
  if (c) v = c[1];
  return v.trim();
}

function kindGuess(text: string, fallback: string): string {
  const t = (text || "").toLowerCase();
  if (/tender|e-?tender|quotation|\bbid\b|rfp|auction|expression of interest|\beoi\b/.test(t)) return "tender";
  if (/scheme|yojana|scholarship|subsidy|welfare/.test(t)) return "scheme";
  if (/recruit|vacanc|career|\bjob\b|apply|appointment|engagement|walk-?in/.test(t)) return "job";
  return fallback || "job";
}

function parseDeadline(text: string): string | null {
  if (!text) return null;
  let m = text.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/);
  if (m) {
    const d = +m[1], mo = +m[2], y = +m[3];
    if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12) {
      return `${y}-${String(mo).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
    }
  }
  const mon: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };
  m = text.match(/\b(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{4})\b/i);
  if (m) {
    const d = +m[1], mo = mon[m[2].slice(0, 3).toLowerCase()], y = +m[3];
    if (d >= 1 && d <= 31 && mo) {
      return `${y}-${String(mo).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
    }
  }
  return null;
}

function jobTypeGuess(text: string): string {
  const t = text.toLowerCase();
  if (t.includes("intern")) return "Internship";
  if (t.includes("part-time") || t.includes("part time")) return "Part-time";
  if (t.includes("contract") || t.includes("freelance")) return "Contract";
  if (t.includes("remote") || t.includes("anywhere")) return "Remote";
  return "Full-time";
}

// ---- India-only location handling -------------------------------------------
let PLACES: { name: string; state: string }[] = [];

async function loadPlaces() {
  PLACES = (await sbGet("india_places?select=name,state")) || [];
}

function indiaState(loc: string): string | null {
  if (!loc) return null;
  const l = loc.toLowerCase();
  let best: string | null = null;
  let bestLen = -1;
  for (const p of PLACES) {
    if (l.includes(p.name) && p.name.length > bestLen) {
      best = p.state;
      bestLen = p.name.length;
    }
  }
  return best;
}

function isIndiaLocation(loc: string): boolean {
  if (!loc) return false;
  if (indiaState(loc)) return true;
  return /india|anywhere|worldwide|global|work from home|wfh/.test(loc.toLowerCase());
}

function toJobRow(s: any, it: any) {
  const title = clean(it.title).slice(0, 120);
  if (title.length < 2) return null;

  let location = s.kind === "gov"
    ? (s.district_hint && s.state_hint ? `${s.district_hint}, ${s.state_hint}` : (s.state_hint || "India"))
    : clean(it.location).slice(0, 120);
  if (!location) location = "Not specified";
  if (s.kind !== "gov" && !isIndiaLocation(location)) return null;

  let company = clean(it.company).slice(0, 120);
  if (company.length < 2) company = clean(s.name).slice(0, 120);
  let desc = clean(it.description).slice(0, 8000);
  if (desc.length < 10) {
    desc = `${title}${company ? " at " + company : ""}. Details ke liye original posting dekhein.`;
  }
  let apply = clean(it.url);
  if (apply && !/^https:\/\//i.test(apply)) apply = "";
  return {
    title,
    company_name: company,
    location,
    job_type: jobTypeGuess(`${it.job_type || ""} ${title} ${it.description || ""}`),
    description: desc,
    apply_url: apply || null,
    source_name: clean(s.name).slice(0, 120),
    source_url: apply || null,
    kind: kindGuess(`${it.title || ""} ${it.url || ""}`, s.kind_hint || "job"),
    deadline: parseDeadline(`${it.title || ""} ${it.description || ""}`),
    status: "approved",
  };
}

async function fetchText(url: string, ms = 13000): Promise<string> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(url, {
      headers: { "User-Agent": "KaamSetuBot/1.0 (job aggregation; links back to source)" },
      signal: ctrl.signal,
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.text();
  } finally {
    clearTimeout(t);
  }
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) {
      const idx = i++;
      out[idx] = await fn(items[idx]);
    }
  });
  await Promise.all(workers);
  return out;
}

function parseRss(xml: string): any[] {
  const items: any[] = [];
  const blocks = xml.match(/<item[\s\S]*?<\/item>/gi) ||
    xml.match(/<entry[\s\S]*?<\/entry>/gi) || [];
  for (const b of blocks) {
    let link = tag(b, "link");
    if (!link) {
      const m = b.match(/<link[^>]*href="([^"]+)"/i);
      if (m) link = m[1];
    }
    items.push({
      title: tag(b, "title"),
      url: link,
      description: tag(b, "description") || tag(b, "summary") || tag(b, "content"),
      company: tag(b, "author") || tag(b, "dc:creator"),
      location: tag(b, "location") || "",
      job_type: tag(b, "type") || "",
    });
  }
  return items;
}

function pickArray(data: any): any[] {
  if (Array.isArray(data)) return data;
  if (data && typeof data === "object") {
    for (const k of ["jobs", "data", "results", "items", "hits"]) {
      if (Array.isArray(data[k])) return data[k];
    }
  }
  return [];
}

function mapJsonItem(o: any) {
  const pick = (...keys: string[]) => {
    for (const k of keys) if (o && o[k] != null && o[k] !== "") return o[k];
    return "";
  };
  return {
    title: pick("title", "position", "name", "role", "job_title"),
    url: pick("url", "apply_url", "job_url", "link", "absolute_url"),
    description: pick("description", "content", "details", "summary"),
    company: pick("company_name", "company", "employer", "organization"),
    location: pick("location", "candidate_required_location", "city", "region"),
    job_type: pick("job_type", "type", "employment_type", "contract_type"),
  };
}

function parseGov(html: string, base: string): any[] {
  const out: any[] = [];
  const seen = new Set<string>();
  const re = /<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    const href = m[1];
    const text = clean(m[2]);
    if (!text || text.length < 6) continue;
    const blob = (href + " " + text).toLowerCase();
    if (!/(recruit|vacanc|notif|advertis|advt|opening|apply|career|exam|post)/.test(blob)) continue;
    let abs = href;
    try {
      abs = new URL(href, base).toString();
    } catch {
      continue;
    }
    if (!/^https?:\/\//i.test(abs) || seen.has(abs)) continue;
    seen.add(abs);
    out.push({
      title: text.slice(0, 120),
      url: abs,
      description: "",
      company: "",
      location: "",
      job_type: "",
    });
  }
  return out.slice(0, 25);
}

async function sbGet(path: string) {
  const r = await fetch(`${REST}/${path}`, { headers: H });
  if (!r.ok) throw new Error(`GET ${path} -> ${r.status}`);
  return await r.json();
}

async function sbInsertIgnore(row: any): Promise<number> {
  const r = await fetch(`${REST}/jobs?on_conflict=source_url`, {
    method: "POST",
    headers: {
      ...H,
      "Content-Type": "application/json",
      Prefer: "resolution=ignore-duplicates,return=representation",
    },
    body: JSON.stringify([row]),
  });
  if (!r.ok) return 0;
  const data = await r.json().catch(() => []);
  return Array.isArray(data) ? data.length : 0;
}

async function log(severity: string, category: string, message: string, metadata: any) {
  try {
    await fetch(`${REST}/logs`, {
      method: "POST",
      headers: { ...H, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify([{
        severity, category, message,
        app_id: "kaamsetu", environment: "prod", request_id: "ingest", metadata,
      }]),
    });
  } catch (_e) { /* logging must never break ingestion */ }
}

async function sbPatch(path: string, body: any) {
  await fetch(`${REST}/${path}`, {
    method: "PATCH",
    headers: { ...H, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(body),
  });
}

async function processSource(s: any) {
  try {
    let items: any[] = [];
    if (s.kind === "rss") items = parseRss(await fetchText(s.url));
    else if (s.kind === "json") items = pickArray(JSON.parse(await fetchText(s.url))).map(mapJsonItem);
    else if (s.kind === "gov") items = parseGov(await fetchText(s.url), s.url);
    let inserted = 0;
    let skipped = 0;
    for (const it of items) {
      const row = toJobRow(s, it);
      if (!row) {
        skipped++;
        continue;
      }
      inserted += await sbInsertIgnore(row);
    }
    await sbPatch(`job_sources?id=eq.${s.id}`, {
      last_run_at: new Date().toISOString(),
      last_status: `ok: ${inserted} new, ${skipped} skipped of ${items.length}`,
    });
    return { source: s.name, fetched: items.length, inserted, skipped };
  } catch (e) {
    const msg = String(e).slice(0, 200);
    await sbPatch(`job_sources?id=eq.${s.id}`, {
      last_run_at: new Date().toISOString(),
      last_status: `error: ${msg}`,
    });
    await log("WARN", "background", "ingest_source_failed", { source: s.name, error: msg });
    return { source: s.name, error: msg };
  }
}

Deno.serve(async (req) => {
  try {
    const cfg = await sbGet("app_config?key=eq.ingest_key&select=value");
    const expected = cfg?.[0]?.value || "";
    const provided = req.headers.get("x-ingest-key") || "";
    if (!expected || provided !== expected) return json({ error: "unauthorized" }, 401);

    await loadPlaces();

    let limit = 120;
    try {
      const b = await req.clone().json();
      if (b && b.limit) limit = Math.min(400, Number(b.limit));
    } catch (_e) { /* no body */ }
    const sources = await sbGet(`job_sources?active=is.true&select=*&order=last_run_at.asc.nullsfirst&limit=${limit}`);
    const results = await mapLimit(sources, 10, processSource);
    const inserted = results.reduce((a, r: any) => a + (r.inserted || 0), 0);
    const failed = results.filter((r: any) => r.error).length;
    await log("INFO", "background", "ingest_run", { sources: sources.length, inserted, failed });
    return json({ ok: true, ran_at: new Date().toISOString(), sources: sources.length, inserted, results });
  } catch (e) {
    return json({ ok: false, error: String(e).slice(0, 400) }, 500);
  }
});
