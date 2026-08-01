local e=type(getgenv)=="function" and getgenv() or _G
e.SCRIPT_KEY=e.SCRIPT_KEY or ""
e.SLICEHUB_REQUESTED_TIER=e.SLICEHUB_REQUESTED_TIER or (string.find(tostring(e.SCRIPT_KEY), "^SLICE%-PREM%-") and "PREMIUM" or "FREE")
loadstring(game:HttpGet("https://slicebot-production.up.railway.app/api/utility/bootstrap?v="..tostring(os.time())))()
