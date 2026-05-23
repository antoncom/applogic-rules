local uci = require "luci.model.uci".cursor()
local debug_cli = {
    rule = uci:get("applogic", "debug_mode", "rule"),
    shownode = uci:get_list("applogic", "debug_mode", "shownode"),
}

return debug_cli
