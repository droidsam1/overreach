# 0046 — Weather providers: Open-Meteo by default, OpenWeather optional

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

Weather (Today forecast, dry and sunny windows, weather of Garmin runs) only worked with OpenWeather One Call. One
Call needs the user's own key and a separate subscription with payment details, so people without a card had no
weather at all. Overreach has no backend and keeps keys on the device (AGENTS.md), so every provider is called
straight from the phone.

Checked on the official pages (25 Nov 2026):

- **Open-Meteo.** No key, account or card. The free API is for non-commercial use (no subscriptions, ads or
  commercial products), under 10,000 calls a day (5,000 an hour, 600 a minute), data under CC BY 4.0. The forecast
  API gives hourly `temperature_2m`, `precipitation_probability`, `weather_code` (WMO) and `is_day`. The archive
  API (`archive-api.open-meteo.com`) serves the same variables except the precipitation probability; the terms page
  does not treat it separately and the docs say a key is only needed for commercial use. Its servers log IP
  addresses and the requested coordinates for up to 90 days.
- **OpenWeather free plan.** `/data/2.5/forecast` (5 days, 3-hour steps) is included in the free plan with 60
  calls a minute. One Call (the code uses the 4.0 timeline endpoint) is pay-per-call with the first 1,000 calls a
  day free and needs a card.

## Decision

1. Three selectable providers: **Open-Meteo** (default for new installs), **OpenWeather One Call** and
   **OpenWeather free key**. Settings shows what each needs, costs and cannot do (setup, card, resolution, past
   runs, terms) before the person chooses.
2. An install that already saved an OpenWeather key and never chose keeps OpenWeather. A new install starts on
   Open-Meteo but sends nothing until the person confirms it once: the coarse 0.1° area leaves the device to a third
   party, so the consent is explicit even though there is no key to enter.
3. OpenWeather keys are validated with One Call first; a refusal (401 or 403) falls back to the free forecast.
   The detected mode selects the provider and is shown in settings with a hint to upgrade. The free mode returns no
   past-run weather, with no error.
4. All providers produce `WeatherHour`. Open-Meteo WMO codes are mapped to the OpenWeather condition ids that the
   forecast model already understands, so the Today screen, windows and symbols are provider independent. A
   `WeatherHour` can last more than one hour (`durationSeconds`) so 3-hour steps keep their meaning.
5. Switching provider clears stored forecasts and keeps the OpenWeather key until Disconnect. Each provider has its
   own cache file, daily request budget (200) and back-off. Only the coarse area, the requested variables and a
   date range are sent to Open-Meteo; no key, identifier or other personal data.
6. Every screen that shows weather links to the active provider (Open-Meteo.com or OpenWeather).

## Consequences

- People without a card get weather with no setup. Overreach must stay non-commercial (no subscriptions or ads) to
  keep using the free Open-Meteo API; commercial use would need a paid plan or another provider.
- Open-Meteo sees the user's IP address and coarse area, like OpenWeather did; both are disclosed in Settings.
- Runs from the last seven days read the forecast API's `past_days`, because the archive lags by days.
- Open-Meteo history has no precipitation probability, so past-run weather never shows one.
- Adding a provider means a `WeatherSource` implementation, a `WeatherProvider` case with its limitations and an
  attribution link.
