#!/usr/bin/env bash
# Fetches current weather + a short hourly forecast from Open-Meteo (free,
# no API key/account needed) for either the machine's IP-geolocated
# position (default, via ip-api.com — also free/keyless) or an explicitly
# named city, and prints one combined JSON object.
set -euo pipefail

city="${1:-}"

if [ -n "$city" ]; then
    encoded="$(jq -sRr @uri <<< "$city")"
    geo="$(curl -s "https://geocoding-api.open-meteo.com/v1/search?count=1&name=$encoded")"
    lat="$(jq -r '.results[0].latitude // empty' <<< "$geo")"
    lon="$(jq -r '.results[0].longitude // empty' <<< "$geo")"
    place="$(jq -r '.results[0].name // empty' <<< "$geo")"
    country="$(jq -r '.results[0].country // empty' <<< "$geo")"
else
    ipgeo="$(curl -s "http://ip-api.com/json/")"
    lat="$(jq -r '.lat // empty' <<< "$ipgeo")"
    lon="$(jq -r '.lon // empty' <<< "$ipgeo")"
    place="$(jq -r '.city // empty' <<< "$ipgeo")"
    country="$(jq -r '.country // empty' <<< "$ipgeo")"
fi

if [ -z "$lat" ] || [ -z "$lon" ]; then
    echo '{"error":"location lookup failed"}'
    exit 0
fi

weather="$(curl -s "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,wind_speed_10m,precipitation&hourly=temperature_2m,weather_code,precipitation_probability&timezone=auto&forecast_days=2")"

jq --arg place "$place" --arg country "$country" '. + {place: $place, country: $country}' <<< "$weather"
