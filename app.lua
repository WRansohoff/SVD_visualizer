-- Required Lua/Lapis includes
local lapis = require("lapis")
local config = require("lapis.config").get()
-- Import bit32 library globally for use in etlua templates.
bit32 = require("bit32")
-- Utilities
local futil = require("modules/file_util")
-- 3rd-party
local json = require("modules/3p/json/json")

-- Initial Application setup.
local app = lapis.Application()

-- Database models.
local Device = require("models/device")

-- Enable ETLua templating and set a default layout.
app:enable("etlua")
app.layout = require "views.layout_default"

-- Default index page.
app:get("/", function(self)
  -- Display an error message if appropriate.
  err_msg = self.session.err_msg
  self.session.err_msg = nil

  -- Set the web page's title.
  page_title = 'SVD Visualizer'

  -- Load available devices.
  devices = Device:select( "" );

  return { render = "main" }
end)

app:post("/new_device/:name", function(self)
  if string.match( self.params.name, ";" ) then
    return { status = 403, json = { error = "Don't be a jerk, please..." } }
  elseif string.match( self.params.name, " " ) then
    return { status = 400, json = { error = "Invalid device name." } }
  elseif next( Device:select( "where name = ?", self.params.name ) ) then
    return { status = 400, json = { error = "Device with that name already exists." } }
  end
  -- Create the new database entry.
  local new_device = Device:create( {
    name = self.params.name,
    import_state = "PRE"
  } )
  return { status = 200, json = { name = self.params.name } }
end)

app:post("/delete_device/:id", function(self)
  local device_id = tonumber( self.params.id )
  local dev_to_del = Device:find( device_id )
  -- Delete associated files. (TODO: How safe is this rm command?)
  os.execute( 'rm -rf static/devices/' .. device_id )
  -- Delete database entry.
  dev_to_del:delete()
  return { status = 200 }
end)

app:get("/device_attrs/:id", function(self)
  local device_id = tonumber( self.params.id )
  local dev = Device:find( device_id )
  if ( dev.import_state == "PRE" ) then
    return { status = 200, json = { state = "pre_upload" } }
  elseif ( dev.import_state == "PROC" ) then
    return { status = 200, json = { state = "processing" } }
  elseif ( dev.import_state == "DONE" ) then
    -- TODO: Load JSON file and return it.
    return { status = 200, json = { state = "done", device_json = { } } }
  end
end)

app:post("/device_upload/:id", function(self)
  local device_id = tonumber( self.params.id )
  local dev = Device:find( device_id )
  if ( dev.import_state == "PROC" ) then
    return { status = 403, json = { error = "Error: An SVD file is already being processed for this device. Please wait for it to complete." } }
  end
  -- Save the uploaded file.
  futil.ensure_dir_exists( "static/devices/" .. device_id )
  if self.params.file and self.params.file.content and #self.params.file.content > 0 then
    local svd_path = "static/devices/" .. device_id .. "/" .. device_id .. ".svd"
    futil.write_new_file( svd_path, self.params.file.content )
    -- Mark the device as 'ready to process' now that the file exists.
    dev:update( { import_state = "PROC" } )
  end
  return { redirect_to = "/" }
end)

app:get( "/process_device/:id" , function( self )
  local device_id = tonumber( self.params.id )
  local dev = Device:find( device_id )
  -- Ensure that the device's SVD file still exists.
  if not futil.path_exists( "static/devices/" .. device_id .. "/" .. device_id .. ".svd" ) then
    dev:update( { import_state = "PRE" } )
    return { status = 404, json = { error = { "Could not find uploaded SVD file; reverting to pre-upload state." } } }
  end
  -- Run it through the Rust parser. (TODO: Error checking)
  os.execute( 'static/rust/svd_reader/target/debug/svd_reader static/devices/' .. device_id .. '/' .. device_id .. '.svd' )
  -- Rename the output file once it finishes. (TODO: Update the Rust parser to do this)
  os.rename( 'static/devices/' .. device_id .. '/' .. device_id .. '.svd.json', 'static/devices/' .. device_id .. '/' .. device_id .. '.json' )
  -- Mark the device as 'done processing'.
  dev:update( { import_state = "DONE" } )
  return { status = 200 }
end)

app:get( "/device_json/:id" , function( self )
  local device_id = tonumber( self.params.id )
  local dev = Device:find( device_id )
  -- Open the JSON file.
  local json_f = io.open( "static/devices/" .. device_id .. "/" .. device_id .. ".json", 'r' )
  -- (Ensure that the file exists)
  if not json_f then
    return { status = 404, json = { error = "Could not find processed JSON file." } }
  end
  -- Read the file.
  local json_str = json_f:read( "*all" )
  json_f:close()
  -- Parse it into JSON.
  local json_j = json.decode( json_str )
  if not json_j then
    return { status = 500, json = { error = "Could not parse processed JSON file." } }
  end
  -- Return the parsed JSON.
  return { status = 200, json = json_j }
end)

app:get( "/device_tree_html/:id" , function( self )
  local device_id = tonumber( self.params.id )
  local dev = Device:find( device_id )
  -- Open the JSON file.
  local json_f = io.open( "static/devices/" .. device_id .. "/" .. device_id .. ".json", 'r' )
  -- (Ensure that the file exists)
  if not json_f then
    return { status = 404, json = { error = "Could not find processed JSON file." } }
  end
  -- Read the file.
  local json_str = json_f:read( "*all" )
  json_f:close()
  -- Parse it into JSON.
  device = json.decode( json_str )
  if not device then
    return { status = 500, json = { error = "Could not parse processed JSON file." } }
  end
  -- Render the 'device_tree_view' page.
  return { render = "device_tree_view" }
end)

-- TODO: Merge this with the above method.
app:get( "/device_grid_html/:id" , function( self )
  local device_id = tonumber( self.params.id )
  local dev = Device:find( device_id )
  -- Open the JSON file.
  local json_f = io.open( "static/devices/" .. device_id .. "/" .. device_id .. ".json", 'r' )
  -- (Ensure that the file exists)
  if not json_f then
    return { status = 404, json = { error = "Could not find processed JSON file." } }
  end
  -- Read the file.
  local json_str = json_f:read( "*all" )
  json_f:close()
  -- Parse it into JSON.
  device = json.decode( json_str )
  if not device then
    return { status = 500, json = { error = "Could not parse processed JSON file." } }
  end
  -- Render the 'device_grid_view' page.
  return { render = "device_grid_view" }
end)

return app
