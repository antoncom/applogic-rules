local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: break
-- ["break"] = function(vars) <lua code> end
local function func(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local vars = func_vars_builder.make_vars(rule)

    local result = ""
    local noerror = true
    local tmp_res

    if type(op_body) == "function" then
        noerror, tmp_res = pcall(op_body, vars)

        if noerror == false then
            print("Error: " .. tostring(tmp_res))
            tmp_res = nil
        end
    else
        tmp_res = nil
        noerror = false
    end
    
    result = tmp_res
    if (type(result) == "boolean" and result == true) then 
        rule.break_in = true

        -- TODO
        -- Очистить значения узлов правила
        -- для того, чтобы после возобновления обработки, не остались старые значния (до break)

        for name, node in luci.util.kspairs(rule.setting) do
            if node.saved then
                node.saved = nil
                node.output = nil
            end
        end

    else 
        rule.break_in = false
    end
    

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end
end

return func