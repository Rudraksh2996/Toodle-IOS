# Toodle iOS architecture

Native SwiftUI, iOS 17+, no external app dependencies. `ToodleCore` is a local Swift package containing Foundation-only domain logic, Codable wire adapters, URLSession clients and seeded simulation. The app owns UI, Observation state, MapKit, Charts, AVFoundation and CoreLocation. AWS remains on the existing Amplify backend; no credentials ship in the app.

## Reference and precedence

Ported from Rudraksh2996/Toodle at `05e16819181d5caa34076e16571f66254a4dec0d`. The supplied brief describes the desired native experience; deployed route handlers and `lib/` determine business logic.

- FRI is `0.55V + 0.35A + 0.10R`. `lib/fri.ts` uses continuous upper boundaries .35/.65/.85, NORMAL green #22c55e, ADVISORY amber #f59e0b, WARNING orange #f97316, CRITICAL red #ef4444. Dispatch requires >= .86 (or verified blockage), independently of the risk label.
- Effective rain is max(current, peak last 3h, last24h/6), rounded to two decimals, mapped piecewise at 0/2.5/7.5/15/30 mm/h to 0/.35/.65/.85/1. Rolling history includes the current hourly slot; forecast excludes it. When current time is missing, use max(0, count-6), matching legacy.
- Conservative best-match/GFS merge takes maxima for rain metrics, and primary-model temperature/humidity/wind. One successful model is sufficient. Missing weather is explicitly labeled demo.
- All 12 IDs and coordinates come from `lib/mock-data.ts`, including the exceptional string ID `4`. DTU Main Gate, not Minto Bridge, is the fixed simulation target. Its four V/A/R triples are (.05,.10,0), (.35,.40,.5), (.88,.85,.6), (.95,.92,1). Other nodes retain the legacy random ranges using a seeded generator for reproducible demos. The resulting target FRI values are .0625/.3825/.8415/.9445; invented brief example scores are not substituted.
- Legacy history is synthetic, not recorded sensor history. All generated charts and acoustic waveforms are labeled illustrative.

## Wire compatibility

The README examples differ from the actual Next.js handlers. Decoders accept bare/enveloped nodes, numeric/string IDs, DynamoDB PK identifiers and numeric/string coordinates. Analysis accepts both nested README `data.valid/pooling_score` and flat deployed `roadVerified/v_pooling`, including AWS uppercase label keys. Weather accepts `next6hPrecipMm` as total or hourly array. The analyze request sends `imageBase64` required by the handler plus documented image/GPS metadata. Telemetry sends `rain_rate` required by the handler plus documented `r_rate`. Health checks are strings or structured error objects.

## Resilience and side effects

Every HTTP request has an eight-second timeout. Read failures return explicitly labeled bundled data; weather first tries direct Open-Meteo. Forced offline mode never makes network requests. Analysis fallback is always marked simulated and cannot authorize a real SMS. Dispatch never automatically sends on threshold crossing; it offers an SMS preview and a deliberate send action. Simulation cannot send real SMS. HTTP rejections (especially 429 cooldown) are surfaced; an ambiguous network failure during dispatch is reported as unconfirmed, never silently treated as delivered or automatically retried. Cooldowns are kept across sheet dismissal and app restart.

## Capture trust

Only an in-app camera capture with a recent, accurate, non-simulated GPS fix can authorize field dispatch. Library selections are demo/unverified evidence even if a fresh device fix exists, since their capture location cannot be established. Location fixes expire after two minutes. The server must independently enforce authorization and evidence trust in a production deployment.

## Validation

`swift test --package-path Packages/ToodleCore` validates domain calculations, fixtures, network fallback and simulation. XcodeGen produces the committed Xcode project. Full iOS compilation, simulator smoke tests, permissions and device camera/SMS integration require Xcode; this host currently has only Command Line Tools.
