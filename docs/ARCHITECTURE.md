# Architecture

Toodle is an iOS 17 SwiftUI application. Foundation-only ToodleCore owns models, risk calculations, weather metrics, HTTP requests and simulation. The app uses Observation, MapKit, Charts, AVFoundation and CoreLocation. No AWS credentials are stored on the device.

FRI = 0.55V + 0.35A + 0.10R. Continuous upper boundaries are .35/.65/.85, with green/amber/orange/red bands. Real dispatch requires FRI >= .86 or verified blockage. Effective rain is max(current, peak over three hours, 24-hour total / 6). The two weather models merge conservatively using maxima.

KIET Main Gate is the fixed simulation target. Its four V/A/R triples are (.05,.10,0), (.35,.40,.5), (.88,.85,.6), (.95,.92,1). Other nodes use seeded values within stage-specific ranges. In live mode, node history accumulates responses observed during the app session; the current API does not publish an acoustic waveform.

Reads have eight-second timeouts and labeled demo fallbacks. Weather tries Open-Meteo before demo data. Dispatch errors remain visible; a network failure is never reported as a successful delivery. Simulated alerts never send SMS. Library photos do not establish capture location. Fresh accurate GPS and an in-app camera capture are required for verified field evidence.

Field dispatch uses the visual pooling score as its request risk score. The backend may reject a flood-only report below .86 even when field evidence passes the .70 eligibility gate; that rejection is displayed. GPS validity is checked again at send time.
