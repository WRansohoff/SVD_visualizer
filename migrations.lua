local schema = require( "lapis.db.schema" )
local types = schema.types

return {
  [ 1 ] = function()
    schema.create_table( "devices", {
      { "id", types.serial },
      { "name", types.varchar },
      { "import_state", types.varchar },
      "PRIMARY KEY (id)"
    } )
    schema.create_index( "devices", "name" );
  end
}
