local window_manager = require("remos.window_manager")

local app_window = {}

function app_window.runApp(title, appPath, ...)
    local args = {...}
    
    local function drawAppContent(contentWin)
        -- Save original term
        local originalTerm = term.current()
        
        -- Redirect to content window
        term.redirect(contentWin)
        
        -- Run the app
        local success, err = pcall(function()
            os.run({}, appPath, unpack(args))
        end)
        
        -- Restore original term
        term.redirect(originalTerm)
        
        if not success then
            printError("App error: " .. err)
        end
    end
    
    local windowInfo = window_manager.createWindow(title, nil, nil, 40, 20, drawAppContent)
    window_manager.redrawAll()
    
    return windowInfo
end

return app_window
