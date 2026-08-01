local e=type(getgenv)=="function" and getgenv() or _G
e.SCRIPT_KEY=e.SCRIPT_KEY or ""
e.SLICEHUB_REQUESTED_TIER="PREMIUM"
loadstring(game:HttpGet("https://slicebot-production.up.railway.app/api/bootstrap?v="..tostring(os.time())))()
