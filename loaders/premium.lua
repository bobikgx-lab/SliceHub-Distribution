getgenv().SCRIPT_KEY = getgenv().SCRIPT_KEY or ""

local url =
    "https://raw.githubusercontent.com/" ..
    "bobikgx-lab/SliceHub-Distribution/main/" ..
    "builds/SliceHub_PREMIUM.lua"

loadstring(game:HttpGet(
    url .. "?v=" .. tostring(os.time())
))()
