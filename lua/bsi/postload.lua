local logger = require("bsi.logger")
local levels = logger.levels

-- setup log file
logger:init({
    log_level =  levels.DEBUG,
    log_file_path = '/tmp/nvimlogger'
})

