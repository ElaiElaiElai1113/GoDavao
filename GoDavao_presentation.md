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
Urban mobility challenges in Davao City: fragmented routes, congestion, and rising travel costs  
Under‑utilized vehicles and low ride‑sharing adoption  
Need for safe, real‑time, route‑based carpooling tailored to local routes  
Goal: reduce cost per passenger and improve seat utilization without sacrificing safety  

Speaker notes:
Keep this non‑technical. Explain that GoDavao focuses on shared routes and real‑time coordination rather than full taxi replacement.

---

## Slide 3 — Research Overview (Objectives + Contributions)
Design and build a route‑based ridesharing system for Davao City  
Provide dynamic fare estimation with carpool discounts, surge, and booking options  
Support verified driver onboarding and passenger safety features  
Deliver real‑time updates for matching, ride status, and notifications  

Speaker notes:
Emphasize the contributions as a working system plus pricing logic specific to Davao.

---

## Slide 4 — Conceptual / Operational Framework (Architecture)
Frontend: Flutter (mobile + web) with Provider for state management  
Backend: Supabase (PostgreSQL, Auth, Storage, Realtime)  
Routing: OSRM for distance/ETA with Haversine fallback  
Maps: MapLibre GL for route visualization  
Weather: Open‑Meteo for rain‑based surge adjustments  

Speaker notes:
Explain the data flow: UI → Provider → Services → Repositories → Supabase, plus external routing and weather services.

---

## Slide 5 — Pricing Model (Updated From Project)
Base fare: ₱25  
Distance rate: ₱14 per km  
Time rate: ₱0.80 per minute  
Booking fee: ₱5  
Minimum fare: ₱70  
Night surcharge: +15% (21:00–05:00)  
Platform fee: 15% of total  
Carpool discounts by total seats: 2=6%, 3=12%, 4=20%, 5=25%  
Booking modes: Shared, Group Flat (+10%), Pakyaw (+20%)

Shared Ride Pricing (Distance-Proportional):
- Passengers split total route fare based on distance traveled
- Example: 10km route (₱500 total)
  - Passenger A travels 10km → pays ₱333
  - Passenger B travels 5km → pays ₱167
- Total collected equals full route fare

Surge multiplier: 0.7–2.0 based on demand and weather  

Speaker notes:
This slide is the updated pricing from the project code. Highlight the three booking modes and that surge is weather‑ and time‑aware. Emphasize the distance‑proportional pricing for shared rides where passengers pay based on their actual traveled distance.

---

## Slide 6 — System Output: Onboarding & Verification
Role selection: Passenger or Driver  
ID verification upload for users  
Driver vehicle registration (photo + details)  
Admin verification panel for approval workflow  

Speaker notes:
Show onboarding screenshots if available: registration, ID upload, and vehicle form.

---

## Slide 7 — System Output: Passenger Flow
Map search for pickup/destination  
Route preview with distance and ETA  
Real‑time fare breakdown and carpool savings preview  
Choose seats, Group booking, or Pakyaw  
Ride request, live tracking, and notifications  

Speaker notes:
Use 2–3 annotated screenshots or a short walkthrough (map → fare → confirm).

---

## Slide 8 — System Output: Driver Flow
Create and manage driver routes  
Accept/decline ride requests  
Start/End ride with timestamps  
Passenger info and ratings/feedback  

Speaker notes:
Show route creation and ride status screens if available.

---

## Slide 9 — System Output: Safety, Ratings, and Payments
Ratings and feedback for accountability  
Safety tools (SOS, trusted contacts)  
Payment workflow with on‑hold transactions (GCash)  
Realtime updates for ride matches and status  

Speaker notes:
Tie these features to trust and safety for shared rides.

---

## Slide 10 — Conclusions & Recommendations
Evaluation: [[Insert your testing/evaluation method from paper]]  
Key results: [[Insert top 2–3 results or metrics]]  
Limitations: dependence on routing/weather APIs, limited real‑world pilot data  
Future work: larger user study, ML‑based matching, stronger payment integration, regulatory alignment  

Speaker notes:
End with impact: cost savings + better seat utilization + local‑fit design. Invite questions.

