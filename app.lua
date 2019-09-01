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

-- POST method to create a new 'device' database entry.
app:post("/new_device/:name", function(self)
  -- Simple string sanitization and checking. TODO: Use gsub w/ [A-Za-z0-9]?
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

  -- Return success.
  return { status = 200, json = { name = self.params.name } }
end)

-- POST method to delete a 'device' database entry.
app:post("/delete_device/:id", function(self)
  -- Make sure that the ID is a number, not an SQL injection.
  local device_id = tonumber( self.params.id )
  -- Find the requested device. (TODO: make sure it exists.)
  local dev_to_del = Device:find( device_id )

  -- Delete associated files.
  os.execute( 'rm -rf static/devices/' .. device_id )
  -- Delete database entry.
  dev_to_del:delete()

  -- Return success.
  return { status = 200 }
end)

-- Action to check the current import status of a Device.
app:get("/device_attrs/:id", function(self)
  -- Make sure that the ID is a number, not an SQL injection.
  local device_id = tonumber( self.params.id )
  -- Find the requested device. (TODO: make sure it exists.)
  local dev = Device:find( device_id )

  -- 'Pre-import' state: the user should be prompted to upload a file.
  if ( dev.import_state == "PRE" ) then
    return { status = 200, json = { state = "pre_upload" } }
  -- 'Processing' state: file has not been processed into JSON yet.
  elseif ( dev.import_state == "PROC" ) then
    return { status = 200, json = { state = "processing" } }
  -- 'Done' state: the device JSON is ready to render.
  elseif ( dev.import_state == "DONE" ) then
    return { status = 200, json = { state = "done" } }
  end
end)

-- POST method to upload an SVD file.
app:post("/device_upload/:id", function(self)
  -- Make sure that the Device ID is a number, not an SQL injection.
  local device_id = tonumber( self.params.id )
  -- Find the requested device. (TODO: make sure it exists.)
  local dev = Device:find( device_id )

  -- If a file is being processed for this device, reject the upload.
  if ( dev.import_state == "PROC" ) then
    return { status = 403, json = { error = "Error: An SVD file is already being processed for this device. Please wait for it to complete." } }
  end

  -- Save the uploaded file if it was uploaded successfully.
  futil.ensure_dir_exists( "static/devices/" .. device_id )
  if self.params.file and
     self.params.file.content and
     #self.params.file.content > 0 then
    -- Save it as [number].svd. TODO: should I use the name instead?
    local svd_path = "static/devices/" .. device_id ..
                      "/" .. device_id .. ".svd"
    futil.write_new_file( svd_path, self.params.file.content )
    -- Mark the device as 'ready to process' now that the file exists.
    dev:update( { import_state = "PROC" } )
  end

  -- Load the homepage.
  return { redirect_to = "/" }
end)

-- Action to process an SVD file into JSON.
-- The JSON is saved to disk, so this only runs once per device.
app:get( "/process_device/:id" , function( self )
  -- Make sure that the Device ID is a number, not an SQL injection.
  local device_id = tonumber( self.params.id )
  -- Find the requested device. (TODO: make sure it exists.)
  local dev = Device:find( device_id )

  -- Ensure that the device's SVD file still exists.
  if not futil.path_exists( "static/devices/" .. device_id ..
                            "/" .. device_id .. ".svd" ) then
    -- Revert to 'pre-processing' state if the SVD file is missing.
    -- The user will need to re-upload it.
    dev:update( { import_state = "PRE" } )
    return { status = 404, json = { error = { "Could not find uploaded SVD file; reverting to pre-upload state." } } }
  end

  -- Run the SVD file through the Rust parser. (TODO: Error checking)
  os.execute( 'static/rust/svd_reader/target/debug/svd_reader' ..
              'static/devices/' .. device_id ..
              '/' .. device_id .. '.svd' )
  -- Rename the output file once it finishes.
  -- (TODO: Update the Rust parser to do this)
  os.rename( 'static/devices/' .. device_id .. '/' ..
             device_id .. '.svd.json', 'static/devices/' ..
             device_id .. '/' .. device_id .. '.json' )

  -- Mark the device as 'done processing' and return success.
  dev:update( { import_state = "DONE" } )
  return { status = 200 }
end)

-- Fetch the raw JSON associated with a Device.
-- (TODO: I think this is unused)
app:get( "/device_json/:id" , function( self )
  -- Make sure that the Device ID is a number, not an SQL injection.
  local device_id = tonumber( self.params.id )
  -- Find the requested device. (TODO: make sure it exists.)
  local dev = Device:find( device_id )

  -- Open the JSON file.
  local json_f = io.open( "static/devices/" .. device_id ..
                          "/" .. device_id .. ".json", 'r' )
  -- Ensure that the file was opened successfully.
  if not json_f then
    -- Return 'not found' if the file couldn't be opened.
    return { status = 404,
             json = { error = "Couldn't find processed JSON file." } }
  end
  -- Read the file.
  local json_str = json_f:read( "*all" )
  -- We're done with the file now, so close it.
  json_f:close()

  -- Parse the JSON string into a table.
  local json_j = json.decode( json_str )
  -- Return failure if the parsing failed.
  if not json_j then
    return { status = 500,
             json = { error = "Couldn't parse processed JSON file." } }
  end

  -- Return the parsed JSON.
  return { status = 200, json = json_j }
end)

-- Action to render an HTML view for a Device.
app:get( "/device_html/:id/:type" , function( self )
  -- Make sure that the Device ID is a number, not an SQL injection.
  local device_id = tonumber( self.params.id )
  -- Find the requested device. (TODO: make sure it exists.)
  local dev = Device:find( device_id )

  -- Open the JSON file.
  local json_f = io.open( "static/devices/" .. device_id ..
                          "/" .. device_id .. ".json", 'r' )
  -- Ensure that the file was opened successfully.
  if not json_f then
    return { status = 404,
             json = { error = "Couldn't find processed JSON file." } }
  end
  -- Read the file, then close it.
  local json_str = json_f:read( "*all" )
  json_f:close()

  -- Parse the JSON string into a JSON table.
  device = json.decode( json_str )
  -- Return failure if the parsing failed.
  if not device then
    return { status = 500,
             json = { error = "Couldn't parse processed JSON file." } }
  end

  -- Render the requested device HTML, and return it.
  if self.params.type == 'tree' then
    return { render = "device_tree_view" }
  elseif self.params.type == 'grid' then
    return { render = "device_grid_view" }
  else
    return { status = 404,
             json = { error = "Unrecognized view type." } }
  end
end)

return app
