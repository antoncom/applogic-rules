local util = require "luci.util"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local checkubus = require "applogic.util.checkubus"


local function evuuid(name, match)
    return md5.sumhexa(name..util.serialize_json(match))
end

-- operator: subscribe
-- ["subscribe"] = {
--      ubus = "ubus object",
--      evname = "evname",
--      evmatch = { },
-- }
local function loadvar_subscribed(rule, node_name, op_name, op_body, op_index)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local node_table = rule.setting[node_name]
    local subscription = rule.parent.subscription

    local noerror = true
    local err = ""

    -- local ubusobj = string.format("%s", (node_table.source.ubus or ""))
    -- local evname = string.format("%s", (node_table.source.evname or ""))
    -- local evmatch = node_table.source.match or {}

    local ubusobj = string.format("%s", (op_body.ubus or ""))
    local evname = string.format("%s", (op_body.evname or ""))
    local evmatch = op_body.match or {}

    noerror, err = checkubus(rule.conn, ubusobj)
    if noerror then
        -- загружаем первое значение из очереди
        local evmatch_md5 = evuuid(evname, evmatch)
        if (subscription.queu[ubusobj] and subscription.queu[ubusobj][evmatch_md5]) then
            if (#subscription.queu[ubusobj][evmatch_md5].events > 0) then
                node_table.subtotal = util.serialize_json(subscription.queu[ubusobj][evmatch_md5].events[1].msg)
                -- удаляем переменную из спика vars_to_load
                subscription.removeEvent(ubusobj, evmatch_md5, node_table)
            else
                node_table.subtotal = ""
            end
        end
    end


    if rule.debug_mode.enabled then
        if (noerror) then
            debug(node_name, rule):source_subscribe(ubusobj, evname, node_table.subtotal, noerror, op_body)
        else
            debug(node_name, rule):source_subscribe(ubusobj, evname, err, noerror, op_body)
        end
    end
end

return loadvar_subscribed
