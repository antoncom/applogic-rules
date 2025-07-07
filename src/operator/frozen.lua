local func_vars_builder = require "applogic.util.func_vars_builder"
local util = require "luci.util"

-- operator: frozen
-- ["frozen"] = function(vars) return <table { seconds_to_froze, value_after_unfroze } or number (seconds_to_froze)> end
local function frozen(rule, node_name, op_name, op_body)
    --[[
    To froze variable value once it calculated first time.
    Should return number of seconds to froze.
    Or it may return table like this {seconds, "value after unfroze"}.
    ----------------------------------------]]
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local node_table = rule.setting[node_name]

    local max_seconds = 31536000
    local noerror = true
    local frozen_value = ""
    local seconds_to_froze = 0
    local value_after_unfroze = nil

    -- Keep value of variable while first time modifier applied
    if not node_table.frozen then
        local vars = func_vars_builder.make_vars(rule)

        if(type(op_body) == "function") then
            local tmp_res
            noerror, tmp_res = pcall(op_body, vars)

            if (type(tmp_res) == "table") then
                seconds_to_froze = tmp_res[1] or 0
                value_after_unfroze = tmp_res[2] or nil
            else
                seconds_to_froze = tmp_res or 0
            end
        else
            seconds_to_froze = 0
            noerror = false
        end

        if (tonumber(seconds_to_froze) and (noerror == true)) then
            local delay = seconds_to_froze and tonumber(seconds_to_froze)
            if delay and delay > 0 and delay < max_seconds then
                if (type(node_table.output) == "table") then
                    node_table.output = util.serialize_json(node_table.output)
                elseif (type(node_table.output) == "number" or type(node_table.output) == "string") then
                    node_table.output = tostring(node_table.output)
                end
                node_table.frozen = {
                    seconds = delay,
                    cancel_time = os.time() + delay,
                    value = tostring(node_table.output),
                    value_after = value_after_unfroze
                }
                frozen_value = node_table.frozen.value

                -- ADDON TMPL
                if (noerror) then
                    node_table["frozee"] = node_table.output
                end

            elseif delay == 0 then
                noerror = true
                node_table["frozee"] = nil
            else
                noerror = false
            end
        end
    end

    -- Check delay and unfroze variable's value if time is up
    if (noerror == true) then
        if node_table.frozen and node_table.frozen.cancel_time then
            -- Update Frozen modifier seconds_to_froze (for debug)
            --frozen_value = tostring(varlink.frozen.value)
            frozen_value = node_table.frozen.value
            local now = os.time()
            if (now > node_table.frozen.cancel_time) then
                -- After unfroze put predefined value to the var output
                if (node_table.frozen.value_after) then
                    node_table.output = tostring(node_table.frozen.value_after)
                    node_table.input = tostring(node_table.frozen.value_after)
                end
                node_table.frozen = nil

                -- ADDON TMPL
                node_table["frozee"] = nil

                if rule.debug_mode.enabled then debug(node_name, rule):modifier(op_name, "Frozen until:", "", noerror) end
            else
                if rule.debug_mode.enabled then
                    local remains = node_table.frozen.cancel_time - now
                    local seconds = node_table.frozen.seconds
                    local seconds_to_froze_str = string.format("%s", seconds)
                    debug(node_name, rule):modifier(op_name, "Frozen duration:", seconds_to_froze_str, noerror)
                end
            end
        end
    else
        if rule.debug_mode.enabled then debug(node_name, rule):modifier(op_name, "Frozen duration:", "Wrong frozen value. Check rule!", noerror) end
    end

    return frozen_value
end

return frozen