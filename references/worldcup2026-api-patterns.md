# WorldCup2026 API Patterns & Pitfalls

## API Endpoints (worldcup26.ir, free, no auth)

| Endpoint | Returns | ID scheme |
|----------|---------|-----------|
| `GET /get/games` | 104 matches (72 group + 32 knockout) | id "1"-"72" group, "73"+" knockout |
| `GET /get/teams` | 48 teams with flags, FIFA codes | id "1"-"48" |
| `GET /get/groups` | 12 groups (A-L) with standings | team_id references /get/teams |

## ID Ordering Gotcha (CRITICAL)

API orders group-stage matches by **kickoff time**, NOT by group:

```
API order:  A(1), A(2), B(3), D(4), C(5), D(6), C(7), B(8), E(9), E(10)...
Group order: A(1), A(2), B(3), B(4), C(5), C(6), D(7), D(8)...
```

If you hardcode schedule by group (AABBCC...), IDs won't match API, and score merging will silently assign wrong scores to wrong matches. **Always extract IDs from actual API response.**

## local_date Timezone Trap (CRITICAL — FIXED v1.4.4)

**Root cause**: API `local_date` is the **venue's local time**. The 2026 World Cup spans 4 US/Canada/Mexico timezones, so a single fixed offset cannot convert all matches to Beijing time.

### Venue Timezone → Beijing Offset

| Venue region | Local TZ (June) | Beijing offset | Example API time → Beijing |
|---|---|---|---|
| US Eastern (Atlanta, Miami, Boston, NY/NJ, Philadelphia, Toronto) | UTC-4 (EDT) | **+12h** | 15:00 local → 03:00 BJ |
| US Central (Dallas, Houston, Kansas City) | UTC-5 (CDT) | **+13h** | 15:00 local → 04:00 BJ |
| US Mountain (Denver, Salt Lake City) | UTC-6 (MDT) | **+14h** | 15:00 local → 05:00 BJ |
| Mexico City | UTC-6 (CST, no DST) | **+14h** | 13:00 local → 03:00 BJ |
| US Pacific (LA, San Francisco, Seattle, Vancouver) | UTC-7 (PDT) | **+15h** | 15:00 local → 06:00 BJ |

### What NOT to do

❌ **Don't use a single fixed offset** (original bug: +15h assumed all matches in Pacific time, making all times 3h late for East Coast matches)

❌ **Don't convert API time on-the-fly without venue data** — you don't know which venue each match is at without a stadium-to-timezone mapping

### What to do instead

✅ **Hardcode all Beijing kickoff times in SCHEDULE**, computed from API local_date + correct venue offset:
```ets
const SCHEDULE: MatchRaw[] = [
  {id:'1', home:'Mexico', away:'South Africa', group:'A', kickoff:'06/12 03:00', matchday:'1'},
  // ...
];
```

✅ **Use API only for scores, status, and scorers** — never for time display:
```ets
static getMatches(): MatchInfo[] {
  return buildFallbackMatches();  // Hardcoded SCHEDULE with correct Beijing times
}

static async refreshScores(matches: MatchInfo[]): Promise<void> {
  // Only updates score/status/scorers fields, never touches kickoff
}
```

### How to compute correct Beijing times

1. Query `GET /get/games` for all matches — get each match's `local_date`
2. For each match, determine the venue based on team/host city knowledge:
   - Group A matches (Mexico as host): Mexico City → +14h
   - Most other US matches: +12h (Eastern) or +13h (Central)
   - Canada-hosted matches (Toronto): +12h
3. Apply offset: `API_time + offset_hours` → Beijing time
4. Hardcode the result into the SCHEDULE array

### Alternative: Use authoritative Beijing-time schedule source

The most reliable approach: skip the offset calculation entirely and use a pre-computed Beijing-time schedule from a trusted Chinese sports portal.

**Recommended source**: `https://worldcup2026cn.com/schedule/` — complete 104-match table with:
- Date and Beijing time (GMT+8)
- Stage (小组赛/32强/16强等)
- Home and away team names

**Workflow**:
1. Scrape or visually extract the table from the site
2. Match each row to your hardcoded schedule by team names
3. Directly use the website's Beijing times — no offset calculation needed
4. Verify with user: pick 2-3 matches and confirm the displayed times match CCTV5 broadcast schedule

### Verified sample corrections (v1.4.4)

| id | Match | Old time (wrong) | Correct Beijing time | Offset used |
|----|-------|-----------------|---------------------|-------------|
| 1 | Mexico vs South Africa | 06/12 04:00 | **06/12 03:00** | +14h (Mexico City) |
| 19 | Argentina vs Algeria | 06/17 11:00 | **06/17 09:00** | +13h (US Central) |
| 22 | England vs Croatia | 06/18 06:00 | **06/18 03:00** | +12h (US Eastern) |
| 24 | Ghana vs Panama | 06/18 10:00 | **06/18 07:00** | +12h (US Eastern) |
| 26 | Switzerland vs Bosnia | 06/19 00:00 | **06/19 03:00** | +15h (US Pacific) |

## Response Field Types

`http.HttpDataType.OBJECT` auto-converts JSON types:
- `"TRUE"` → boolean `true`
- `"2"` → number `2`  
- `"finished"` → string `"finished"` (stays string)

Always use `'' + value` before comparing or parsing.

## Hybrid Data Architecture

```
SCHEDULE (hardcoded) → 72 matches with correct Beijing times
    ↓ buildFallbackMatches()
MatchInfo[] with status='scheduled', score=0:0
    ↓ merge API data by ID
MatchInfo[] with real scores, scorers, status
```

Key: `apiMap[g['id']]` lookup by string ID, then update score/status/scorers fields.

## Scorers Field Parsing

API returns scorers as JSON string with Unicode smart quotes:
```
{"J. Quiñones 9'","R. Jiménez 67'"}
```

Must replace `\u2018\u2019\u201C\u201D` (smart quotes) before JSON.parse.
Also strip minutes from scorer names: `name.replace(/\s*\d+.*$/, '')`
