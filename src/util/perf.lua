-- Режим "applogic debug perf": расход CPU, времени и памяти по правилам и операторам.
--
-- Запуск:  applogic debug perf
--
-- Каждые PERF_WINDOW итераций в консоль выводится таблица со средними значениями
-- на одну итерацию за это окно:
--   CPU ms   - процессорное время applogic (os.clock: user+sys процесса);
--   WALL ms  - реальное время, включая ожидание ответов по ubus от других сервисов;
--   MAX ms   - самое долгое (WALL) одно выполнение за окно: пики, например при перечитывании конфигов;
--   ALLOC KB - сколько памяти Lua выделено (≈, по collectgarbage("count"));
--   CALLS    - сколько раз выполнялось за итерацию.
--
-- Время оператора входит во время правила, а строки ubus.* - во время [load-ubus],
-- поэтому строки разных секций не складываются между собой.
--
-- В этом режиме отладка узлов выключена (applogic.sh ставит debug_mode.enable=0),
-- чтобы сбор отладочных данных не искажал замеры: правила работают как в обычном режиме.

local debug_cli = require "applogic.node.debug_cli"

local PERF_WINDOW = 10      -- итераций в одном окне усреднения (≈ 10 x (800 мс + итерация))
local PERF_LEGEND = true    -- выводить под таблицей раздел "КАК ЧИТАТЬ" (пояснения для колонок)

local perf = {}
perf.enabled = (debug_cli.rule == "perf" or debug_cli.rule == "cpu")
if not perf.enabled then
    return perf
end

local ok_socket, socket = pcall(require, "socket")
local clock = os.clock
local wall = (ok_socket and socket.gettime) or os.time
local function mem() return collectgarbage("count") end

local stats = {}            -- stats[group][name] = { cpu, wall, kb, n, max }
local window = { iterations = 0, first = nil, last = nil, alloc = 0, alloc_iters = 0, live = 0, now = 0 }
local iter_mark             -- начало текущей итерации: { c, w }
local last_end              -- конец предыдущей итерации: { c, w }
local prev_live             -- размер кучи Lua после GC на предыдущей итерации
local warmup = true         -- первая итерация (инициализация правил, подписки) в статистику не идёт

local function acc(group, name, cpu, w, kb)
    local g = stats[group]
    if not g then g = {}; stats[group] = g end
    local s = g[name]
    if not s then s = { cpu = 0, wall = 0, kb = 0, n = 0, max = 0 }; g[name] = s end
    s.cpu = s.cpu + cpu
    s.wall = s.wall + w
    if kb and kb > 0 then s.kb = s.kb + kb end    -- если внутри прошёл GC, разница отрицательная - не учитываем
    s.n = s.n + 1
    if w > s.max then s.max = w end
end

-- Замер участка кода:
--     local c0, w0, m0 = perf.start()
--     ...
--     perf.stop("op", "load-ubus", c0, w0, m0)
function perf.start()
    return clock(), wall(), mem()
end

function perf.stop(group, name, c0, w0, m0)
    if warmup then return end
    acc(group, name, clock() - c0, wall() - w0, mem() - m0)
end

-- Начало итерации: время между итерациями (uloop, таймер, события ubus/подписки)
function perf.iter_begin()
    local c, w = clock(), wall()
    if last_end and not warmup then
        acc("loop", "between", c - last_end.c, w - last_end.w, 0)
    end
    iter_mark = { c = c, w = w }
end

-- Сборка мусора в конце итерации: rules:clear_cache() раз в несколько итераций
-- делает полную сборку (collectgarbage()) и возвращает true.
-- Размер "живой" кучи и сколько выделяется за итерацию считаем только по полным сборкам:
-- между ними мусор копится в куче, а инкрементальный сборщик до порога почти не работает.
local iters_since_full = 0
function perf.gc(fn)
    local before = mem()
    local c0, w0 = clock(), wall()
    local full = fn()
    local live = mem()
    iters_since_full = iters_since_full + 1
    if not warmup then
        acc("loop", "gc", clock() - c0, wall() - w0, 0)
    end
    if full then
        if not warmup then window.live = live end
        if prev_live and not warmup then
            window.alloc = window.alloc + math.max(0, before - prev_live)
            window.alloc_iters = window.alloc_iters + iters_since_full
        end
        prev_live = live
        iters_since_full = 0
    end
    window.now = live
end

local report  -- объявлена ниже

-- Конец итерации: общее время, вывод таблицы раз в PERF_WINDOW итераций
function perf.iter_end(iteration)
    if not iter_mark then return end
    local c, w = clock(), wall()
    if warmup then
        warmup = false
        print(string.format("applogic perf: итерация #%d (инициализация) пропущена, таблица - через %d итераций",
            iteration, PERF_WINDOW))
    else
        acc("loop", "TOTAL", c - iter_mark.c, w - iter_mark.w, 0)
        window.iterations = window.iterations + 1
        window.first = window.first or iteration
        window.last = iteration
        if window.iterations >= PERF_WINDOW then
            report()
            stats = {}
            window = { iterations = 0, first = nil, last = nil, alloc = 0, alloc_iters = 0, live = window.live, now = window.now }
        end
    end
    -- Время на вывод таблицы не попадает ни в итерацию, ни в "between"
    last_end = { c = clock(), w = wall() }
end

-------------------------------------------------------------------------------
-- Вывод таблицы
-------------------------------------------------------------------------------
local ft = require "applogic.util.fort"
local util = require "luci.util"

local function ms(sec) return string.format("%.1f", sec * 1000) end

report = function()
    local n = window.iterations
    local total = stats.loop and stats.loop.TOTAL
    local between = stats.loop and stats.loop.between
    if not total then return end
    local total_cpu = total.cpu / n

    local ftable = ft.new()
    local row = 0
    -- calls: текст для колонки CALLS (по умолчанию - среднее число выполнений за итерацию);
    -- no_alloc: для строк итерации ALLOC не считается
    local wait_example        -- строка с самым большим ожиданием (WALL - CPU) - для примера в легенде
    local function line(name, s, calls, note, no_alloc, track_wait)
        row = row + 1
        if s and track_wait then
            local wait = (s.wall - s.cpu) / n
            if wait > 0.0005 and (not wait_example or wait > wait_example.wait) then   -- больше 0.5 мс
                wait_example = { name = name:gsub("^%s+", ""), cpu = s.cpu / n, wall = s.wall / n, wait = wait }
            end
        end
        if not s then
            ftable:write_ln(name, "-", "-", "-", "-", "-", note or "")
            return
        end
        ftable:write_ln(name, ms(s.cpu / n), ms(s.wall / n), ms(s.max),
            no_alloc and "-" or string.format("%.0f", s.kb / n),
            calls or string.format("%.1f", s.n / n), note or "")
        -- Тяжёлые позиции (больше 20% CPU итерации) - жёлтым
        if total_cpu > 0 and (s.cpu / n) > 0.2 * total_cpu and name ~= "TOTAL" then
            ftable:set_cell_prop(row, 1, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
            ftable:set_cell_prop(row, 2, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
        end
    end
    local function section(title)
        ftable:add_separator()
        row = row + 1
        ftable:write_ln(title, "", "", "", "", "", "")
        ftable:set_cell_span(row, 1, 7)
        ftable:set_cell_prop(row, 1, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
        ftable:set_cell_prop(row, 1, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
    end

    ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
    for col = 2, 6 do ftable:set_cell_prop(ft.ANY_ROW, col, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_RIGHT) end
    ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)
    ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)

    row = row + 1
    ftable:write_ln("APPLOGIC PERF", "CPU ms", "WALL ms", "MAX ms", "ALLOC KB", "CALLS",
        string.format("%s, среднее на итерацию за %d (#%d-%d)", os.date("%H:%M:%S"), n, window.first, window.last))

    -- Правила
    section("ПРАВИЛА")
    for name, s in util.kspairs(stats.rule or {}) do
        line(name, s, "1")
    end

    -- Операторы, с разбивкой [load-ubus] на ubus.*
    section("ОПЕРАТОРЫ (время входит во время правил)")
    for name, s in util.kspairs(stats.op or {}) do
        line(name, s, nil, nil, nil, name ~= "load-ubus")
        if name == "load-ubus" then
            for sub, ss in util.kspairs(stats.ubus or {}) do
                line("  " .. sub, ss, nil, nil, nil, true)
            end
        end
    end

    -- Итерация
    section("ИТЕРАЦИЯ")
    line("gc", stats.loop.gc, "-", "clear_cache(); полная сборка раз в 10 итераций - см. MAX", true)
    line("TOTAL", total, "-", "вся итерация", true)
    line("between", between, "-", "между итерациями: таймер uloop, события ubus", true)
    if between then
        local cpu = (total.cpu + between.cpu) / n
        local period = (total.wall + between.wall) / n
        row = row + 1
        ftable:write_ln("load", string.format("%.1f %%", (period > 0) and (cpu / period * 100) or 0), "", "", "", "",
            string.format("CPU (TOTAL+between) / период итерации %s мс", ms(period)))
        ftable:set_cell_prop(row, 1, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
        ftable:set_cell_prop(row, 2, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
    end
    row = row + 1
    local alloc = (window.alloc_iters > 0) and string.format("%.0f", window.alloc / window.alloc_iters) or "-"
    ftable:write_ln("heap", string.format("%.0f KB", window.live), "", "", alloc, "",
        string.format("куча Lua после полной сборки (сейчас %.0f KB); ALLOC - выделено за итерацию", window.now))

    -- Пояснения к колонкам - для тех, кто смотрит на таблицу впервые
    if PERF_LEGEND then
        local example
        if wait_example then
            example = string.format("           Например, %s: CPU %s мс, WALL %s мс - около %s мс applogic ждал ответа.",
                wait_example.name, ms(wait_example.cpu), ms(wait_example.wall), ms(wait_example.wait))
        end
        local legend = {
            "CPU ms   - сколько процессорного времени потратил сам applogic (в среднем за одну итерацию).",
            "WALL ms  - сколько прошло времени по часам: CPU + ожидание ответов других сервисов (tsmodem, uci, ...).",
            "           WALL намного больше CPU - applogic в это время ждёт, а не нагружает процессор.",
            example or false,
            "MAX ms   - самое долгое одно выполнение за окно (по часам). Показывает редкие пики,",
            "           которые в среднем незаметны: например, перечитывание конфигов или полную сборку мусора.",
            "ALLOC KB - сколько памяти Lua выделено за итерацию (≈). CALLS - сколько раз выполнялось за итерацию.",
            "load     - доля процессора, которую занимает applogic: CPU / период итерации (100 % = одно ядро целиком).",
            "Время операторов уже входит во время правил, а ubus.* - во время load-ubus: строки разных секций не складывают.",
        }
        section("КАК ЧИТАТЬ")
        for _, text in ipairs(legend) do
            if text then
                row = row + 1
                ftable:write_ln(text, "", "", "", "", "", "")
                ftable:set_cell_span(row, 1, 7)
                ftable:set_cell_prop(row, 1, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_GRAY)
            end
        end
    end

    ftable:set_border_style(ft.BOLD_STYLE)
    print(tostring(ftable))
end

return perf
