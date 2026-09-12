-- claudebridge -- a Lua command bridge for driving MAME from the outside.
--
-- Enable:  -plugin claudebridge  (plugin.json "start":"true" also auto-loads it)
--
-- Protocol (matches ../ddiigs/MAME_LUA_BRIDGE.md):
--   caller writes Lua source to  /tmp/mame_bridge_cmd.lua   (atomic rename)
--   plugin runs it once per emulated frame, then writes:
--            output text        -> /tmp/mame_bridge_out.txt
--            "done"             -> /tmp/mame_bridge_done
--   at boot/reset the plugin writes "ready" to the done file, so a bare
--   `cat /tmp/mame_bridge_done` == "ready" means MAME is up and idle.
--
-- The tools/mame/claudebridge/ copy in the combatchess_iigs repo is the
-- source of truth; this installed copy is regenerated from it.

local exports = {
    name = "claudebridge",
    version = "1.0.0",
    description = "Claude Code Lua command bridge",
    license = "BSD-3-Clause",
    author = { name = "Claude Code" },
}

local claudebridge = exports

local CMD  = "/tmp/mame_bridge_cmd.lua"
local OUT  = "/tmp/mame_bridge_out.txt"
local DONE = "/tmp/mame_bridge_done"

function claudebridge.startplugin()
    -- MAME 0.254+ notifier handles are RAII objects: a discarded return
    -- value is GC'd and SILENTLY unsubscribes.  Anchor them on the exports
    -- table (held by MAME's plugin registry) so they outlive startplugin.
    exports._subscriptions = {}
    local subs = exports._subscriptions

    local function write_file(path, data)
        local f = io.open(path, "w")
        if f then f:write(data or ""); f:close() end
    end

    local function read_file(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local d = f:read("*a"); f:close(); return d
    end

    -- Run one command string; return its output text. A bare expression is
    -- auto-wrapped in "return ..."; print() output is captured too.
    local function run_cmd(src)
        local buf = {}
        local saved_print = print
        local function capture(...)
            local n = select("#", ...)
            local parts = {}
            for i = 1, n do parts[i] = tostring((select(i, ...))) end
            buf[#buf + 1] = table.concat(parts, "\t")
        end
        local chunk, err = load("return " .. src, "cmd", "t")
        if not chunk then chunk, err = load(src, "cmd", "t") end
        if not chunk then return "ERROR: " .. tostring(err) end
        _G.print = capture
        local results = { pcall(chunk) }
        _G.print = saved_print
        if not results[1] then
            return "ERROR: " .. tostring(results[2])
        end
        for i = 2, #results do buf[#buf + 1] = tostring(results[i]) end
        return table.concat(buf, "\n")
    end

    -- Grab CPU/mem on reset and re-arm the ready flag.
    subs[#subs + 1] = emu.add_machine_reset_notifier(function()
        write_file(DONE, "ready")
        emu.print_info("claudebridge: ready")
    end)

    -- Clean up on machine stop.
    subs[#subs + 1] = emu.add_machine_stop_notifier(function()
        os.remove(CMD); os.remove(OUT); os.remove(DONE)
    end)

    -- Poll for a pending command once per frame.
    emu.register_frame_done(function()
        local src = read_file(CMD)
        if not src then return end
        os.remove(CMD)                       -- consume: run exactly once
        local out = run_cmd(src)
        write_file(OUT, out)
        write_file(DONE, "done")             -- OUT is complete before DONE
    end)

    write_file(DONE, "ready")
end

return exports
