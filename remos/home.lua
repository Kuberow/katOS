local tui = require("touchui")
local container = require("touchui.containers")
local input = require("touchui.input")
local list = require("touchui.lists")
local draw = require("draw")
local popups = require("touchui.popups")

-- Create window for home content (leave space for dock at bottom)
local termW, termH = term.getSize()
local dockHeight = 3
local homeWin = window.create(term.current(), 1, 1, termW, termH - dockHeight)

---@class Shortcut
---@field icon BLIT?
---@field iconFile string?
---@field label string
---@field path string

local function saveShortcuts(shortcuts)
    for i, v in ipairs(shortcuts) do
        v.icon = nil
    end
    assert(remos.saveTable("config/home_apps.table", shortcuts, false))
end

local defaultIcon = assert(remos.loadTransparentBlit("icons/default.icon"))
local unknownIcon = assert(remos.loadTransparentBlit("icons/missing.icon"))

local function loadShortcuts()
    ---@type Shortcut[]
    local shortcuts = assert(remos.loadTable("config/home_apps.table"))
    for i, v in ipairs(shortcuts) do
        if v.iconFile then
            v.icon = remos.loadTransparentBlit(v.iconFile) or unknownIcon
        end
    end
    return shortcuts
end

local shortcuts = loadShortcuts()
local gridList

-- Window control buttons state
local windowState = {
    maximized = false,
    minimized = false,
    originalSize = {w = termW, h = termH},
    originalPos = {x = 1, y = 1}
}

---Update/create/delete a shortcut
---@param index integer
---@param label string?
---@param path string?
---@param iconSmallFile string?
---@param iconLargeFile string?
local function shortcutMenu(index, label, path, iconSmallFile, iconLargeFile)
    -- macOS-style window with proper control buttons
    local rootWin = window.create(term.current(), 3, 3, termW - 4, termH - 6)
    local rootVbox = container.vBox()
    rootVbox:setWindow(rootWin)
    
    -- Draw macOS-style window background
    rootWin.setBackgroundColor(colors.white)
    rootWin.setTextColor(colors.black)
    rootWin.clear()
    
    -- Title bar with proper control buttons
    local w, h = rootWin.getSize()
    
    -- Title bar background
    rootWin.setCursorPos(1, 1)
    rootWin.setBackgroundColor(colors.gray)
    for x = 1, w do
        rootWin.setCursorPos(x, 1)
        rootWin.write(" ")
    end
    
    -- Control buttons (left side - macOS style)
    local buttonY = 1
    rootWin.setCursorPos(2, buttonY)
    rootWin.setBackgroundColor(colors.red)
    rootWin.write(" × ") -- Close
    
    rootWin.setCursorPos(6, buttonY)
    rootWin.setBackgroundColor(colors.yellow)
    rootWin.write(" - ") -- Minimize
    
    rootWin.setCursorPos(10, buttonY)
    rootWin.setBackgroundColor(colors.lime)
    rootWin.write(" + ") -- Maximize
    
    -- Window title (centered)
    rootWin.setBackgroundColor(colors.gray)
    rootWin.setTextColor(colors.white)
    local title = index <= #shortcuts and "Edit Shortcut" or "New Shortcut"
    rootWin.setCursorPos(math.floor((w - #title) / 2), 1)
    rootWin.write(title)

    -- Content area
    local contentWin = window.create(rootWin, 1, 2, w, h - 1)
    contentWin.setBackgroundColor(colors.white)
    contentWin.setTextColor(colors.black)
    contentWin.clear()
    
    rootVbox:setWindow(contentWin)

    local labelInput = input.inputWidget("Label")
    rootVbox:addWidget(labelInput)
    labelInput:setValue(label or "")

    local pathPicker = input.fileWidget("Path", nil, nil, "lua")
    pathPicker.selected = path
    rootVbox:addWidget(pathPicker)

    local iconFilePicker = input.fileWidget("Icon", nil, nil, "icon", nil, "icons")
    iconFilePicker.selected = iconSmallFile
    rootVbox:addWidget(iconFilePicker)

    -- Buttons container
    local buttonContainer = container.hBox()
    rootVbox:addWidget(buttonContainer)

    local deleteButton = input.buttonWidget("Delete", function(self)
        table.remove(shortcuts, index)
        saveShortcuts(shortcuts)
        shortcuts = loadShortcuts()
        gridList:setTable(shortcuts)
        rootVbox.exit = true
    end)
    buttonContainer:addWidget(deleteButton)

    local cancelButton = input.buttonWidget("Cancel", function(self)
        rootVbox.exit = true
    end)
    buttonContainer:addWidget(cancelButton)
    
    local saveButton = input.buttonWidget("Save", function(self)
        if type(labelInput.value) == "string" and type(pathPicker.selected) == "string" then
            shortcuts[index] = {
                label = labelInput.value,
                path = pathPicker.selected,
                iconFile = iconFilePicker.selected
            }
        else
            remos.addAppFile("remos/popup.lua", "Error!",
                "Label and Path are both required to be filled to save this shortcut!")
        end
        saveShortcuts(shortcuts)
        shortcuts = loadShortcuts()
        gridList:setTable(shortcuts)
        rootVbox.exit = true
    end)
    buttonContainer:addWidget(saveButton)

    -- Handle control button clicks
    local function handleControlClick(x, y)
        if y == 1 then
            if x >= 2 and x <= 4 then -- Close button
                rootVbox.exit = true
            elseif x >= 6 and x <= 8 then -- Minimize button
                -- For now, just close since we don't have proper window management
                rootVbox.exit = true
            elseif x >= 10 and x <= 12 then -- Maximize button
                -- Toggle between original and maximized size
                if rootWin.getSize() == termW - 4 and termH - 6 then
                    rootWin.reposition(1, 1, termW, termH)
                else
                    rootWin.reposition(3, 3, termW - 4, termH - 6)
                end
            end
        end
    end

    -- Custom event handler for control buttons
    local originalEvent = rootVbox.event
    rootVbox.event = function(self, event, ...)
        if event == "mouse_click" then
            local button, x, y = ...
            local winX, winY = rootWin.getPosition()
            local absX, absY = x - winX + 1, y - winY + 1
            handleControlClick(absX, absY)
        end
        return originalEvent(self, event, ...)
    end

    tui.run(rootVbox, true, nil, true)
end

settings.define("remos.home.large_icons", {
    description = "Use large icons for home screen (3x3 instead of 4x4)",
    type = "boolean",
    default = false
})

local homeSize = 4
if settings.get("remos.home.large_icons") then
    homeSize = 3
end

local strings = require "cc.strings"

gridList = list.gridListWidget(shortcuts, homeSize, homeSize, function(win, x, y, w, h, item, theme)
    local icon = item.icon or defaultIcon
    local iconx = math.floor((w - 5) / 2)
    local wrapped = strings.wrap(item.label, w - 1)
    local totalh = 3 + #wrapped
    local icony = math.max(math.floor((h - totalh) / 2), 1)
    draw.draw_blit(x + iconx, icony + y, icon, win)
    for i, t in ipairs(wrapped) do
        local toy = icony + i + 2
        if toy > h then
            break
        end
        local ty = toy + y
        local tx = x + math.floor((w - #t) / 2)
        draw.text(tx, ty, t, win)
    end
end, function(index, item)
    remos.addAppFile(item.path)
end, function(index, item)
    shortcutMenu(index, item.label, item.path, item.iconSmallFile, item.iconLargeFile)
end)
gridList:setWindow(homeWin)

-- Enhanced dock drawing function
local function drawDock()
    local dockWin = window.create(term.current(), 1, termH - dockHeight + 1, termW, dockHeight)
    
    -- Clear dock area
    dockWin.setBackgroundColor(colors.black)
    dockWin.clear()
    
    -- Draw dock background with gradient effect
    for y = 1, dockHeight do
        dockWin.setCursorPos(1, y)
        if y == 1 then
            dockWin.setBackgroundColor(colors.gray)
        else
            dockWin.setBackgroundColor(colors.lightGray)
        end
        for x = 1, termW do
            dockWin.write(" ")
        end
    end
    
    -- Draw separator line
    dockWin.setCursorPos(1, 1)
    dockWin.setBackgroundColor(colors.black)
    dockWin.setTextColor(colors.gray)
    for x = 1, termW do
        dockWin.write("▀")
    end
    
    -- Draw app icons in dock (first few shortcuts)
    local dockApps = math.min(#shortcuts, 6) -- Reduced for better spacing
    local totalWidth = dockApps * 6 + (dockApps - 1) * 2
    local startX = math.floor((termW - totalWidth) / 2)
    
    for i = 1, dockApps do
        local item = shortcuts[i]
        local icon = item.icon or defaultIcon
        local x = startX + (i - 1) * 8
        
        -- Draw icon background (rounded effect)
        dockWin.setBackgroundColor(colors.lightGray)
        for dy = 2, dockHeight do
            dockWin.setCursorPos(x, dy)
            dockWin.write("  ")
            dockWin.setCursorPos(x + 3, dy)
            dockWin.write("  ")
        end
        
        -- Draw icon (simplified representation)
        dockWin.setCursorPos(x + 1, 3)
        dockWin.setBackgroundColor(colors.lightGray)
        dockWin.setTextColor(colors.blue)
        dockWin.write("[")
        dockWin.setTextColor(colors.black)
        dockWin.write(string.sub(item.label, 1, 1))
        dockWin.setTextColor(colors.blue)
        dockWin.write("]")
        
        -- Draw app label below icon
        if #item.label > 0 then
            dockWin.setCursorPos(x, dockHeight)
            dockWin.setBackgroundColor(colors.lightGray)
            dockWin.setTextColor(colors.black)
            local displayLabel = string.sub(item.label, 1, 4)
            dockWin.write(" " .. displayLabel .. " ")
        end
    end
    
    -- Page indicators
    if gridList and gridList.pages and gridList.pages > 1 then
        local str = ""
        for i = 1, gridList.pages do
            if gridList.page == i then
                str = str .. "●"
            else
                str = str .. "○"
            end
            if i < gridList.pages then
                str = str .. " "
            end
        end
        dockWin.setCursorPos(math.floor((termW - #str) / 2), 2)
        dockWin.setTextColor(colors.black)
        dockWin.setBackgroundColor(colors.lightGray)
        dockWin.write(str)
    end
    
    -- System info on right side
    local timeText = textutils.formatTime(os.time("local"), false)
    dockWin.setCursorPos(termW - #timeText - 1, 2)
    dockWin.setTextColor(colors.black)
    dockWin.setBackgroundColor(colors.lightGray)
    dockWin.write(timeText)
end

-- Window control functions
local function toggleMaximize()
    if windowState.maximized then
        -- Restore original size
        homeWin.reposition(windowState.originalPos.x, windowState.originalPos.y, 
                          windowState.originalSize.w, windowState.originalSize.h)
        windowState.maximized = false
    else
        -- Save current state and maximize
        windowState.originalSize.w, windowState.originalSize.h = homeWin.getSize()
        windowState.originalPos.x, windowState.originalPos.y = homeWin.getPosition()
        homeWin.reposition(1, 1, termW, termH - dockHeight)
        windowState.maximized = true
    end
    drawDock()
end

local function minimizeApp()
    windowState.minimized = true
    -- In a real system, this would hide the window
    -- For now, we'll just clear and show a message
    homeWin.setBackgroundColor(colors.black)
    homeWin.clear()
    homeWin.setCursorPos(2, math.floor((termH - dockHeight) / 2))
    homeWin.setTextColor(colors.white)
    homeWin.write("App minimized - click to restore")
end

local function closeApp()
    -- In a real system, this would exit the app
    -- For now, we'll just clear and exit the event loop
    homeWin.setBackgroundColor(colors.black)
    homeWin.clear()
    homeWin.setCursorPos(2, math.floor((termH - dockHeight) / 2))
    homeWin.setTextColor(colors.white)
    homeWin.write("App closed")
    os.sleep(2)
    return true -- Signal to exit
end

-- Custom run loop that includes dock rendering and window controls
local function runWithDock()
    parallel.waitForAny(
        function()
            tui.run(gridList, nil, function(event)
                if event == "settings_update" then
                    homeSize = 4
                    if settings.get("remos.home.large_icons") then
                        homeSize = 3
                    end
                    gridList:updateGridSize(homeSize, homeSize)
                    shortcuts = loadShortcuts()
                    gridList:setTable(shortcuts)
                    defaultIcon = assert(remos.loadTransparentBlit("icons/default.icon"))
                elseif event == "add_home_shortcut" then
                    shortcutMenu(#shortcuts + 1)
                elseif event == "window_maximize" then
                    toggleMaximize()
                elseif event == "window_minimize" then
                    minimizeApp()
                elseif event == "window_close" then
                    if closeApp() then
                        return true
                    end
                end
                drawDock()
            end, true)
        end,
        function()
            while true do
                local event, param1, param2, param3 = os.pullEvent()
                if event == "mouse_click" then
                    local button, x, y = param1, param2, param3
                    -- Check if click is in dock area for quick app launches
                    if y >= termH - dockHeight + 2 and y <= termH then
                        local dockApps = math.min(#shortcuts, 6)
                        local totalWidth = dockApps * 6 + (dockApps - 1) * 2
                        local startX = math.floor((termW - totalWidth) / 2)
                        
                        for i = 1, dockApps do
                            local appX = startX + (i - 1) * 8
                            if x >= appX and x <= appX + 5 and y >= termH - 1 then
                                remos.addAppFile(shortcuts[i].path)
                                break
                            end
                        end
                    end
                end
                drawDock()
            end
        end
    )
end

-- Initial draw
drawDock()
runWithDock()
