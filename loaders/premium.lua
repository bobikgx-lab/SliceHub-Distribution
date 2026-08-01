local e=type(getgenv)=="function" and getgenv() or _G
e.SCRIPT_KEY=e.SCRIPT_KEY or ""
loadstring(game:HttpGet("https://slicebot-production.up.railway.app/api/bootstrap?v="..tostring(os.time())))()
