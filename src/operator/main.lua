local util = require "luci.util"
-- local log = require "applogic.util.log"
-- local last_mdfr_name = require "applogic.util.last_mdfr_name"


-- todo: move operators (modifiers) to operator directory and rewrite imports
-- require "applogic.modifier.skip"
-- require "applogic.modifier.skip_func"
-- require "applogic.modifier.lua"
-- require "applogic.modifier.lua_func"
-- require "applogic.modifier.bash"
-- require "applogic.modifier.frozen"
-- require "applogic.modifier.frozen_func"
-- require "applogic.modifier.trigger"
-- require "applogic.modifier.save"
-- require "applogic.modifier.save_func"
-- require "applogic.modifier.shell"
-- require "applogic.modifier.ui_update"
-- require "applogic.modifier.exec"
-- require "applogic.modifier.mailsend"
-- require "applogic.modifier.smssend"
-- require "applogic.modifier.store_db"

-- new imports
local skip = require "applogic.operator.skip"
local func = require "applogic.operator.func"
local bash = require "applogic.operator.bash"
local save = require "applogic.operator.save"
local frozen = require "applogic.operator.frozen"
local store_db = require "applogic.operator.store_db"
local ui_update = require "applogic.operator.ui_update"


local main = {}
function main:modify(node_name, rule)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
    local varlink = rule.setting[node_name]

    -- Before the modifier applies, we put load the initial (input) value to intermediate (subtotal)
    --varlink.subtotal = varlink.subtotal or string.format("%s", tostring(varlink.input))
    if(varlink["saved"]) then
        varlink.input = varlink["saved"]
    end

    -- TODO refactor the frozen modifier!
    -- TMPL
    if(varlink["frozee"]) then
        varlink.input = varlink["frozee"]
    end

    varlink.subtotal = varlink.subtotal or tostring(varlink.input)

    if varlink.modifier then
        for operator_index, operator_table in util.kspairs(varlink.modifier) do
            local operator_name, operator_body

            -- operator_table: { ["op_name"] = <op_body> }
            for key, value in pairs(operator_table) do
                operator_name = key
                operator_body = value
            end

            if not varlink.frozen  then
                if "skip" == operator_name then
                    local is_skip = skip(rule, node_name, operator_name, operator_body, operator_index)

                    if is_skip then
                        -- Если указать у переменной input = "some value"
                        -- то перед отменой обработки присвоить переменно йзначение из input
                        -- иначе в переменной останется хранится последнее расчётное значение (из output)
                        --varlink.subtotal = varlink.input or varlink.output or ""
                        if rule["default"][node_name].input then
                            varlink.input = string.format("%s", rule["default"][node_name].input) -- cloning default input
                            varlink.subtotal = string.format("%s",varlink.input)
                        else
                            varlink.subtotal = string.format("%s",varlink.output)
                        end
                        break
                    end
                end

                -- if "trigger" == operator_name then
                --     local must_trigger = trigger(node_name, rule)
                --     if not must_trigger then
                --         break
                --     end
                -- end

                if "func" == operator_name then
                    varlink.subtotal = func(rule, node_name, operator_name, operator_body, operator_index)
                end

                if "bash" == operator_name then
                    varlink.subtotal = bash(rule, node_name, operator_name, operator_body, operator_index)
                end

                -- if "mail" == operator_name then
                --     varlink.subtotal = mailsend(node_name, operator_name, operator_body, rule)
                -- end

                -- if "sms" == operator_name then
                --     varlink.subtotal = smssend(node_name, operator_name, operator_body, rule)
                -- end

                if "save" == operator_name then
                    varlink.subtotal = save(rule, node_name, operator_name, operator_body, operator_index)
                end

                -- if "shell" == operator_name then
                --     shell(node_name, operator_name, operator_body, rule)
                -- end

                -- if "exec" == operator_name then
                --     varlink.subtotal = exec(node_name, operator_name, operator_body, rule)
                -- end

                if "ui-update" == operator_name then
                    ui_update(rule, node_name, operator_name, operator_body, operator_index)
                end

                if "store-db" == operator_name then
                    store_db(rule, node_name, operator_name, operator_body, operator_index)
                end
            end

            if "frozen" == operator_name then
                frozen(rule, node_name, operator_name, operator_body, operator_index)
            end
        end
    end
    -- Afterall, put subtotal to output
    -- Remove trailing \n if only one string returned
    if(type(varlink.subtotal) == "table") then
        varlink.output = util.serialize_json(varlink.subtotal)
    else
        varlink.output = string.format("%s", varlink.subtotal)
        local _, n = varlink.output:gsub("\n", "\n")
        if n == 1 then varlink.output = varlink.output:gsub("%s+$", "") end
    end


    if rule.debug_mode.enabled then debug(node_name, rule):output(varlink.output) end
    --varlink.subtotal = nil
    --varlink.bash_join = nil

    -- profiler.stop()
    -- profiler.report("profiler.log")
end


return main