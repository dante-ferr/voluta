#!/usr/bin/env python3
import json
import urllib.request
import sys

def get_weather():
    try:
        url = "https://wttr.in/?format=j1"
        req = urllib.request.Request(url, headers={'User-Agent': 'WaybarWeather/1.0'})
        with urllib.request.urlopen(req, timeout=4) as response:
            data = json.loads(response.read().decode('utf-8'))
            cur = data['current_condition'][0]
            temp = cur['temp_C']
            desc = cur['weatherDesc'][0]['value']
            
            # Simple icon mapping
            weather_code = int(cur.get('weatherCode', '113'))
            icon = "☀️"
            if weather_code in [113]:
                icon = "☀️"
            elif weather_code in [116, 119, 122]:
                icon = "⛅"
            elif weather_code in [266, 293, 296, 302, 308, 353, 356]:
                icon = "🌧️"
            elif weather_code in [200, 386, 389]:
                icon = "⛈️"
            elif weather_code in [227, 230, 323, 326, 332]:
                icon = "❄️"
            elif weather_code in [143, 248, 260]:
                icon = "🌫️"

            out = {
                "text": f"{icon} {temp}°C",
                "tooltip": f"{desc}, {temp}°C",
                "class": "weather"
            }
            print(json.dumps(out))
    except Exception:
        # Graceful silent fallback if offline
        print(json.dumps({"text": "⛅ --°C", "tooltip": "Offline", "class": "weather"}))

if __name__ == "__main__":
    get_weather()
