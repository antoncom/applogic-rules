local uci = require "luci.model.uci".cursor()
local debug_cli = {
    rule = uci:get("applogic", "debug_mode", "rule"),
    showvar = uci:get_list("applogic", "debug_mode", "showvar"),
}

return debug_cli
