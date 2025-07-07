local func_vars_builder = {}

function func_vars_builder.make_vars(rule)
    local vars = {}

    for name, _ in pairs(rule.setting) do
        vars[name] = rule.setting[name].output
    end

    return vars
end

return func_vars_builder