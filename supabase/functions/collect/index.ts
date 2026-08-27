// 핫이슈 수집기 — Supabase Edge Function 판
//
// collector/ 의 Dart 구현을 그대로 옮긴 것이다. **판단 규칙이 같아야 한다** —
// 로컬에서 본 순위와 배포본의 순위가 다르면 무엇을 믿어야 할지 알 수 없게 된다.
// 로직을 고칠 때는 양쪽을 함께 고칠 것.
//
// 왜 서버리스인가: Dart 수집기는 누군가 PC를 켜둬야 한다. 그러면 배포본의
// 순위가 그 PC 전원에 묶인다. 여기로 옮기면 pg_cron 이 알아서 깨운다.
//
// 전부 공식 RSS 신디케이션 피드다. HTML 스크래핑은 하지 않는다.
// 저장하는 것은 키워드·제목·링크뿐이고 기사 본문은 복제하지 않는다.

import { createClient } from "npm:@supabase/supabase-js@2";
import { XMLParser } from "npm:fast-xml-parser@4";

// ── 소스 정의 ──────────────────────────────────────────────────────
// collector/lib/src/source.dart 와 id·가중치가 일치해야 한다.
// 피드가 아니라 **언론사** 단위로 묶는 게 핵심이다. 연합뉴스 섹션 10개를
// 각각 세면 "10곳에 났다"가 되어 확산도가 부풀려진다.

type Kind = "trends" | "news";

interface Outlet {
  id: string;
  label: string;
  weight: number;
  feeds: string[];
  kind: Kind;
}

const YNA_SECTIONS = [
  "politics", "economy", "society", "international", "culture",
  "sports", "entertainment", "health", "industry", "local",
];

const OUTLETS: Outlet[] = [
  {
    id: "googleTrends", label: "구글 트렌드", weight: 1.0, kind: "trends",
    feeds: ["https://trends.google.com/trending/rss?geo=KR"],
  },
  {
    id: "yna", label: "연합뉴스", weight: 0.9, kind: "news",
    feeds: YNA_SECTIONS.map((s) => `https://www.yna.co.kr/rss/${s}.xml`),
  },
  {
    id: "khan", label: "경향신문", weight: 0.75, kind: "news",
    feeds: [
      "https://www.khan.co.kr/rss/rssdata/total_news.xml",
      "https://www.khan.co.kr/rss/rssdata/kh_sports.xml",
    ],
  },
  {
    id: "mk", label: "매일경제", weight: 0.7, kind: "news",
    feeds: [
      "https://www.mk.co.kr/rss/30000001/",
      "https://www.mk.co.kr/rss/71000001/",
      "https://www.mk.co.kr/rss/30000023/",
    ],
  },
  {
    id: "donga", label: "동아일보", weight: 0.7, kind: "news",
    feeds: ["https://rss.donga.com/total.xml"],
  },
  {
    id: "sbs", label: "SBS", weight: 0.75, kind: "news",
    feeds: ["https://news.sbs.co.kr/news/headlineRssFeed.do?plink=RSSREADER"],
  },
  {
    id: "jtbc", label: "JTBC", weight: 0.7, kind: "news",
    feeds: ["https://fs.jtbc.co.kr/RSS/newsflash.xml"],
  },
];

const USER_AGENT = "hotissue-collector/0.1 (+prototype; supabase edge function)";
const ARCHIVE_AFTER_HOURS = 6;
const HEADLINES_PER_FEED = 60;

// ── 정규화 · 매칭 ──────────────────────────────────────────────────
// collector/lib/src/normalize.dart, match.dart 와 같은 규칙.

const STRIP = /[^가-힣ㄱ-ㅎㅏ-ㅣa-z0-9]/g;

function normalize(input: string): string {
  return input.toLowerCase().replace(STRIP, "");
}

function tokenize(input: string): string[] {
  return input
    .toLowerCase()
    .split(/\s+/)
    .map((t) => t.replace(STRIP, ""))
    .filter((t) => t.length > 0);
}

/** 헤드라인이 키워드를 다루는가 (직접 매칭) */
function mentions(haystack: string, keyword: string): boolean {
  const k = normalize(keyword);
  if (k.length < 2) return false;

  const h = normalize(haystack);
  if (h.includes(k)) return true;

  // 한 글자 토큰(골·법·물)도 한국어에서는 의미가 있어 버리지 않는다.
  // 대신 최소 하나는 두 글자 이상이어야 한다 — 전부 한 글자면 아무 데나 걸린다.
  const tokens = tokenize(keyword);
  if (tokens.length < 2) return false;
  if (!tokens.some((t) => t.length >= 2)) return false;

  return tokens.every((t) => h.includes(t));
}

/** 두 제목이 같은 사건인가 (토큰 겹침) */
function sameStory(a: string, b: string): boolean {
  const ta = new Set(tokenize(a).filter((t) => t.length >= 2));
  const tb = new Set(tokenize(b).filter((t) => t.length >= 2));
  if (ta.size === 0 || tb.size === 0) return false;

  let overlap = 0;
  for (const t of ta) if (tb.has(t)) overlap++;
  if (overlap < 2) return false;

  return overlap / Math.min(ta.size, tb.size) >= 0.35;
}

function matches(headline: string, keyword: string, storyTitle?: string): boolean {
  if (mentions(headline, keyword)) return true;
  if (!storyTitle) return false;
  return sameStory(headline, storyTitle);
}

/**
 * 언론사 안에서의 헤드라인 위치를 순위(1~20)로 환산.
 * HotScore 의 rankHorizon 이 20이라 그 이상은 전부 0점이 된다.
 * 300번째에 걸린 것도 "그 언론사가 다뤘다"는 사실은 같으므로 뒤로 갈수록 압축한다.
 */
function newsRank(position: number): number {
  if (position <= 10) return position;
  if (position <= 50) return 10 + Math.ceil((position - 10) / 10);
  if (position <= 200) return 15 + Math.ceil((position - 50) / 50);
  return 20;
}

// ── RSS 파싱 ───────────────────────────────────────────────────────

const parser = new XMLParser({
  ignoreAttributes: true,
  // ht:news_item 같은 네임스페이스 접두사를 떼서 localName 으로 접근한다.
  removeNSPrefix: true,
  parseTagValue: false,
  trimValues: true,
});

function asArray<T>(v: T | T[] | undefined): T[] {
  if (v === undefined || v === null) return [];
  return Array.isArray(v) ? v : [v];
}

function text(v: unknown): string | null {
  if (v === undefined || v === null) return null;
  const s = String(v).trim();
  return s.length === 0 ? null : s;
}

interface TrendEntry {
  keyword: string;
  rank: number;
  approxTraffic: string | null;
  newsTitle: string | null;
  newsUrl: string | null;
  newsOutlet: string | null;
  newsSnippet: string | null;
}

function parseTrends(xml: string): TrendEntry[] {
  const doc = parser.parse(xml);
  const items = asArray(doc?.rss?.channel?.item);

  const out: TrendEntry[] = [];
  for (const item of items) {
    const keyword = text(item?.title);
    if (!keyword) continue;

    // 첫 번째 뉴스 항목을 대표로 쓴다. 피드가 중요도 순으로 준다.
    const news = asArray(item?.news_item)[0];

    out.push({
      keyword,
      rank: out.length + 1,
      approxTraffic: text(item?.approx_traffic),
      newsTitle: news ? text(news.news_item_title) : null,
      newsUrl: news ? text(news.news_item_url) : null,
      newsOutlet: news ? text(news.news_item_source) : null,
      newsSnippet: news ? text(news.news_item_snippet) : null,
    });
  }
  return out;
}

function parseHeadlines(xml: string): string[] {
  const doc = parser.parse(xml);
  const items = asArray(doc?.rss?.channel?.item);

  const out: string[] = [];
  for (const item of items) {
    const t = text(item?.title);
    if (t) out.push(t);
    if (out.length >= HEADLINES_PER_FEED) break;
  }
  return out;
}

async function fetchText(url: string): Promise<string> {
  const res = await fetch(url, {
    headers: { "User-Agent": USER_AGENT },
    signal: AbortSignal.timeout(20_000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return await res.text();
}

// ── 수집 ───────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  const started = Date.now();
  const log: Record<string, string> = {};

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // 1) 트렌드 — 이슈를 정의하는 소스. 실패하면 이번 사이클을 통째로 건너뛴다.
  const trendOutlet = OUTLETS.find((o) => o.kind === "trends")!;
  let trends: TrendEntry[];
  try {
    trends = parseTrends(await fetchText(trendOutlet.feeds[0]));
    log[trendOutlet.id] = `ok (${trends.length})`;
  } catch (e) {
    const message = `트렌드 소스 실패: ${e instanceof Error ? e.message : e}`;
    console.error(message);
    return json({ ok: false, error: message }, 502);
  }

  // 2) 뉴스 — 보도되는지 검증하는 소스. 하나 죽어도 계속 간다.
  //    Edge Function 은 실행 시간 제한이 있으므로 언론사별로 병렬 수집한다.
  const newsOutlets = OUTLETS.filter((o) => o.kind === "news");
  const headlines = new Map<string, string[]>();

  await Promise.all(newsOutlets.map(async (outlet) => {
    const collected: string[] = [];
    let failed = 0;

    const results = await Promise.allSettled(outlet.feeds.map(fetchText));
    for (const r of results) {
      if (r.status === "fulfilled") {
        collected.push(...parseHeadlines(r.value));
      } else {
        failed++;
      }
    }

    headlines.set(outlet.id, collected);
    log[outlet.id] = failed === 0
      ? `ok (${collected.length})`
      : `partial (${collected.length}, 피드 ${failed}개 실패)`;
  }));

  // 3) 직전 순위를 읽어 previous_rank 를 채운다.
  const { data: existing } = await supabase
    .from("issues")
    .select("normalized_keyword, ranks");

  const previousRanks = new Map<string, Record<string, number>>();
  for (const row of existing ?? []) {
    const map: Record<string, number> = {};
    for (const r of (row.ranks ?? []) as Array<Record<string, unknown>>) {
      map[String(r.source)] = Number(r.rank);
    }
    previousRanks.set(row.normalized_keyword, map);
  }

  // 4) 이슈 조립
  const now = new Date().toISOString();
  const rows = trends.map((entry) => {
    const key = normalize(entry.keyword);
    const before = previousRanks.get(key) ?? {};

    const ranks: Array<Record<string, unknown>> = [{
      source: trendOutlet.id,
      rank: entry.rank,
      previous_rank: before[trendOutlet.id] ?? null,
      observed_at: now,
    }];

    for (const outlet of newsOutlets) {
      const list = headlines.get(outlet.id) ?? [];
      const idx = list.findIndex((h) => matches(h, entry.keyword, entry.newsTitle ?? undefined));
      if (idx === -1) continue;

      ranks.push({
        source: outlet.id,
        rank: newsRank(idx + 1),
        previous_rank: before[outlet.id] ?? null,
        observed_at: now,
      });
    }

    return {
      keyword: entry.keyword,
      normalized_keyword: key,
      summary: entry.newsSnippet ?? entry.newsTitle,
      status: statusFor(before, ranks),
      ranks,
      related_keywords: relatedFor(entry, trends, headlines),
      source_title: entry.newsTitle,
      source_url: entry.newsUrl,
      source_outlet: entry.newsOutlet,
      approx_traffic: entry.approxTraffic,
      last_seen_at: now,
      // first_seen_at 은 보내지 않는다. 덮어쓰면 신선도·나이 계산이 망가진다.
    };
  });

  // 5) upsert
  const { error: upsertError } = await supabase
    .from("issues")
    .upsert(rows, { onConflict: "normalized_keyword" });

  if (upsertError) {
    console.error("upsert 실패", upsertError);
    return json({ ok: false, error: upsertError.message, sources: log }, 500);
  }

  // 6) 오래 안 보인 이슈를 아카이브로. 시간 기반이라 점수 계산이 필요 없다.
  const cutoff = new Date(Date.now() - ARCHIVE_AFTER_HOURS * 3600_000).toISOString();
  const { error: archiveError } = await supabase
    .from("issues")
    .update({ status: "archived" })
    .neq("status", "archived")
    .lt("last_seen_at", cutoff);

  if (archiveError) console.error("아카이브 실패", archiveError);

  return json({
    ok: true,
    upserted: rows.length,
    corroborated: rows.filter((r) => r.ranks.length > 1).length,
    elapsed_ms: Date.now() - started,
    sources: log,
  });
});

/** 직전 순위 대비 방향. collector.dart 의 _status 와 같은 규칙. */
function statusFor(
  before: Record<string, number>,
  ranks: Array<Record<string, unknown>>,
): string {
  if (Object.keys(before).length === 0) return "rising";

  let delta = 0;
  let compared = 0;
  for (const r of ranks) {
    const b = before[String(r.source)];
    if (b === undefined) continue;
    delta += b - Number(r.rank);
    compared++;
  }
  if (compared === 0) return "rising";
  if (delta > 1) return "rising";
  if (delta < -1) return "cooling";
  return "steady";
}

/**
 * 같은 헤드라인에 함께 등장하는 트렌드 키워드끼리 연결.
 * 임의 태그가 아니라 실제 동시 등장이라 의미가 있다.
 * 연관 판정은 직접 매칭만 쓴다 — 같은 기사 판정까지 넣으면 무관한 키워드가 엮인다.
 */
function relatedFor(
  self: TrendEntry,
  all: TrendEntry[],
  headlines: Map<string, string[]>,
): string[] {
  const every = [...headlines.values()].flat();
  const out: string[] = [];

  for (const other of all) {
    if (other.keyword === self.keyword) continue;
    const together = every.some((h) =>
      mentions(h, self.keyword) && mentions(h, other.keyword)
    );
    if (together) out.push(other.keyword);
    if (out.length >= 3) break;
  }
  return out;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
