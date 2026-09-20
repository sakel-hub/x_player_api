-- luacheck: globals export
-- scripts/doc_format.lua
-- Compact Markdown documentation generator for x_player_api via lua-language-server
local util = require 'utility'
local jsonb = require 'json-beautify'

export.serializeAndExport = function(docs, outputDir)
    local jsonPath = outputDir .. '/doc.json'
    local mdPath = outputDir .. '/doc.md'

    -- Export standard JSON AST
    local old_support = jsonb.supportSparseArray
    jsonb.supportSparseArray = true
    local jsonOk, jsonErr = util.saveFile(jsonPath, jsonb.beautify(docs))
    jsonb.supportSparseArray = old_support

    -- Build compact, structured Markdown
    local lines = {}
    local function emit(str)
        table.insert(lines, str or "")
    end

    emit("# x_player_api API Reference")
    emit("")
    emit("High-performance player animation, locomotion, eating simulation, and 3D wield items API for Luanti.")
    emit("")

    -- Table of Contents
    emit("## Table of Contents")
    emit("")
    emit("- [Classes & Data Structures](#classes--data-structures)")
    emit("- [Type Aliases & Callbacks](#type-aliases--callbacks)")
    emit("- [Core & Model API](#core--model-api)")
    emit("- [Visual Proxies & Observers API](#visual-proxies--observers-api)")
    emit("- [Locomotion & Action Controls API](#locomotion--action-controls-api)")
    emit("- [Eating & Consumables API](#eating--consumables-api)")
    emit("- [3D Wield Item API](#3d-wield-item-api)")
    emit("- [Registries & State Tables](#registries--state-tables)")
    emit("")
    emit("---")
    emit("")

    -- Categorize documentation items
    local classes = {}
    local aliases = {}
    local functions = {}
    local variables = {}

    for _, item in ipairs(docs) do
        local name = item.name
        if not name and item.defines and item.defines[1] then
            name = item.defines[1].view
        end

        local def1 = item.defines and item.defines[1]
        local file = (def1 and def1.file) or ""
        local is_foreign = file:find("^%[FOREIGN%]") or file:find("Luanti%.app") or file:find("builtin")

        -- Filter out foreign library definitions, internal engine overrides, and private fields
        local is_valid = name and name ~= "LuaLS"
            and not is_foreign
            and not name:find("^core%.")
            and not name:find("%.%_")
            and not name:find("^player_api%.[^%.]+%.")
            and not name:find("^x_player_api%.[^%.]+%.")
        if is_valid then
            if item.type == "type" and name ~= "player_api" and name ~= "x_player_api" then
                if def1 and def1.type == "doc.alias" then
                    table.insert(aliases, item)
                else
                    table.insert(classes, item)
                end
            elseif def1 and (def1.view == "function"
                or (def1.extends and def1.extends.type == "function")) then
                table.insert(functions, item)
            elseif name ~= "x_player_api" and name ~= "player_api" then
                table.insert(variables, item)
            end
        end
    end

    table.sort(classes, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(aliases, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(functions, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(variables, function(a, b) return (a.name or "") < (b.name or "") end)

    -- Classes
    emit("## Classes & Data Structures")
    emit("")
    for _, cls in ipairs(classes) do
        local cname = cls.name or (cls.defines and cls.defines[1] and cls.defines[1].view) or "Unknown"
        emit("### `" .. cname .. "`")
        emit("")
        if cls.desc and cls.desc ~= "" then
            emit(cls.desc)
            emit("")
        end

        if cls.fields and #cls.fields > 0 then
            emit("| Field | Type | Description |")
            emit("| :--- | :--- | :--- |")
            local seen_fields = {}
            for _, field in ipairs(cls.fields) do
                local fname = field.name
                local is_public_custom = cls.name == "WieldItemCustomDef"
                    or (fname and fname:find("^_wield_"))
                local is_private = fname and fname:find("^_") and not is_public_custom
                if fname and not seen_fields[fname] and not is_private then
                    seen_fields[fname] = true
                    local ftype = (field.extends and field.extends.view) or "any"
                    ftype = ftype:gsub("|", "\\|")
                    local fdesc = (field.desc or ""):gsub("\n", " "):gsub("|", "\\|")
                    emit(string.format("| `%s` | `%s` | %s |", fname, ftype, fdesc))
                end
            end
            emit("")
        end
    end

    emit("---")
    emit("")

    -- Type Aliases
    if #aliases > 0 then
        emit("## Type Aliases & Callbacks")
        emit("")
        emit("| Type Alias | Signature / Definition |")
        emit("| :--- | :--- |")
        for _, alias in ipairs(aliases) do
            local aname = alias.name or (alias.defines and alias.defines[1] and alias.defines[1].view) or "Unknown"
            local def1 = alias.defines and alias.defines[1]
            local sig = (def1 and def1.view) or "any"
            sig = sig:gsub("|", "\\|")
            emit(string.format("| `%s` | `%s` |", aname, sig))
        end
        emit("")
        emit("---")
        emit("")
    end

    -- Helper to render a function entry
    local function render_func(fn)
        local fname = fn.name or (fn.defines and fn.defines[1] and fn.defines[1].name)
        local def = fn.defines and fn.defines[1]
        local ext = def and def.extends

        emit("#### `" .. tostring(fname) .. "`")
        emit("")

        local desc = (def and def.rawdesc) or (fn.desc) or ""
        -- Strip any trailing raw enum code block that LuaLS appends to rawdesc
        if desc:find("\n\n```lua") then
            desc = desc:sub(1, desc:find("\n\n```lua") - 1)
        end
        desc = desc:gsub("^%s+", ""):gsub("%s+$", "")

        if desc ~= "" then
            emit(desc)
            emit("")
        end

        -- Signature
        if ext and ext.view then
            emit("```lua")
            emit(ext.view)
            emit("```")
            emit("")
        end

        -- Parameters
        if ext and ext.args and #ext.args > 0 then
            emit("**Parameters:**")
            emit("")
            for _, arg in ipairs(ext.args) do
                local aname = arg.name or "?"
                local atype = arg.view or "any"
                local adesc = arg.desc or arg.rawdesc or ""
                if adesc ~= "" then
                    emit(string.format("* `%s` (`%s`): %s", aname, atype, adesc))
                else
                    emit(string.format("* `%s` (`%s`)", aname, atype))
                end
            end
            emit("")
        end

        -- Returns
        if ext and ext.returns then
            local rets = ext.returns
            if rets.type then rets = {rets} end
            if #rets > 0 then
                emit("**Returns:**")
                emit("")
                for _, ret in ipairs(rets) do
                    local rname = ret.name
                    local rtype = ret.view or "any"
                    local rdesc = ret.desc or ret.rawdesc or ""
                    if rname and rname ~= "" then
                        if rdesc ~= "" then
                            emit(string.format("* `%s` (`%s`): %s", rname, rtype, rdesc))
                        else
                            emit(string.format("* `%s` (`%s`)", rname, rtype))
                        end
                    else
                        if rdesc ~= "" then
                            emit(string.format("* `%s`: %s", rtype, rdesc))
                        else
                            emit(string.format("* `%s`", rtype))
                        end
                    end
                end
                emit("")
            end
        end
    end

    -- Group Functions
    local groups = {
        {
            title = "Core & Model API",
            desc = "Model registration, format switching (GLB multi-track vs. B3D single-track), "
                .. "model redirects, animation tracks, and skin textures.",
            match = function(n)
                return (n:find("model") or n:find("animation") or n:find("texture"))
                    and not (n:find("proxy") or n:find("observer") or n:find("bone"))
            end
        },
        {
            title = "Visual Proxies & Observers API",
            desc = "Dual-model visual proxy entities (`x_player_api:visual_glb`, `x_player_api:visual_b3d`), "
                .. "observer cohort management (`set_observers`) for Luanti 5.17.0+ modern vs legacy clients, "
                .. "and bone override dispatching with network throttling.",
            match = function(n)
                return n:find("proxy") or n:find("proxies") or n:find("observer")
                    or n:find("cohort") or n:find("bone") or n:find("client")
            end
        },
        {
            title = "Locomotion & Action Controls API",
            desc = "Input control handlers, high-level semantic locomotion/action state evaluation, "
                .. "custom evaluators, social emotes, and reaction triggers.",
            match = function(n)
                return n:find("control") or n:find("state") or n:find("emote") or n:find("hurt")
                    or n:find("bow") or n:find("item_action") or n:find("action") or n:find("globalstep")
                    or n:find("locomotion") or n:find("evaluator")
                    or n:find("equip") or n:find("sound") or n:find("item_cache")
                    or n:find("weapon_categor")
            end
        },
        {
            title = "Eating & Consumables API",
            desc = "Consumable items registry, particle generators, authentic crumb/liquid particle spawning, "
                .. "and eating animation triggers.",
            match = function(n)
                return n:find("eat") or n:find("consumable") or n:find("particle")
            end
        },
        {
            title = "3D Wield Item API",
            desc = "Native 3D wielded item rendering via ephemeral Arm_Right child LuaEntity, "
                .. "attachment positioning, rotation offsets, and visibility control.",
            match = function(n)
                return n:find("wield")
            end
        }
    }

    local assigned = {}
    for _, grp in ipairs(groups) do
        emit("## " .. grp.title)
        emit("")
        emit(grp.desc)
        emit("")
        for _, fn in ipairs(functions) do
            local fn_name = fn.name or ""
            if not assigned[fn_name] and grp.match(fn_name) then
                assigned[fn_name] = true
                render_func(fn)
            end
        end
        emit("---")
        emit("")
    end

    -- Remaining functions
    local remaining = {}
    for _, fn in ipairs(functions) do
        local fn_name = fn.name or ""
        if not assigned[fn_name] then
            table.insert(remaining, fn)
        end
    end
    if #remaining > 0 then
        emit("## Miscellaneous Functions")
        emit("")
        for _, fn in ipairs(remaining) do
            render_func(fn)
        end
        emit("---")
        emit("")
    end

    -- Registries & State Tables
    emit("## Registries & State Tables")
    emit("")
    emit("| Registry / Table | Type | Description |")
    emit("| :--- | :--- | :--- |")
    for _, var in ipairs(variables) do
        local vname = var.name or ""
        local def = var.defines and var.defines[1]
        local vtype = (def and def.extends and def.extends.view) or (def and def.view) or "table"
        vtype = vtype:gsub("|", "\\|")
        local vdesc = (def and def.rawdesc) or (var.desc) or ""
        vdesc = vdesc:gsub("\n", " "):gsub("|", "\\|")
        emit(string.format("| `%s` | `%s` | %s |", vname, vtype, vdesc))
    end
    emit("")

    local content = table.concat(lines, "\n")
    local mdOk, mdErr = util.saveFile(mdPath, content)

    if not (jsonOk and mdOk) then
        return false, {jsonPath, mdPath}, {jsonErr, mdErr}
    end

    return true, {jsonPath, mdPath}
end
