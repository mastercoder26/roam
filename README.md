# Roam
<img width="386" height="784" alt="image" src="https://github.com/user-attachments/assets/80156598-fa92-4164-9c1e-fb3df10d2bfd" />

Roam is an iPhone driving coach for families helping a new driver build real experience. It gives them a clearer view of a route before leaving, then turns recorded practice drives into feedback they can actually use.

The repo includes the native iOS app, a web route-planning demo, and the backend route analysis service that powers difficulty scoring.

## How it works

Pick a start, destination, and departure time. Roam analyzes the route shape, maneuvers, traffic-aware timing, daylight, weather, and available road data, then returns a difficulty score with the reasons behind it.

The iOS app keeps the main experience in four tabs: Routes, Drive, Progress, and Profile. Routes handles planning and practice routes. Drive records a session only after the driver starts it. Progress turns qualifying drives into measured miles, coverage, and route-adjusted coaching history.

Drive recording is local-first. The app uses CoreLocation and CoreMotion to filter weak GPS, measure speed changes, and flag events like hard braking, rapid acceleration, sharp cornering, and unstable phone movement. Signed-in users can sync profile and drive history through the data API.

## Features

- Route difficulty scores with reasons, hotspots, alternates, and confidence
- Departure-time comparison for the same trip
- Guided practice plans based on route demands
- Manual drive recording with GPS and motion-based events
- Progress tracking for measured miles, after-dark driving, faster roads, and weekly history
- Shared route import from Apple Maps and Google Maps
- Live Activity and CarPlay views for an active drive
