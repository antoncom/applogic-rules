local util = require "luci.util"
local uci = require "luci.model.uci".cursor()


-- Define the LevelDB database path
local inmemory_db_path = uci:get("tsmjournal", "database", "inmemory")
local ondisk_db_path = uci:get("tsmjournal", "database", "ondisk")


-- operator: store-db
-- ["store-db"] = { param_list = { "param1", "param2", etc... } }
-- Function to store data in the database using db_utils
local function store_db(rule, node_name, op_name, op_body, op_index)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local node_table = rule.setting[node_name] or {}
    local param_list = op_body.param_list or {}
    local result = {}
    local noerror = true

    if (#param_list > 0) then
        local params, name = {}, ''
        for i = 1, #param_list do
            name = param_list[i]
            if name == node_name then
                if util.contains({ "journal_reg", "journal_usb", "journal_stm", "journal_userbalance" }, name) then
                    name = "journal"
                end
                params[name] = node_table.subtotal or ""
            else
                params[name] = rule.setting[name] and rule.setting[name].output or ""
            end
        end
        params["ruleid"] = rule.ruleid

        util.ubus("tsmodem.journal", "send", params)
    end
end

return store_db