local pretty = require "applogic.util.test"

print(pretty({ ["state"] = "connected", ["conninfo"] = { ["remote"] = { ["family"] = "ipv4", ["port"] = 1883, ["address"] = "45.89.25.58" }, ["local"] = { ["family"] = "ipv4", ["port"] = 42814, ["address"] = "192.168.1.20" } }, ["broker"] = { ["host"] = "platform.wimark.com", ["port"] = "1883" }, ["id"] = "3015be6a-5ca8-ff1a-3655-44d1faa50958", ["version"] = "openwrt-21.02.95" }))
