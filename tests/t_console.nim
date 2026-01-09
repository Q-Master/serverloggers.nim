import ../serverloggers

var logger = newConsoleLogger()
logger.open()
logger.tag("key", "value")
logger.tag("key1", 8)
log(lvlDebug, "Test log")
logger.close()
