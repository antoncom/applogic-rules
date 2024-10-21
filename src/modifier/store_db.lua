local util = require "luci.util"
local json = require "cjson"
local leveldb = require 'lualeveldb'

-- Define the LevelDB database path
local db_path = "/var/spool/tsmodem/journal.db"  -- Database path

-- Function to store data in the database using db_utils
function store_db(varname, mdf_name, modifier, rule)
    util.perror("store_db called!")
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
                if util.contains({ "journal_reg", "journal_usb", "journal_stm" }, name) then
                    name = "journal"
                end
                params[name] = varlink.subtotal or ""
            else
                params[name] = rule.setting[name] and rule.setting[name].output or ""
            end
        end
        params["ruleid"] = rule.ruleid

        local opt = leveldb.options()
        opt.createIfMissing = true
        opt.errorIfExists = false
        
        local key = os.time() .. "_" .. rule.ruleid
        local success, err = pcall(function()
            -- Open the database
            db = leveldb.open(opt, db_path)
            
            -- Perform the put operation
            db:put(key, json.encode(params))
            
            -- Close the database
            leveldb.close(db)
        end)
        
        -- Handle potential errors
        
        if not success then
            noerror = false
            if rule.debug_mode.enabled then
                result = "Error storing data in LevelDB: " .. err
                -- debug(varname, rule):modifier(mdf_name, param_list, result, noerror)
            end
        else
            if rule.debug_mode.enabled then
                --debug(varname, rule):modifier(mdf_name, param_list, serialized_data, noerror)
            end
        end
    end
end

return store_db
