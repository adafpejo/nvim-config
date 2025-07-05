local logger = require("bsi.logger")
local levels = require("bsi.logger.level")

-- setup log file
logger:init({
    log_level =  levels.DEBUG,
    log_file_path = '/tmp/nvimlogger'
})

