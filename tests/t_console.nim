import ../serverloggers

var logger = newConsoleLogger()
logger.open()
log(lvlDebug, "Test log")
logger.close()
