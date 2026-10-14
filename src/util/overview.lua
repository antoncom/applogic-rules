-- Режим "applogic debug overview": вычисление цвета строки узла в общей отладочной таблице.
--
-- В правиле описывается таблица overview, ключ - имя узла, значение - таблица цветов:
--
--     local overview = {
--         ["signal"] = { ["yellow"] = function(nodes) return <true/false>, <значение> end },
--         ["switch"] = { ["red"]    = function(nodes) return <true/false> end },
--     }
--     self:follow("signal"):debug(overview)
--
-- nodes - то же окно на значения узлов правила, что получают операторы ([func], [skip] и т.д.).
-- Цвет применяется, если функция вернула true. Приоритет: red > yellow > green.
-- Второе возвращаемое значение (необязательное) выводится в колонке RESULT вместо
-- полного значения узла - так таблица остаётся компактной (одно число в строке).
-- Если значение вернули несколько функций, берётся значение сработавшего цвета,
-- а если ни один цвет не сработал - первое непустое значение по приоритету.
-- Если функция упала с ошибкой - строка помечается ✖, текст ошибки выводится в колонке NOTES.
-- Если для узла задано не таблица цветов (например, true) - узел выводится без подсветки.
--
-- Для совместимости поддерживаются и старые строковые условия вида [[ return ($node == "true") ]],
-- но со значениями-таблицами они не работают, поэтому используйте функции.

local func_nodes_builder = require "applogic.util.func_nodes_builder"
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"

local PRIORITY = { "red", "yellow", "green" }

-- Возвращает: hit (true/false), value (для колонки RESULT или nil), err (текст ошибки или nil)
local function eval(rule, cond)
    if type(cond) == "function" then
        local ok, res, value = pcall(cond, func_nodes_builder:make_nodes(rule))
        if not ok then return false, nil, tostring(res) end
        return res == true, value
    elseif type(cond) == "string" then
        local ok, res = pcallchunk(substitute(rule, cond, true))
        if not ok then return false, nil, "lua chunk error" end
        return res == true
    elseif type(cond) == "boolean" then
        return cond
    end
    return false, nil, "unsupported condition type: " .. type(cond)
end

local overview = {}

-- Регистрирует узел в overview-таблице правила и вычисляет его цвет на текущей итерации
function overview.node(rule, nodename, spec)
    if not (rule.debug and rule.debug.nodes and rule.debug.nodes[nodename]) then return end

    local color, err, value, first_value
    if type(spec) == "table" then
        for _, c in ipairs(PRIORITY) do
            if spec[c] ~= nil then
                local hit, v, e = eval(rule, spec[c])
                if e then err = (err and (err .. "\n") or "") .. c .. ": " .. e end
                if first_value == nil and v ~= nil then first_value = v end
                if hit and not color then
                    color = c
                    value = v
                end
            end
        end
    end
    if value == nil then value = first_value end

    rule.debug.nodes[nodename].overview = { color = color, error = err, value = value }
    rule.debug.overviewed = rule.debug.overviewed or {}
    rule.debug.overviewed[nodename] = true
end

return overview
