local file_util = {}

-- Return truth-y if the file path exists, nil if it doesn't.
function file_util.path_exists( path_str )
  -- Simple sanitation.
  local actual_path = path_str:gsub( "[^a-zA-Z0-9_/%.]", "" )
  -- Assume that invalid paths don't exist.
  if actual_path ~= path_str then return nil end
  -- Check whether the path name exists with 'os.rename'.
  return os.rename( actual_path, actual_path )
end

-- Attempt to create a directory.
function file_util.create_directory( dir_str )
  -- Simple sanitation.
  local actual_dir = dir_str:gsub( "[^a-zA-Z0-9_/]", "" )
  -- Ignore invalid names.
  if actual_dir ~= dir_str then return end
  -- Try to make the directory. TODO: Return truth-y/false-y?
  os.execute( 'mkdir -p ' .. actual_dir )
end

-- Try to ensure that a directory exists.
-- Return true if it exists or was created.
-- Return false if it does not exist and couldn't be created.
function file_util.ensure_dir_exists( dir_str )
  -- Simple sanitation.
  local actual_dir = dir_str:gsub( "[^a-zA-Z0-9_/]", "" )
  -- Ignore invalid names.
  if actual_dir ~= dir_str then return false end
  -- Return true if the directory exists already.
  if file_util.path_exists( actual_dir ) then return true
  -- Otherwise, try to create it.
  else
    file_util.create_directory( actual_dir )
    if file_util.path_exists( actual_dir ) then
      return true
    else
      return false
    end
  end
end

-- Create a new file with the provided string contents.
-- Return true if the file was written, false if not.
function file_util.write_new_file( file_path, contents )
  -- Simple sanitation.
  local actual_path = file_path:gsub( "[^a-zA-Z0-9_/%.]", "" )
  -- Ignore invalid filenames.
  if file_path ~= actual_path then return false end
  -- Create and write to the file. TODO: Error checking.
  local f = io.open( actual_path, 'w' )
  f:write( contents )
  f:close()
  return true
end

return file_util
