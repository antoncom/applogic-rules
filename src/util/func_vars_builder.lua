local func_vars_builder = {}

-- logic from util/substitute.lua
function func_vars_builder.make_vars(varname, rule, from_input)
    local vars = {}
    for name, _ in pairs(rule.setting) do
        if name ~= varname then
            vars[name] = rule.setting[name].output
        else
            if from_input then
                vars[name] = rule.setting[name].input
            else
                vars[name] = rule.setting[name].subtotal
            end
        end
    end
    return vars
end

return func_vars_builder