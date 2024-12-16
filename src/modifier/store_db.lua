local util = require "luci.util"
local json = require "cjson"
--local leveldb = require 'lualeveldb'
local uci = require "luci.model.uci".cursor()
local ubus = require "ubus"



-- Define the LevelDB database path
local inmemory_db_path = uci:get("tsmjournal", "database", "inmemory")
local ondisk_db_path = uci:get("tsmjournal", "database", "ondisk")


-- Function to store data in the database using db_utils
function store_db(varname, mdf_name, modifier, rule)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local varlink = rule.setting[varname] or {}
    local param_list = modifier.param_list or {}
    local result = {}
    local noerror = true

    if (#param_list > 0) then
        local params, name = {}, ''
        for i = 1, #param_list do
            name = param_list[i]
            if name == varname then
                if util.contains({ "journal_reg", "journal_usb", "journal_stm", "journal_userbalance" }, name) then
                    name = "journal"
                end
                params[name] = varlink.subtotal or ""
            else
                params[name] = rule.setting[name] and rule.setting[name].output or ""
            end
        end
        params["ruleid"] = rule.ruleid

        util.ubus("tsmodem.journal", "send", params)

    end
end

return store_db
