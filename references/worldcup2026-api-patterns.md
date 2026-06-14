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

## local_date Timezone Trap

API `local_date` is in **UTC-5 (US Eastern)** for most matches, but varies by venue city (UTC-4 to UTC-10).

```
API: "06/13/2026 21:00" (UTC-5 local)
+15h → "06/14 12:00" Beijing time ✅ (correct for most matches)
```

However, matches in different US timezones produce different offsets:
- East Coast (UTC-5): +15h works
- West Coast (UTC-8): +15h gives wrong result
- Hawaii (UTC-10): +15h gives wrong result

**Solution**: Don't convert. Hardcode Beijing times from official schedule, use API only for scores/status.

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
