# GoDavao — Oral Presentation Deck (15 minutes)

## Slide 1 — Title
GoDavao: A Dynamic Ridesharing App for Davao City  
[[Program/Department]]  
Researchers: [[Name 1]], [[Name 2]], [[Name 3]]  
Adviser: [[Adviser Name]]  

Speaker notes:
Open with the problem in Davao City and why shared rides matter. Briefly state that this is a working prototype with a complete passenger–driver flow.

---

## Slide 2 — Application & Technology Context (Problem + Motivation)
Davao commuters face congestion, inconsistent routes, and rising travel costs  
Many vehicles run under-filled, while passengers struggle to find efficient rides  
Existing apps focus on point-to-point trips, not shared routes aligned to daily travel patterns  
Goal: make rides more affordable and reliable by sharing seats on compatible routes  

Speaker notes:
Keep it simple: the app is about sharing a ride along similar paths, not replacing taxis.

---

## Slide 3 — Research Overview (Objectives + Contributions)
Objectives: design a localized ridesharing system that improves efficiency, affordability, and safety  
Contributions: working prototype, dynamic pricing logic, and real-time ride coordination  
Significance: reduces per-passenger cost and improves seat utilization in Davao  

Speaker notes:
Highlight the local fit: routes, pricing, and safety are tuned for Davao’s commuting patterns.

---

## Slide 4 — Conceptual / Operational Framework (Architecture)
Client: Flutter app for passengers and drivers  
Backend: Supabase (Auth, PostgreSQL, Storage, Realtime)  
Routing: OSRM for distance/ETA (Haversine fallback)  
Maps: MapLibre GL for live route display  
Weather: Open-Meteo for rain-based surge adjustments  

Speaker notes:
Explain the flow: app → backend → routing/weather services → real-time updates.

---

## Slide 5 — Pricing Model (Current System)
Base fare: ₱25  
Distance rate: ₱14 per km  
Time rate: ₱0.80 per minute  
Booking fee: ₱5  
Minimum fare: ₱70  
Night surcharge: +15% (21:00–05:00)  
Platform fee: 15% of total  
Carpool discounts by total seats: 2=6%, 3=12%, 4=20%, 5=25%  
Booking modes: Shared, Group Flat (+10%), Pakyaw (+20%)  
Surge multiplier: 1.0–1.8 based on rush hours and rain  

Speaker notes:
This slide reflects the current pricing logic in the project. Highlight the three booking modes and that surge is weather- and time-aware.

---

## Slide 6 — System Output: Onboarding & Verification
Role selection: Passenger or Driver  
ID verification upload and review  
Driver vehicle registration (photo + details)  
Admin verification workflow  

Speaker notes:
Show onboarding screenshots if available: registration, ID upload, and vehicle form.

---

## Slide 7 — System Output: Passenger Flow
Map search for pickup and destination  
Route preview with distance and ETA  
Fare breakdown and carpool savings preview  
Choose seats, Group booking, or Pakyaw  
Ride request, live tracking, and notifications  

Speaker notes:
Use 2–3 annotated screenshots or a short walkthrough (map → fare → confirm).

---

## Slide 8 — System Output: Driver Flow
Create and publish driver routes  
Accept/decline ride requests  
Start/End ride with timestamps  
Passenger info and ratings/feedback  

Speaker notes:
Show route creation and ride status screens if available.

---

## Slide 9 — System Output: Safety, Ratings, and Payments
Ratings and feedback for accountability  
Safety tools (SOS, trusted contacts)  
Payment workflow with on-hold transactions (GCash)  
Realtime updates for ride matches and status  

Speaker notes:
Tie these features to trust and safety for shared rides.

---

## Slide 10 — Conclusions & Recommendations
Evaluation: UAT (passengers + drivers), unit/integration testing, system log analysis  
Key results: 100% UAT pass rate; SUS score 85.4 (Excellent)  
Limitations: small sample size; limited payment options; Davao-specific calibration  
Future work: larger pilot, multi-payment support, expanded service areas, algorithm tuning  

Speaker notes:
End with impact: cost savings + better seat utilization + local-fit design. Invite questions.
